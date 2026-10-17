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
    case loadingLocal
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

/// Persists the user's chosen model folder across launches (app-scoped security bookmark).
enum ModelBookmark {
    private static let key = "localModelBookmark"

    static func save(_ url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data, options: .withSecurityScope,
            relativeTo: nil, bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale { save(url) }
        return url
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
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

    private var scopedModelURL: URL?

    /// Loads a model from a folder the user picked; remembers it for next launch.
    func useLocalModel(url: URL, restoring: Bool = false) {
        guard let llmDownloadService else {
            showError("Model loading is unavailable.")
            return
        }
        if case .loadingLocal = llmDownloadState { return }
        if case .downloading = llmDownloadState { return }

        scopedModelURL?.stopAccessingSecurityScopedResource()
        let accessing = url.startAccessingSecurityScopedResource()
        scopedModelURL = accessing ? url : nil
        llmDownloadState = .loadingLocal

        Task {
            do {
                try await llmDownloadService.loadLocalLLM(from: url)
                ModelBookmark.save(url)
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.llmDownloadState = .ready
                    self.phase = .upload
                }
            } catch {
                print(error)
                if accessing { url.stopAccessingSecurityScopedResource() }
                self.scopedModelURL = nil
                self.llmDownloadState = .idle
                if restoring {
                    ModelBookmark.clear()  // folder moved or deleted: fall back to the start screen
                } else {
                    self.showError(error)
                }
            }
        }
    }

    /// Re-opens the previously chosen model folder, if any.
    func restoreLocalModel() {
        guard llmDownloadService != nil, let url = ModelBookmark.resolve() else { return }
        useLocalModel(url: url, restoring: true)
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
        guard phase != .loading else { return }
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
    
    func dismissError() {
        self.showError = false
        self.error = nil
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
        currentTask?.cancel()
        currentTask = nil
        messages.removeAll()
    }

    var isRunning: Bool {
        currentTask != nil
    }

    func send() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }

        messages.append(ChatMessage(role: .user, text: trimmed))
        input = ""
        let typing = ChatMessage(role: .typing, text: "")
        messages.append(typing)

        currentTask = Task {
            let reply: ChatAnswer
            if let service = chatService {
                reply = await service.reply(to: trimmed)
            } else {
                reply = await mockChatService.reply(to: trimmed)
            }
            // A cancelled task belongs to a chat that was reset; drop its answer.
            guard !Task.isCancelled else { return }
            messages.removeAll { $0.id == typing.id }
            messages.append(ChatMessage(role: .assistant, answer: reply))
            currentTask = nil
        }
    }
}
