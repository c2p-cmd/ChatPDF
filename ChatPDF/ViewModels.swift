import Foundation
import SwiftUI
import Combine

enum AppPhase {
    case upload
    case loading
    case main
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var phase: AppPhase = .upload
    @Published var selectedFileURL: URL? = nil

    private let ingestionService: MockIngestionService

    init(ingestionService: MockIngestionService = MockIngestionService()) {
        self.ingestionService = ingestionService
    }

    func handleFile(url: URL) {
        guard url.pathExtension.lowercased() == "pdf" else { return }
        selectedFileURL = url
        withAnimation(.easeInOut(duration: 0.25)) {
            phase = .loading
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.ingestionService.ingest(url: url)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.phase = .main
                    }
                }
            } catch {
                // For prototype, return to upload on error
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.phase = .upload
                    }
                }
            }
        }
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var input: String = ""

    private let chatService: MockChatService

    init(chatService: MockChatService = MockChatService()) {
        self.chatService = chatService
    }

    func send() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let userMsg = ChatMessage(role: .user, text: trimmed)
        messages.append(userMsg)
        input = ""

        // Typing indicator
        messages.append(ChatMessage(role: .typing, text: ""))

        Task { [weak self] in
            guard let self else { return }
            let reply = await self.chatService.reply(to: trimmed)
            await MainActor.run {
                // Remove typing indicator if present
                if let idx = self.messages.firstIndex(where: { $0.role == .typing }) {
                    self.messages.remove(at: idx)
                }
                self.messages.append(ChatMessage(role: .assistant, text: reply))
            }
        }
    }
}
