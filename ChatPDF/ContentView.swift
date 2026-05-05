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
                switch appVM.phase {
                case .setupLLM:
                    ModelDownloadView(state: appVM.llmDownloadState) {
                        appVM.downloadLLM()
                    } onCancel: {
                        appVM.cancelLLMDownload()
                    }
                    .transition(.opacity.combined(with: .scale))
                case .upload:
                    VStack {
                        UploadView { url in
                            Task {
                                try await vecturaService?.clearAll()
                                appVM.handleFile(url: url)
                            }
                        } onError: { err in
                            self.appVM.showError(err)
                        }
                        .transition(.opacity.combined(with: .scale))
                        .disabled(appVM.error != nil)
                        
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
            .alert(isPresented: $appVM.showError, error: appVM.error) { _ in
                Button(role: .close) {
                    self.appVM.showError = false
                }
            } message: { err in
                Text(err.localizedDescription)
            }
            .toolbarRole(.automatic)
            .toolbar(content: toolbarContent)
            .task(id: "Initialization", priority: .high) {
                do {
                    let vectura = try await VecturaService()
                    self.vecturaService = vectura
                    self.appVM = AppViewModel(ingestionService: vectura)
                    self.chatVM.initializeChatService(vectura)
                } catch {
                    print(error)
                    self.appVM = AppViewModel()
                    self.appVM.showError(error)
                }
            }
        }
        .preferredColorScheme(.light)
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
