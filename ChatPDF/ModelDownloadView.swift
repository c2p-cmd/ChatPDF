import SwiftUI

struct ModelDownloadView: View {
    let state: LLMDownloadState
    let onDownload: () -> Void
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

    private var byteCountText: String? {
        guard let progress, progress.totalUnitCount > 0 else { return nil }

        let completed = ByteCountFormatStyle(style: .file).format(progress.completedUnitCount)
        let total = ByteCountFormatStyle(style: .file).format(progress.totalUnitCount)

        return "\(completed) of \(total)"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.primary)

            Text("Download chat model")
                .foregroundStyle(Color.primary)
                .font(.headline)

            Text("The model is required before chatting with your PDF.")
                .foregroundStyle(Color.primary.opacity(0.7))
                .font(.subheadline)

            if let progress {
                VStack(spacing: 8) {
                    ProgressView(value: progress.fractionCompleted)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 280)

                    VStack(spacing: 2) {
                        Text(progress.fractionCompleted, format: .percent.precision(.fractionLength(0)))
                            .font(.caption)
                            .foregroundStyle(Color.primary.opacity(0.7))

                        if let byteCountText {
                            Text(byteCountText)
                                .font(.caption2)
                                .foregroundStyle(Color.primary.opacity(0.6))
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button(isDownloading ? "Downloading..." : "Download Model", systemImage: "arrow.down.circle", action: onDownload)
                    .buttonStyle(.borderedProminent)
                    .disabled(isDownloading)

                if isDownloading {
                    Button("Cancel", systemImage: "xmark.circle", role: .cancel, action: onCancel)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ModelDownloadView(state: .downloading(.init(
        fractionCompleted: 0.42,
        completedUnitCount: 1_260_000_000,
        totalUnitCount: 3_000_000_000
    ))) { } onCancel: { }
}
