//
//  ContentView.swift
//  ChatPDF
//
//  Created by Sharan Thakur on 01/05/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State var vecturaService: VecturaService?
    @State private var appVM = AppViewModel()
    @State private var chatVM = ChatViewModel()
    @State private var navigator = PDFNavigator()
    @State private var showOpenPanel = false
    @State private var confirmNewChat = false
    @State private var isDropTargeted = false

    private var canOpen: Bool { appVM.phase == .upload || appVM.phase == .main }

    var body: some View {
        NavigationStack {
            phaseContent
                .modifier(chromeModifier)
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        if let startupError = appVM.startupError {
            StartupErrorView(message: startupError) {
                Task { await initialize() }
            }
        } else {
            switch appVM.phase {
            case .setupLLM:
                ModelDownloadView(state: appVM.llmDownloadState) {
                    appVM.downloadLLM()
                } onChooseFolder: { url in
                    appVM.useLocalModel(url: url)
                } onCancel: {
                    appVM.cancelLLMDownload()
                }
                .transition(.opacity)
            case .upload:
                UploadView { url in
                    openDocument(url)
                } onError: { err in
                    self.appVM.showError(err)
                }
                .transition(.opacity)
            case .loading:
                LoadingView(fileName: appVM.selectedFileURL?.lastPathComponent)
                    .transition(.opacity)
            case .main:
                mainContent
                    .transition(.opacity)
            }
        }
    }

    private var mainContent: some View {
        MainSplitView(fileURL: appVM.selectedFileURL, chatVM: $chatVM, navigator: navigator)
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                openDocument(url)
                return true
            } isTargeted: { isDropTargeted = $0 }
    }

    private var menuActions: ChatActions {
        var actions = ChatActions()
        if appVM.phase == .main { actions.newChat = { requestNewChat() } }
        if canOpen { actions.openPDF = { showOpenPanel = true } }
        return actions
    }

    private var chromeModifier: ChromeModifier {
        ChromeModifier(
            appVM: appVM,
            showOpenPanel: $showOpenPanel,
            confirmNewChat: $confirmNewChat,
            actions: menuActions,
            requestNewChat: { requestNewChat() },
            startNewChat: { startNewChat() },
            openDocument: { openDocument($0) },
            initialize: { await initialize() }
        )
    }

    /// Replaces whatever is open with this PDF.
    private func openDocument(_ url: URL) {
        guard url.pathExtension.lowercased() == "pdf" else {
            appVM.showError(IngestError.notAPDF)
            return
        }
        Task {
            do {
                try await vecturaService?.clearAll()
                chatVM.reset()
                appVM.handleFile(url: url)
            } catch {
                appVM.showError(error)
            }
        }
    }

    private func requestNewChat() {
        if chatVM.messages.isEmpty {
            startNewChat()
        } else {
            confirmNewChat = true
        }
    }

    private func startNewChat() {
        appVM.newChat()
        chatVM.reset()
    }

    /// Starts the search engine. On failure the app stays on an explanatory screen (no mock fallback).
    func initialize() async {
        do {
            let vectura = try await VecturaService()
            self.vecturaService = vectura
            self.appVM = AppViewModel(ingestionService: vectura)
            self.chatVM.initializeChatService(vectura)
            self.appVM.restoreLocalModel()
        } catch {
            print(error)
            self.appVM = AppViewModel()
            self.appVM.startupError = VecturaService.startupMessage(for: error)
        }
    }
}

/// Title, toolbar, alert, dialogs and menu-bar actions around the phase content.
private struct ChromeModifier: ViewModifier {
    @Bindable var appVM: AppViewModel
    @Binding var showOpenPanel: Bool
    @Binding var confirmNewChat: Bool
    let actions: ChatActions
    let requestNewChat: () -> Void
    let startNewChat: () -> Void
    let openDocument: (URL) -> Void
    let initialize: () async -> Void

    func body(content: Content) -> some View {
        content
            .alert(isPresented: $appVM.showError, error: appVM.error) { _ in
                Button("Close", role: .close) {
                    appVM.dismissError()
                }
            } message: { err in
                Text(err.localizedDescription)
            }
            .navigationTitle(appVM.phase == .main ? (appVM.selectedFileURL?.lastPathComponent ?? "") : "")
            .navigationSubtitle(appVM.phase == .main ? "Runs on this Mac" : "")
            .toolbar {
                if appVM.phase == .main {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Chat", systemImage: "square.and.pencil", action: requestNewChat)
                            .help("Close this PDF and start a new chat (⌘N)")
                    }
                }
            }
            .confirmationDialog("Start a new chat?", isPresented: $confirmNewChat) {
                Button("New Chat", role: .destructive, action: startNewChat)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This closes the PDF and clears the conversation.")
            }
            .fileImporter(isPresented: $showOpenPanel, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url): openDocument(url)
                case .failure(let err): appVM.showError(err)
                }
            }
            .focusedSceneValue(\.chatActions, actions)
            .task(id: "Initialization", priority: .high) {
                await initialize()
            }
    }
}

struct StartupErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("ChatPDF couldn't start")
                .font(.headline)
            Text(.init(message))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
                .textSelection(.enabled)
            Button("Try Again", systemImage: "arrow.clockwise", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MainSplitView: View {
    let fileURL: URL?
    @Binding var chatVM: ChatViewModel
    var navigator: PDFNavigator

    var body: some View {
        HSplitView {
            PDFPreview(url: fileURL, navigator: navigator)
                .frame(minWidth: 320, idealWidth: 560)
            ChatView(viewModel: $chatVM, navigator: navigator)
                .frame(minWidth: 320, idealWidth: 460)
        }
    }
}

#Preview {
    ContentView()
}
