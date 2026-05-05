import Foundation
import SwiftUI
import Combine
import Observation

enum AppPhase {
    case setupLLM
    case upload
    case loading
    case main
}

enum LLMDownloadState: Equatable {
    case unavailable
    case idle
    case downloading(ModelDownloadProgress)
    case ready
}

struct ModelDownloadProgress: Equatable {
    let fractionCompleted: Double
    let completedUnitCount: Int64
    let totalUnitCount: Int64

    init(
        fractionCompleted: Double = 0,
        completedUnitCount: Int64 = 0,
        totalUnitCount: Int64 = 0
    ) {
        self.fractionCompleted = min(max(fractionCompleted, 0), 1)
        self.completedUnitCount = max(completedUnitCount, 0)
        self.totalUnitCount = max(totalUnitCount, 0)
    }

    init(_ progress: Progress) {
        let fraction = progress.fractionCompleted.isFinite ? progress.fractionCompleted : 0

        self.init(
            fractionCompleted: fraction,
            completedUnitCount: progress.completedUnitCount,
            totalUnitCount: progress.totalUnitCount
        )
    }
}

@MainActor
@Observable
final class AppViewModel<Ingestor: IngestService> {
    var phase: AppPhase = .setupLLM
    var selectedFileURL: URL? = nil
    var error: CustomError? = nil
    var showError: Bool = false
    var llmDownloadState: LLMDownloadState = .unavailable

    private let ingestionService: IngestService
    private let llmDownloadService: LLMDownloadService?
    private var llmDownloadTask: Task<Void, Never>?
    private var llmDownloadGeneration = 0

    init(ingestionService: VecturaService) {
        self.ingestionService = ingestionService
        self.llmDownloadService = ingestionService
        self.phase = .setupLLM
        self.llmDownloadState = .idle
    }
    
    init(ingestionService: Ingestor = MockIngestionService()) {
        self.ingestionService = ingestionService
        self.llmDownloadService = nil
        self.llmDownloadState = .unavailable
    }

    func newChat() {
        self.showError = false
        self.error = nil
        self.phase = .upload
        self.selectedFileURL = nil
    }

    func downloadLLM() {
        guard let llmDownloadService else {
            showError("LLM download is unavailable.")
            return
        }

        if case .downloading = llmDownloadState {
            return
        }

        llmDownloadState = .downloading(ModelDownloadProgress())
        phase = .setupLLM
        llmDownloadGeneration += 1
        let generation = llmDownloadGeneration

        llmDownloadTask = Task {
            do {
                try await llmDownloadService.downloadLLM { progress in
                    let downloadProgress = ModelDownloadProgress(progress)

                    Task { @MainActor in
                        guard self.llmDownloadGeneration == generation else { return }
                        self.llmDownloadState = .downloading(downloadProgress)
                    }
                }

                await MainActor.run {
                    guard self.llmDownloadGeneration == generation else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.llmDownloadState = .ready
                        self.phase = .upload
                        self.llmDownloadTask = nil
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard self.llmDownloadGeneration == generation else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.llmDownloadState = .idle
                        self.llmDownloadTask = nil
                    }
                }
            } catch {
                print(error)
                await MainActor.run {
                    guard self.llmDownloadGeneration == generation else { return }
                    self.llmDownloadState = .idle
                    self.llmDownloadTask = nil
                    self.showError(error)
                }
            }
        }
    }

    func cancelLLMDownload() {
        llmDownloadGeneration += 1
        llmDownloadTask?.cancel()
        llmDownloadTask = nil

        if case .downloading = llmDownloadState {
            withAnimation(.easeInOut(duration: 0.25)) {
                llmDownloadState = .idle
            }
        }
    }
    
    func handleFile(url: URL) {
        guard llmDownloadState == .ready || llmDownloadState == .unavailable else {
            self.phase = .setupLLM
            return
        }

        guard url.pathExtension.lowercased() == "pdf" else {
            self.phase = .upload
            self.showError(IngestError.notAPDF)
            return
        }
        selectedFileURL = url
        withAnimation(.easeInOut(duration: 0.25)) {
            phase = .loading
        }
        Task {
            do {
                try await self.ingestionService.ingest(url: url)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.phase = .main
                    }
                }
            } catch {
                print(error)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.phase = .upload
                        self.showError(error)
                    }
                }
            }
        }
    }
    
    func showError(_ errorText: String) {
        self.error = CustomError(message: errorText)
        self.showError = true
    }
    
    func showError(_ error: Error) {
        self.error = CustomError(error)
        self.showError = true
    }
}

@MainActor
@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var input: String = ""
    
    private var currentTask: Task<Void, Never>?

    private var chatService: VecturaService?
    private let mockChatService = MockChatService()

    init() { }
    
    init(messages: [ChatMessage]) {
        self.messages = messages
    }
    
    func initializeChatService(_ service: VecturaService) {
        self.chatService = service
    }
    
    func reset() {
        messages.removeAll()
    }
    
    var isRunning: Bool {
        currentTask != nil
    }

    func send() {
        self.currentTask?.cancel()
        defer {
            self.currentTask = nil
        }
        self.currentTask = Task {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let userMsg = ChatMessage(role: .user, text: trimmed)
            await MainActor.run {
                messages.append(userMsg)
                input = ""
            }

            // Typing indicator
            await MainActor.run {
                messages.append(ChatMessage(role: .typing, text: ""))
            }

            let reply: ChatAnswer
            if let service = chatService {
                reply = await service.reply(to: trimmed)
            } else {
                reply = await mockChatService.reply(to: trimmed)
            }
            await MainActor.run {
                // Remove typing indicator if present
                self.messages.removeAll(where: { $0.role == .typing })
                
                self.messages.append(ChatMessage(role: .assistant, answer: reply))
            }
        }
    }
}
