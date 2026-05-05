import Foundation
import Combine

// MARK: - Models
struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant, typing }
    let id = UUID()
    let role: Role
    let text: String
}

// MARK: - Mock Ingestion Service
final class MockIngestionService {
    // Duration range in seconds; default 1.5–3.0
    var minDelay: TimeInterval = 1.5
    var maxDelay: TimeInterval = 3.0

    func ingest(url: URL) async throws {
        let delay = Double.random(in: minDelay...maxDelay)
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}

// MARK: - Mock Chat Service
final class MockChatService {
    private let responses: [String] = [
        "This section discusses key concepts from your document.",
        "The document mentions several important points related to your query.",
        "Relevant content found on page 2 (mock).",
        "Here's a concise summary related to your question (mock).",
        "Cross-referencing sections suggests a few insights (mock)."
    ]
    private var index: Int = 0

    func reply(to message: String) async -> String {
        // Deterministic rotation
        let response = responses[index % responses.count]
        index += 1
        // Simulate short thinking delay 0.8–1.2s
        let delay = Double.random(in: 0.8...1.2)
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return response
    }
}
