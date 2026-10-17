//
//  LLMBenchmarkTests.swift
//  ChatPDFTests
//
//  Opt-in LLM benchmark through the real pipeline (routing + retrieval + prompt + generation).
//  Needs an unsandboxed host to read the model directory:
//    TEST_RUNNER_RUN_BENCH=1 TEST_RUNNER_MODEL_DIR=/path TEST_RUNNER_MODEL_NAME=x TEST_RUNNER_OUT=/tmp/x.json \
//    xcodebuild test ... ENABLE_APP_SANDBOX=NO
//

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXLMTokenizers
import Testing
import VecturaKit
@testable import ChatPDF

private struct BenchCase: Codable {
    let doc: String          // fixture file name
    let question: String
    let expected: String     // "topical" | "general" | "unrelated"
    let mustContain: [String] // any-of; empty = no fact check
}

private struct BenchRow: Codable {
    let question: String
    let expectedIntent: String
    let usedIntent: String
    let latencySeconds: Double
    let promptTokens: Int
    let generatedTokens: Int
    let promptSeconds: Double
    let decodeTokensPerSecond: Double
    let factOK: Bool?
    let hasThinkTag: Bool
    let truncated: Bool
    let sourceCount: Int
    let answer: String
    let rawOutput: String
}

private struct BenchReport: Codable {
    let model: String
    let loadSeconds: Double
    let peakMemoryGB: Double
    let rows: [BenchRow]
}

private let srs = "An_Empirical_Study_of_Compute_Platform_Influence_on_5G_gNB_Performance_and_Energy_Efficiency_Using_srsRAN.pdf"
private let rep = "5G Assessment Technical Report.pdf"
private let gam = "Mini_Research_paper.pdf"

private let benchCases: [BenchCase] = [
    .init(doc: srs, question: "What throughput did the Raspberry Pi achieve?", expected: "topical", mustContain: ["33.8", "32"]),
    .init(doc: srs, question: "Why did the Raspberry Pi sessions fail?", expected: "topical", mustContain: ["USB"]),
    .init(doc: srs, question: "Which UE was used in the testbed?", expected: "topical", mustContain: ["Nokia X30"]),
    .init(doc: srs, question: "How much lower was the Raspberry Pi's power consumption?", expected: "topical", mustContain: ["five", "5"]),
    .init(doc: srs, question: "What is this document about?", expected: "general", mustContain: ["Raspberry", "srsRAN", "5G"]),
    .init(doc: srs, question: "Summarize this paper in a few sentences", expected: "general", mustContain: ["Raspberry", "notebook", "x86"]),
    .init(doc: srs, question: "Write me a poem about cats", expected: "unrelated", mustContain: []),
    .init(doc: rep, question: "Which tool is used as the SIP registrar and proxy?", expected: "topical", mustContain: ["Kamailio"]),
    .init(doc: rep, question: "What clustering algorithm was used and which k was chosen?", expected: "topical", mustContain: ["K-Means", "k = 4", "4"]),
    .init(doc: rep, question: "How many flows were clustered?", expected: "topical", mustContain: ["342"]),
    .init(doc: rep, question: "What MOS did RTPengine report?", expected: "topical", mustContain: ["4.3"]),
    .init(doc: rep, question: "Give me an overview of this report", expected: "general", mustContain: ["5G", "SIP", "Open5GS"]),
    .init(doc: gam, question: "What were the Research Objectives?", expected: "topical", mustContain: ["Investigate", "impact of a gamified"]),
    .init(doc: gam, question: "And questions?", expected: "topical", mustContain: ["retention compared to traditional", "research question", "?"]),
    .init(doc: gam, question: "Who wrote this paper?", expected: "topical", mustContain: ["Aromal", "Sharan"]),
    .init(doc: gam, question: "What is the null hypothesis?", expected: "topical", mustContain: ["no significant difference"]),
    .init(doc: gam, question: "What is the capital of France?", expected: "unrelated", mustContain: []),
]

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["RUN_BENCH"] == "1"))
struct LLMBenchmarkTests {
    private func fixture(_ name: String) -> URL {
        let root = Bundle(for: BenchToken.self).resourceURL!
        return FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.first { $0.lastPathComponent == name }
            ?? root.appendingPathComponent(name)
    }

    @Test func benchmark() async throws {
        let env = ProcessInfo.processInfo.environment
        let dir = try #require(env["MODEL_DIR"])
        let name = env["MODEL_NAME"] ?? URL(fileURLWithPath: dir).lastPathComponent
        let out = env["OUT"] ?? "/tmp/bench_\(name).json"

        let service = try await VecturaService()

        let t0 = Date()
        let container = try await loadModelContainer(
            from: URL(fileURLWithPath: dir), using: TokenizersLoader())
        let loadSeconds = Date().timeIntervalSince(t0)
        await service.setLLM(container)
        print("BENCH loaded \(name) in \(loadSeconds)s")

        // warm-up so first-call kernel compilation doesn't pollute latency
        try await service.clearAll()
        try await service.ingest(url: fixture(srs))
        _ = await service.reply(to: "Which UE was used in the testbed?")

        var rows: [BenchRow] = []
        var currentDoc = ""
        for c in benchCases {
            if c.doc != currentDoc {
                try await service.clearAll()
                try await service.ingest(url: fixture(c.doc))
                currentDoc = c.doc
            }
            let start = Date()
            let answer = await service.reply(to: c.question)
            let latency = Date().timeIntervalSince(start)
            let g = await service.lastGeneration
            let stats = g
            let decodeTPS = (stats?.generateSeconds ?? 0) > 0 ? Double(stats!.generatedTokens) / stats!.generateSeconds : 0
            let fact: Bool? = c.mustContain.isEmpty ? nil
                : c.mustContain.contains { answer.finalAnswer.localizedCaseInsensitiveContains($0) }
            let row = BenchRow(
                question: c.question,
                expectedIntent: c.expected,
                usedIntent: stats?.intent ?? "unrelated(no-llm)",
                latencySeconds: latency,
                promptTokens: stats?.promptTokens ?? 0,
                generatedTokens: stats?.generatedTokens ?? 0,
                promptSeconds: stats?.promptSeconds ?? 0,
                decodeTokensPerSecond: decodeTPS,
                factOK: fact,
                hasThinkTag: (stats?.rawOutput ?? "").contains("<think>"),
                truncated: (stats?.generatedTokens ?? 0) >= (stats?.intent == "general" ? 700 : 400),
                sourceCount: answer.sources.count,
                answer: answer.finalAnswer,
                rawOutput: stats?.rawOutput ?? ""
            )
            rows.append(row)
            print("BENCH \(String(format: "%5.1fs", latency)) \(row.usedIntent) :: \(c.question)")
        }

        let report = BenchReport(
            model: name, loadSeconds: loadSeconds,
            peakMemoryGB: Double(Memory.peakMemory) / 1_073_741_824, rows: rows)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(report).write(to: URL(fileURLWithPath: out))
        print("BENCH wrote \(out)")
    }
}

private final class BenchToken {}
