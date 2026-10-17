//
//  TestDocsTests.swift
//  ChatPDFTests
//
//  Runs against the PDFs in ChatPDFTests/Fixtures (copies of test_docs/).
//

import Foundation
import MLXLMCommon
import Testing
import VecturaKit
import VecturaMLXKit
@testable import ChatPDF

private final class BundleToken {}

private enum Doc: String, CaseIterable {
    case report = "5G Assessment Technical Report.pdf"
    case srsran = "An_Empirical_Study_of_Compute_Platform_Influence_on_5G_gNB_Performance_and_Energy_Efficiency_Using_srsRAN.pdf"
    case gamification = "Mini_Research_paper.pdf"
    case sklearn = "Scikit_Learn_Cheat_Sheet_Python.pdf"
    case scanned = "PublicWaterMassMailing.pdf"

    /// The PDFs ship inside the test bundle (ChatPDFTests/Fixtures), since the sandboxed host can't read test_docs/.
    var url: URL {
        let root = Bundle(for: BundleToken.self).resourceURL!
        let found = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .first { $0.lastPathComponent == rawValue }
        return found ?? root.appendingPathComponent(rawValue)
    }
}

/// A question plus words that must appear in the retrieved text if retrieval worked.
private struct RetrievalCase {
    let doc: Doc
    let question: String
    let anyOf: [String]
}

private let retrievalCases: [RetrievalCase] = [
    .init(doc: .srsran, question: "What throughput did the Raspberry Pi achieve?", anyOf: ["33.8", "32–38"]),
    .init(doc: .srsran, question: "Why did the Raspberry Pi sessions fail?", anyOf: ["USB disconnection", "host controller", "USB transfers", "instability"]),
    .init(doc: .srsran, question: "Which UE was used in the testbed?", anyOf: ["Nokia X30"]),
    .init(doc: .report, question: "Which tool provides the SIP registrar and proxy?", anyOf: ["Kamailio"]),
    .init(doc: .report, question: "What clustering algorithm was used on the N3 traffic and what k was chosen?", anyOf: ["K-Means", "k = 4"]),
    .init(doc: .report, question: "How many GTP-U flows were clustered?", anyOf: ["342"]),
    .init(doc: .gamification, question: "What is the null hypothesis?", anyOf: ["Null Hypothesis", "no significant difference"]),
    .init(doc: .gamification, question: "Who is the professor of the course?", anyOf: ["William Morrison"]),
    .init(doc: .sklearn, question: "How do I create a KNN classifier in scikit-learn?", anyOf: ["KNeighborsClassifier"]),
    .init(doc: .sklearn, question: "How do I get a classification report?", anyOf: ["classification_report"]),
]

private func makeService() async throws -> VecturaService {
    try await VecturaService()
}

private func ingest(_ doc: Doc, into service: VecturaService) async throws {
    try await service.clearAll()
    try await service.ingest(url: doc.url)
}

