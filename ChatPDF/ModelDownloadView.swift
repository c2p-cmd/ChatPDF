import SwiftUI
import UniformTypeIdentifiers

struct ModelDownloadView: View {
    let state: LLMDownloadState
    let onDownload: () -> Void
    let onChooseFolder: (URL) -> Void
    let onCancel: () -> Void

    private var progress: ModelDownloadProgress? {
        if case .downloading(let value) = state {
            value
        } else {
            nil
        }
    }

    private var isDownloading: Bool {
        progress != nil
    }

    private var isLoadingLocal: Bool {
        state == .loadingLocal
    }

    @State private var showFolderPicker = false

    private var byteCountText: String? {
        guard let progress, progress.totalUnitCount > 0 else { return nil }

        let completed = ByteCountFormatStyle(style: .file).format(progress.completedUnitCount)
        let total = ByteCountFormatStyle(style: .file).format(progress.totalUnitCount)

        return "\(completed) of \(total)"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Download chat model")
                .font(.headline)

            Text("Answers come from a language model that runs on this Mac. It downloads once (a few gigabytes); after that your PDFs and questions never leave this Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if isLoadingLocal {
                ProgressView("Loading model…")
            }

            if let progress {
                VStack(spacing: 8) {
                    ProgressView(value: progress.fractionCompleted)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 280)

                    VStack(spacing: 2) {
                        Text(progress.fractionCompleted, format: .percent.precision(.fractionLength(0)))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let byteCountText {
                            Text(byteCountText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button(isDownloading ? "Downloading…" : "Download Model", systemImage: "arrow.down.circle", action: onDownload)
                    .buttonStyle(.borderedProminent)
                    .disabled(isDownloading || isLoadingLocal)

                Button(isLoadingLocal ? "Loading…" : "Use Local Model Folder…", systemImage: "folder") {
                    showFolderPicker = true
                }
                .buttonStyle(.bordered)
                .disabled(isDownloading || isLoadingLocal)

                // Always laid out so the row doesn't shift when a download starts.
                Button("Cancel", systemImage: "xmark.circle", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                    .opacity(isDownloading ? 1 : 0)
                    .disabled(!isDownloading)
                    .accessibilityHidden(!isDownloading)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { onChooseFolder(url) }
        }
    }
}

#Preview {
    ModelDownloadView(state: .downloading(.init(
        fractionCompleted: 0.42,
        completedUnitCount: 1_260_000_000,
        totalUnitCount: 3_000_000_000
    ))) { } onChooseFolder: { _ in } onCancel: { }
}
