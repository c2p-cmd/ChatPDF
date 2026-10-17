//
//  IntentRouter.swift
//  ChatPDF
//

import Foundation
import VecturaKit

enum QueryIntent: String {
    case general
    case topical
    case unrelated
}

/// Nearest-centroid intent classifier built on the app's existing embedder.
actor IntentRouter {
    private let embedder: any VecturaEmbedder
    private var centroids: [QueryIntent: [Float]] = [:]

    /// Minimum cosine margin a non-topical class needs over "topical".
    private let margin: Float = 0.04

    private static let examples: [QueryIntent: [String]] = [
        .general: [
            "What is this document about?",
            "Summarize this PDF",
            "Give me an overview",
            "What are the main points?",
            "Tell me about this paper",
            "What is the gist of this file?",
            "TL;DR of the document",
            "What topics does this cover?"
        ],
        .topical: [
            "What does the author say about the methodology?",
            "How many participants were in the study?",
            "What is the definition of the term used in section 2?",
            "What results were reported for the experiment?",
            "Who is responsible for the payment terms?",
            "Explain the algorithm described on page 3",
            "What are the limitations mentioned?",
            "When was the agreement signed?"
        ],
        .unrelated: [
            "What's the weather today?",
            "Write me a poem about cats",
            "Who won the football match last night?",
            "Tell me a joke",
            "What is the capital of France?",
            "How do I cook pasta?",
            "Write a Python script to sort a list",
            "What's your favorite color?"
        ]
    ]

    init(embedder: any VecturaEmbedder) {
        self.embedder = embedder
    }

    func classify(_ message: String) async -> QueryIntent {
        do {
            try await buildCentroidsIfNeeded()
            guard let q = try await embedder.embed(texts: [message]).first else { return .topical }

            let scores = centroids.mapValues { Self.cosine(q, $0) }
            guard let topical = scores[.topical] else { return .topical }

            // Only leave "topical" when another class clearly wins.
            let best = scores
                .filter { $0.key != .topical }
                .max { $0.value < $1.value }
            if let best, best.value - topical >= margin {
                return best.key
            }
            return .topical
        } catch {
            print("Intent routing failed: \(error)")
            return .topical
        }
    }

    private func buildCentroidsIfNeeded() async throws {
        guard centroids.isEmpty else { return }
        var built: [QueryIntent: [Float]] = [:]
        for (intent, phrases) in Self.examples {
            let vectors = try await embedder.embed(texts: phrases)
            guard let first = vectors.first else { continue }
            var sum = [Float](repeating: 0, count: first.count)
            for v in vectors {
                for i in 0..<sum.count { sum[i] += v[i] }
            }
            built[intent] = sum
        }
        centroids = built
    }

    private static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<min(a.count, b.count) {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = (na * nb).squareRoot()
        return denom > 0 ? dot / denom : 0
    }
}
