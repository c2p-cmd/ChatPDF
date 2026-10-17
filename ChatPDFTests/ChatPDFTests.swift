//
//  ChatPDFTests.swift
//  ChatPDFTests
//

import Foundation
import MLXLMCommon
import Testing
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
