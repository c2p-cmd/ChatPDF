import Foundation
import MLXLMCommon

// MARK: - Models
/// Plain value type used by both the UI and the service actor, so it must not be main-actor isolated.
nonisolated struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role { case user, assistant, typing, system }
    let id: UUID
    let role: Role
    let text: String
    let answer: ChatAnswer?
    
    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
        self.answer = nil
    }
    
    init (id: UUID = UUID(), role: Role, answer: ChatAnswer) {
        self.id = id
        self.role = role
        self.text = answer.finalAnswer
        self.answer = answer
    }
    
    var modelThought: String? {
        self.answer?.thinking
    }
    
    var modelThoughtIsEmpty: Bool {
        modelThought?.isEmpty ?? true
    }
    
    var sources: [String] {
        self.answer?.sources ?? []
    }
    
    func asChatMessage() -> MLXLMCommon.Chat.Message {
        var role: MLXLMCommon.Chat.Message.Role
        switch self.role {
        case .user:
            role = .user
        case .assistant, .typing:
            role = .assistant
        case .system:
            role = .system
        }
        return MLXLMCommon.Chat.Message(role: role, content: self.text)
    }
}

extension [ChatMessage] {
    nonisolated func asChatHistory() -> [MLXLMCommon.Chat.Message] {
        map { $0.asChatMessage() }
    }
}

struct CustomError: Error, LocalizedError {
    let message: String
    let errorDescription: String?
    
    init(message: String) {
        self.message = message
        self.errorDescription = nil
    }
    
    init(_ error: Error) {
        if let localizedError = error as? LocalizedError {
            self.message = localizedError.localizedDescription
            self.errorDescription = localizedError.errorDescription
        } else {
            let nsError = error as NSError
            self.message = nsError.localizedDescription.isEmpty ? "An unexpected error occurred" : nsError.localizedDescription
            self.errorDescription = nsError.localizedFailureReason
        }
    }
}

struct AnswerSource: Hashable {
    let index: Int
    let page: String?
    let chunkID: String?
    let score: Float
}

struct ChunkRecord: Hashable {
    let id: String
    let text: String
    let page: Int
    let chunkIndex: Int
    let source: String
}

nonisolated struct ChatAnswer: Equatable, Sendable {
    let finalAnswer: String
    let thinking: String?
    let sources: [String]
}

// MARK: - Mock Ingestion Service
nonisolated final class MockIngestionService: IngestService {
    // Duration range in seconds; default 1.5–3.0
    var minDelay: TimeInterval = 1.5
    var maxDelay: TimeInterval = 3.0

    func ingest(url: URL) async throws {
        let delay = Double.random(in: minDelay...maxDelay)
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}

// MARK: - Mock Chat Service
actor MockChatService: ChatService {
    private let responses: [String] = [
        "This section discusses key concepts from your document.",
        "The document mentions several important points related to your query.",
        "Relevant content found on page 2 (mock).",
        "Here's a concise summary related to your question (mock).",
        "Cross-referencing sections suggests a few insights (mock)."
    ]
    private var index: Int = 0

    func reply(to message: String, onPartial: (@Sendable (String) -> Void)?) async -> ChatAnswer {
        // Deterministic rotation
        let response = responses[index % responses.count]
        index += 1
        // Simulate short thinking delay 0.8–1.2s
        let delay = Double.random(in: 0.8...1.2)
        // Stream the canned answer word by word so the UI path is exercised without an LLM.
        var shown = ""
        for word in response.split(separator: " ") {
            shown += (shown.isEmpty ? "" : " ") + word
            onPartial?(shown)
            try? await Task.sleep(nanoseconds: UInt64(delay / Double(response.split(separator: " ").count) * 1_000_000_000))
        }
        return ChatAnswer(finalAnswer: response, thinking: "Ahh yes, the user asked a great question.", sources: [
            "[p:1,c:12]",
        ])
    }
}
