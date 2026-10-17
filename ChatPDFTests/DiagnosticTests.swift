import Foundation
import PDFKit
import Testing
import VecturaKit
@testable import ChatPDF

private struct EvalQ { let q: String; let any: [String] }

private let evalSet: [EvalQ] = [
    .init(q: "What were the Research Objectives?", any: ["Investigate and quantify"]),
    .init(q: "Who wrote this paper?", any: ["Aromal Baby"]),
    .init(q: "Who are the authors?", any: ["Aromal Baby"]),
    .init(q: "Which professor supervised the course?", any: ["William Morrison"]),
    .init(q: "What is the null hypothesis?", any: ["no significant difference"]),
    .init(q: "What are the research questions?", any: ["retention compared to traditional learning"]),
    .init(q: "What is the title of the paper?", any: ["Impact of Gamification"]),
    .init(q: "What were the independent variables?", any: ["Independent variables"]),
    .init(q: "Which dataset of student grades was used?", any: ["grades of the students"]),
]

private struct DocEval { let file: String; let qs: [EvalQ] }
private let allEvals: [DocEval] = [
    .init(file: "Mini_Research_paper.pdf", qs: evalSet),
    .init(file: "An_Empirical_Study_of_Compute_Platform_Influence_on_5G_gNB_Performance_and_Energy_Efficiency_Using_srsRAN.pdf", qs: [
        .init(q: "What throughput did the Raspberry Pi achieve?", any: ["33.8", "32–38"]),
        .init(q: "Why did the Raspberry Pi sessions fail?", any: ["USB disconnection", "host controller", "USB transfers", "instability"]),
        .init(q: "Which UE was used in the testbed?", any: ["Nokia X30"]),
        .init(q: "What power meter was used?", any: ["power meter"]),
    ]),
    .init(file: "5G Assessment Technical Report.pdf", qs: [
        .init(q: "Which tool provides the SIP registrar and proxy?", any: ["Kamailio"]),
        .init(q: "What clustering algorithm was used and what k was chosen?", any: ["K-Means", "k = 4"]),
        .init(q: "How many GTP-U flows were clustered?", any: ["342"]),
    ]),
    .init(file: "Scikit_Learn_Cheat_Sheet_Python.pdf", qs: [
        .init(q: "How do I create a KNN classifier in scikit-learn?", any: ["KNeighborsClassifier"]),
        .init(q: "How do I get a classification report?", any: ["classification_report"]),
    ]),
]

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["RUN_DIAG"] == "1"))
struct DiagnosticTests {
    private func fixture(_ name: String) -> URL {
        let root = Bundle(for: DiagToken.self).resourceURL!
        return FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.first { $0.lastPathComponent == name }!
    }

    @Test func compareRetrievalSettings() async throws {
        let variants: [(String, VecturaService.Tuning)] = [
            ("chunk256 (current)", .init()),
            ("chunk256+dropRefs", .init(excludeReferences: true)),
            ("chunk384+dropRefs", .init(chunkSize: 384, excludeReferences: true)),
            ("chunk512+dropRefs", .init(chunkSize: 512, excludeReferences: true)),
            ("chunk512", .init(chunkSize: 512)),
        ]
        for (name, tuning) in variants {
            let service = try await VecturaService(tuning: tuning)
            var total = 0, hits = 0
            var missed: [String] = []
            var ctxTokens: [Int] = []
            for d in allEvals {
                try await service.clearAll()
                try await service.ingest(url: fixture(d.file))
                for e in d.qs {
                    let selected = VecturaService.selectContext(try await service.retrieve(e.q, limit: 5))
                    ctxTokens.append(await service.tokenCount(selected.map(\.text).joined(separator: " ")))
                    total += 1
                    if selected.contains(where: { r in e.any.contains { r.text.localizedCaseInsensitiveContains($0) } }) { hits += 1 } else { missed.append(e.q) }
                }
            }
            print("EVAL \(name): \(hits)/\(total) avgContextTokens=\(ctxTokens.reduce(0, +) / max(ctxTokens.count, 1)) missed=\(missed)")
        }
    }
}
private final class DiagToken {}