@Suite(.serialized)
struct TestDocsRetrievalTests {
    @Test func fixturesAreReadable() {
        for doc in Doc.allCases {
            #expect(FileManager.default.isReadableFile(atPath: doc.url.path),
                    "Missing fixture \(doc.rawValue)")
        }
    }

    /// The scanned PDF has no text layer; OCR must recover enough text to index and retrieve.
    @Test func scannedPDFIsOCRedAndSearchable() async throws {
        let service = try await makeService()
        try await service.clearAll()
        try await service.ingest(url: Doc.scanned.url)
        let results = try await service.retrieve("water", limit: 5)
        print("OCR retrieval: \(results.count) results, top text: \(results.first?.text.prefix(200) ?? "-")")
        #expect(!results.isEmpty)
        #expect(results.contains { $0.text.split(whereSeparator: \.isWhitespace).count > 20 })
    }

    @Test func retrievalFindsTheAnswerChunk() async throws {
        let service = try await makeService()
        var failures: [String] = []
        for doc in Doc.allCases where doc != .scanned {
            try await ingest(doc, into: service)
            for c in retrievalCases where c.doc == doc {
                let results = try await service.retrieve(c.question, limit: 5)
                let hit = results.contains { r in c.anyOf.contains { r.text.localizedCaseInsensitiveContains($0) } }
                let top = results.first?.score ?? 0
                print("RETRIEVAL [\(hit ? "HIT " : "MISS")] top=\(String(format: "%.3f", top)) \(c.question)")
                if !hit {
                    failures.append(c.question)
                    for r in results { print("   MISS-CHUNK \(String(format: "%.3f", r.score)): \(r.text.prefix(160).replacingOccurrences(of: "\n", with: " "))") }
                }
            }
        }
        #expect(failures.isEmpty, "Missed: \(failures)")
    }

    /// The router's "unrelated" gate relies on off-topic questions scoring below the 0.22 cutoff.
    @Test func retrievalScoresSeparateOnTopicFromOffTopic() async throws {
        let service = try await makeService()
        try await ingest(.srsran, into: service)

        let onTopic = [
            "What throughput did the Raspberry Pi achieve?",
            "What power meter was used?",
            "Which core network was used with srsRAN?",
        ]
        let offTopic = [
            "What is the best recipe for chocolate cake?",
            "Who won the 2018 World Cup?",
            "Write a poem about autumn",
        ]
        var onScores: [Float] = [], offScores: [Float] = []
        for q in onTopic { onScores.append(try await service.retrieve(q).first?.score ?? 0) }
        for q in offTopic { offScores.append(try await service.retrieve(q).first?.score ?? 0) }
        print("RETRIEVAL on-topic top scores: \(onScores) off-topic: \(offScores)")

        #expect(onScores.allSatisfy { $0 > 0.22 }, "on-topic below cutoff: \(onScores)")
        #expect(offScores.allSatisfy { $0 <= 0.22 }, "off-topic above cutoff: \(offScores)")
        #expect((onScores.min() ?? 0) > (offScores.max() ?? 1))
    }
}

@Suite(.serialized)
struct TestDocsIntentTests {
    private static func router() async throws -> IntentRouter {
        let url = try #require(Bundle.main.resourceURL)
        return IntentRouter(embedder: try await MLXEmbedder(configuration: ModelConfiguration(directory: url)))
    }

    private static let cases: [(String, QueryIntent)] = [
        // general
        ("What is this document about?", .general),
        ("Summarize this paper for me", .general),
        ("Give me a short overview of the report", .general),
        ("What are the key takeaways?", .general),
        // topical, drawn from the test docs
        ("What throughput did the Raspberry Pi achieve?", .topical),
        ("Why were USB disconnections observed?", .topical),
        ("Which tool provides the SIP registrar and proxy?", .topical),
        ("What k was chosen for K-Means clustering?", .topical),
        ("What is the null hypothesis?", .topical),
        ("How do I create a KNN classifier?", .topical),
        // unrelated
        ("What's the weather like today?", .unrelated),
        ("Tell me a joke", .unrelated),
        ("Who won the world cup in 2018?", .unrelated),
        ("Write a poem about autumn", .unrelated),
    ]

    @Test func classifierMatchesLabelsOnTestDocQuestions() async throws {
        let router = try await Self.router()
        var wrong: [String] = []
        for (q, expected) in Self.cases {
            let got = await router.classify(q)
            print("INTENT [\(got == expected ? "ok " : "BAD")] expected=\(expected.rawValue) got=\(got.rawValue) :: \(q)")
            if got != expected { wrong.append("\(q) -> \(got.rawValue) (want \(expected.rawValue))") }
        }
        let accuracy = Double(Self.cases.count - wrong.count) / Double(Self.cases.count)
        #expect(accuracy >= 0.85, "accuracy \(accuracy); wrong: \(wrong)")
    }

