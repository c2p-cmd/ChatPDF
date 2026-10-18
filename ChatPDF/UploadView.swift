import SwiftUI
import UniformTypeIdentifiers

struct UploadView: View {
    let onFileChosen: (URL) -> Void
    let onError: (Error) -> Void

    @State private var isTargeted = false
    @State private var showImporter = false
    @State private var errorText: String? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: isTargeted ? "arrow.down.doc.fill" : "doc.badge.plus")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            Text(isTargeted ? "Release to open" : "Drop a PDF here")
                .font(.headline)
            Text("or")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Choose PDF…") {
                errorText = nil
                showImporter = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Label("Your document stays on this Mac.", systemImage: "lock")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                            style: StrokeStyle(lineWidth: isTargeted ? 3 : 1.5, dash: [7, 5])
                        )
                }
                .padding(24)
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            errorText = nil
            return handleDrop(providers)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                if url.pathExtension.lowercased() == "pdf" {
                    onFileChosen(url)
                } else {
                    errorText = "Please choose a .pdf file."
                }
            case .failure(let err):
                onError(err)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let item = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            errorText = "Please drop a PDF file."
            return false
        }
        item.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, err in
            let url: URL? = {
                if let url = data as? URL { return url }
                if let data = data as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
                return nil
            }()
            Task { @MainActor in
                if let err {
                    errorText = "Couldn’t read that file."
                    onError(err)
                } else if let url, url.pathExtension.lowercased() == "pdf" {
                    errorText = nil
                    onFileChosen(url)
                } else {
                    errorText = "Please drop a .pdf file."
                }
            }
        }
        return true
    }
}

#Preview {
    UploadView { _ in } onError: { _ in }
}
