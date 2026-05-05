//
//  Service.swift
//  ChatPDF
//
//  Created by Sharan Thakur on 01/05/26.
//

import Foundation
import HFAPI
import MLXLMHFAPI
import MLXLMTokenizers
import MLXEmbedders
import MLXLLM
import MLXLMCommon
import NaturalLanguage
import PDFKit
import Tokenizers
import VecturaKit
import VecturaMLXKit

protocol ChatService {
    func reply(to message: String) async -> ChatAnswer
}

protocol IngestService {
    func ingest(url: URL) async throws
}

protocol LLMDownloadService {
    func downloadLLM(onProgress: @Sendable @escaping (Progress) -> Void) async throws
}

enum IngestError: Error, LocalizedError, CustomStringConvertible {
    case failedToLoadPDF
    case emptyPDF
    case extractionFailed
    case notAPDF
    
    var errorDescription: String? {
        self.description
    }
    
    var description: String {
        switch self {
        case .failedToLoadPDF:
            "Failed to load PDF"
        case .emptyPDF:
            "PDF is empty"
        case .extractionFailed:
            "Failed to extract text from PDF"
        case .notAPDF:
            "Not a PDF"
        }
    }
}

actor VecturaService: IngestService, ChatService, LLMDownloadService {
    let config: VecturaConfig
    let embedder: MLXEmbedder
    let vectordb: VecturaKit
    let tokenizer: Tokenizers.Tokenizer
    
    private var chunkRecordsByText: [String: ChunkRecord] = [:]
    private var chunkRecordsByID: [String: ChunkRecord] = [:]
    
    var llm: ModelContainer?
    
    let url: URL = Bundle.main.resourceURL!
    
    init() async throws {
        self.config = try VecturaConfig(
            name: "embeddings-collection",
            dimension: nil  // Auto-detect dimension from MLX embedder
        )
        guard Bundle.main.resourceURL != nil else {
            throw URLError(.badURL)
        }
        // Create MLX embedder
        self.embedder = try await MLXEmbedder(configuration: ModelConfiguration(directory: url))
        self.vectordb = try await VecturaKit(config: config, embedder: embedder)
        self.tokenizer = try await AutoTokenizer.from(directory: url)
    }
    
    func downloadLLM(onProgress: @Sendable @escaping (Progress) -> Void) async throws {
        self.llm = try await loadModelContainer(
            from: HubClient.default,
            configuration: LLMRegistry.qwen3_4b_4bit,
            useLatest: true,
            progressHandler: onProgress
        )
    }
    
    /// Split text into chunks with exact token counts
    func split(
        _ text: String,
        maxTokens: Int = 512,
        overlapTokens: Int = 80
    ) -> [String] {
        // Get exact token IDs for the full text
        let tokenIDs = tokenizer.encode(text: text)
        let totalTokens = tokenIDs.count
        
        guard totalTokens > maxTokens else {
            // Text fits in one chunk
            return [text]
        }
        
        let step = maxTokens - overlapTokens
        var chunks: [String] = []
        var startIdx = 0
        
        while startIdx < totalTokens {
            let endIdx = min(startIdx + maxTokens, totalTokens)
            let chunkTokenIDs = Array(tokenIDs[startIdx..<endIdx])
            
            // Decode token IDs back to text
            let chunkText = tokenizer.decode(tokenIds: chunkTokenIDs)
            chunks.append(chunkText)
            
            if endIdx >= totalTokens { break }
            startIdx += step
        }
        
        return chunks
    }
    
    /// Check token count without splitting
    func tokenCount(_ text: String) -> Int {
        return tokenizer.encode(text: text).count
    }
    
    func clearAll() async throws {
        var docCount = try await vectordb.documentCount
        print("Before reset Docs: \(docCount)")
        try await vectordb.reset()
        docCount = try await vectordb.documentCount
        self.chunkRecordsByID.removeAll()
        self.chunkRecordsByText.removeAll()
        print("After reset Docs: \(docCount)")
    }
    
    func ingest(url: URL) async throws {
        // 1. Load PDF
        guard let pdfDocument = PDFDocument(url: url) else {
            throw IngestError.failedToLoadPDF
        }
        
        // 2. Extract text page-by-page to preserve metadata
        var pageTexts: [(text: String, page: Int)] = []
        
        for pageIndex in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex),
                  let pageString = page.string,
                  !pageString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            pageTexts.append((text: pageString, page: pageIndex + 1))
        }
        
        guard !pageTexts.isEmpty else {
            throw IngestError.emptyPDF
        }
        
        // 3. Split into chunks
        var docCount = 0
        var globalChunkIndex = 0

        for pageData in pageTexts {
            let chunkSize = 256
            let overlap = Int(ceil(Double(chunkSize) * 0.15))
            let chunks: [String] = split(pageData.text, maxTokens: chunkSize, overlapTokens: overlap)

            let ids = try await vectordb.addDocuments(texts: chunks)

            for (localIndex, pair) in zip(ids, chunks).enumerated() {
                let (id, chunkText) = pair

                let record = ChunkRecord(
                    id: id.uuidString,
                    text: chunkText,
                    page: pageData.page,
                    chunkIndex: globalChunkIndex,
                    source: url.lastPathComponent
                )

                chunkRecordsByText[chunkText] = record
                chunkRecordsByID[id.uuidString] = record

                print("""
                Added chunk:
                - id: \(id)
                - page: \(pageData.page)
                - localIndex: \(localIndex)
                - globalChunkIndex: \(globalChunkIndex)
                - tokens: \(tokenCount(chunkText))
                - preview: \(chunkText.prefix(120))
                """)
                
                globalChunkIndex += 1
            }

            print("Added: \(ids.count)")
            docCount += chunks.count
        }
        
        // 4. Index into VecturaKit
        print("Ingested \(docCount) chunks from \(url.lastPathComponent)")
    }
    
    private func generate(with container: ModelContainer, prompt: String) async throws -> String {
        try await container.perform { modelContext in
            let input = try await modelContext.processor.prepare(input: .init(prompt: prompt))

            let parameters = GenerateParameters(
                maxTokens: 400,
                temperature: 0.2,
                topP: 0.25,
                topK: 20
            )

            var output = ""

            for await partialGeneration in try MLXLMCommon.generate(
                input: input,
                parameters: parameters,
                context: modelContext
            ) {
                switch partialGeneration {
                case .chunk(let string):
                    output += string

                case .info(let info):
                    print(info.summary())
                    return output

                case .toolCall:
                    continue
                }
            }

            return output
        }
    }
    
    private func cannedResponse(for message: String) -> String? {
        let normalized = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let greetings: Set<String> = [
            "hi", "hello", "hey", "hello there", "good morning", "good evening"
        ]

        if greetings.contains(normalized) {
            return "Hello! How can I help you with the document?"
        }

        let thanks: Set<String> = ["thanks", "thank you", "thx"]
        if thanks.contains(normalized) {
            return "You're welcome."
        }

        return nil
    }

    private func cleanAnswer(_ text: String) -> (thought: String, cleanAnswer: String) {
        let pattern = #"<think>([\s\S]*?)</think>"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (thought: "", cleanAnswer: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        
        var thought = ""
        var cleaned = text
        
        if let match = regex.firstMatch(in: text, options: [], range: fullRange) {
            if let range = Range(match.range(at: 1), in: text) {
                thought = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let range = Range(match.range(at: 0), in: cleaned) {
                cleaned.removeSubrange(range)
            }
        } else if let start = text.range(of: "<think>") {
            thought = String(text[start.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned = String(text[..<start.lowerBound])
        }
        
        cleaned = cleaned
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return (thought: thought, cleanAnswer: cleaned)
    }

    private func makeSearchQuery(_ userQuery: String) -> SearchQuery {
        let task = "Given a user question, retrieve the most relevant passages from the document that answer it."
        let formatted = """
        Instruct: \(task)
        Query: \(userQuery)
        """
        return SearchQuery(stringLiteral: formatted)
    }
    
    private func formatSources(from results: [VecturaSearchResult]) -> [String] {
        let lines = results.enumerated().map { index, result in
            if let record = chunkRecordsByText[result.text] {
                return "[\(index + 1)] page \(record.page), chunk \(record.chunkIndex), score \(String(format: "%.3f", result.score))"
            } else {
                return "[\(index + 1)] score \(String(format: "%.3f", result.score))"
            }
        }

        return lines
    }
    
    func reply(to message: String) async -> ChatAnswer {
        do {
            if let canned = cannedResponse(for: message) {
                return ChatAnswer(finalAnswer: canned, thinking: nil, sources: [])
            }

            guard let llm = self.llm else {
                return ChatAnswer(finalAnswer: "The local language model is not downloaded yet.", thinking: nil, sources: [])
            }

            let query = makeSearchQuery(message)
            let results: [VecturaSearchResult] = try await vectordb.search(query: query, numResults: 5)

            guard !results.isEmpty else {
                return ChatAnswer(finalAnswer: "I could not find that in the document.", thinking: nil, sources: [])
            }

            let topResults = Array(results.prefix(5))
            let selectedResults = topResults.filter { $0.score > 0.22 }.prefix(4)

            let context = selectedResults.enumerated().map { index, result in
                """
                [Source \(index + 1)]
                \(result.text)
                """
            }.joined(separator: "\n\n---\n\n")

            let prompt = """
            You are answering questions about an uploaded PDF.

            Rules:
            - Use only the provided context.
            - Do not show reasoning.
            - Do not include <think> tags.
            - Answer directly in 1 short paragraph or up to 3 bullet points.
            - If the answer is not in the context, say: "I could not find that in the document."

            Context:
            \(context)

            Question:
            \(message)

            Final answer only:
            """

            let rawAnswer = try await generate(with: llm, prompt: prompt)
            let answer = cleanAnswer(rawAnswer)

            if answer.cleanAnswer.isEmpty {
                return ChatAnswer(finalAnswer: "I could not find that in the document.", thinking: nil, sources: [])
            }

            let sources = formatSources(from: topResults)
            return ChatAnswer(finalAnswer: answer.cleanAnswer, thinking: answer.thought, sources: sources)
        } catch {
            print(error)
            return ChatAnswer(finalAnswer: "Problem with handling the query.", thinking: nil, sources: [])
        }
    }
}
