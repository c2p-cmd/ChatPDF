//
//  ContentView.swift
//  ChatPDF
//
//  Created by Sharan Thakur on 01/05/26.
//

import SwiftUI

struct ContentView: View {
    @State var vecturaService: VecturaService?
    @State private var appVM = AppViewModel()
    @State private var chatVM = ChatViewModel()

    var body: some View {
        NavigationStack {
            Group {
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
                    .transition(.opacity.combined(with: .scale))
                case .upload:
                    VStack {
                        UploadView { url in
                            Task {
                                do {
                                    try await vecturaService?.clearAll()
                                    appVM.handleFile(url: url)
                                } catch {
                                    appVM.showError(error)
                                }
                            }
                        } onError: { err in
                            self.appVM.showError(err)
                        }
                        .transition(.opacity.combined(with: .scale))
                        
                        if let error = appVM.error {
                            Spacer()
                            
                            Text(error.message)
                                .font(.title)
                                .foregroundStyle(.red)
                                .fontWeight(.semibold)
                        }
                    }
                case .loading:
                    LoadingView(title: "Processing document...")
                        .transition(.opacity)
                case .main:
                    MainSplitView(fileURL: appVM.selectedFileURL, chatVM: $chatVM)
                        .transition(.opacity)
                }
                }
            }
            .alert(isPresented: $appVM.showError, error: appVM.error) { _ in
                Button(role: .close) {
                    self.appVM.dismissError()
                }
            } message: { err in
                Text(err.localizedDescription)
            }
            .toolbarRole(.automatic)
            .toolbar(content: toolbarContent)
            .task(id: "Initialization", priority: .high) {
                await initialize()
            }
        }
        .preferredColorScheme(.light)
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

    func toolbarContent() -> some View {
        Group {
            if appVM.phase == .main {
                Button("New Chat", systemImage: "square.and.pencil") {
                    self.appVM.newChat()
                    self.chatVM.reset()
                }
            }
        }
    }
}

struct StartupErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.orange)
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

    var body: some View {
        GeometryReader { geo in
            HSplitView {
                PDFPreview(url: fileURL)
                    .frame(minWidth: geo.size.width * 0.5)
                ChatView(viewModel: $chatVM)
                    .frame(minWidth: geo.size.width * 0.4)
            }
            .frame(width: geo.size.width)
            .background(Color(hex: 0xF6F7FB))
        }
    }
}

#Preview {
    ContentView()
}