    @Test func nothingTopicalIsEverRefusedOrSummarised() async throws {
        let router = try await Self.router()
        for (q, expected) in Self.cases where expected == .topical {
            let got = await router.classify(q)
            #expect(got == .topical, "\(q) -> \(got.rawValue)")
        }
    }
}

/// End to end: needs the Qwen3-4B download (~2.3 GB) and runs generation.
/// Opt in with:  TEST_RUNNER_RUN_E2E=1 xcodebuild test ...
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["RUN_E2E"] == "1"))
struct TestDocsEndToEndTests {
    private static func readyService(_ doc: Doc) async throws -> VecturaService {
        let service = try await makeService()
        try await service.downloadLLM { _ in }
        try await ingest(doc, into: service)
        return service
    }

    @Test func topicalQuestionIsAnsweredWithSources() async throws {
        let service = try await Self.readyService(.srsran)
        let answer = await service.reply(to: "What throughput did the Raspberry Pi achieve in the experiments?")
        print("E2E topical: \(answer.finalAnswer)\nsources: \(answer.sources)")
        #expect(!answer.sources.isEmpty)
        #expect(answer.finalAnswer.contains("33.8") || answer.finalAnswer.contains("32") || answer.finalAnswer.contains("Mbps"))
        #expect(!answer.finalAnswer.contains("<think>"))
    }

    @Test func generalQuestionSummarisesTheWholeDocument() async throws {
        let service = try await Self.readyService(.srsran)
        let answer = await service.reply(to: "What is this document about?")
        print("E2E general: \(answer.finalAnswer)")
        let text = answer.finalAnswer.lowercased()
        #expect(text.contains("5g") || text.contains("srsran") || text.contains("raspberry"))
        #expect(!text.contains("could not find"))
    }

    @Test func unrelatedQuestionIsDeclinedWithoutSources() async throws {
        let service = try await Self.readyService(.srsran)
        let answer = await service.reply(to: "Write me a poem about cats")
        print("E2E unrelated: \(answer.finalAnswer)")
        #expect(answer.sources.isEmpty)
        #expect(answer.finalAnswer.contains("related"))
    }

    @Test func differentDocumentsDoNotLeakIntoEachOther() async throws {
        let service = try await Self.readyService(.sklearn)
        let answer = await service.reply(to: "What throughput did the Raspberry Pi achieve?")
        print("E2E cross-doc: \(answer.finalAnswer)")
        #expect(!answer.finalAnswer.contains("33.8"))
    }
}

/// Scores the embedding router on the shared labelled set (also used by scripts/laya_intent_eval.sh).
@Suite(.serialized)
struct IntentSharedSetTests {
    @Test func embeddingRouterOnSharedQuestionSet() async throws {
        let root = Bundle(for: BundleToken.self).resourceURL!
        let tsv = try #require(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.first { $0.lastPathComponent == "intent_questions.tsv" })
        let url = try #require(Bundle.main.resourceURL)
        let embedder = try await MLXEmbedder(configuration: ModelConfiguration(directory: url))
        let router = IntentRouter(embedder: embedder)

        var lines: [String] = []
        var correct = 0, total = 0, badTopical = 0, topical = 0
        var micros: [Double] = []
        for line in try String(contentsOf: tsv, encoding: .utf8).split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let t0 = Date()
            let got = await router.classify(parts[1])
            micros.append(Date().timeIntervalSince(t0) * 1000)
            total += 1
            if got.rawValue == parts[0] { correct += 1 }
            if parts[0] == "topical" { topical += 1; if got != .topical { badTopical += 1 } }
            lines.append("ROUTEREVAL\t\(parts[0])\t\(got.rawValue)\t\(parts[1])")
        }
        lines.forEach { print($0) }
        micros.sort()
        print("ROUTERSUMMARY correct=\(correct) total=\(total) badTopical=\(badTopical)/\(topical) medianMs=\(micros[micros.count / 2]) ")
    }
}
