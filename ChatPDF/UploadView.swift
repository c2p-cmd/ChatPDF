import SwiftUI
import UniformTypeIdentifiers

struct UploadView: View {
    let onFileChosen: (URL) -> Void
    let onError: (Error) -> Void

    @State private var isTargeted = false
    @State private var showImporter = false
    @State private var errorText: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text("Drag & drop a PDF here")
                    .foregroundStyle(Color.primary)
                    .font(.headline)
                Text("or")
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .font(.subheadline)
                Button {
                    errorText = nil
                    showImporter = true 
                } label: {
                    Text("Select File")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                }
                .glassEffect(
                    .regular.tint(Color.accent.opacity(0.12)),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .buttonStyle(.borderedProminent)
            }
            .glassEffect(.clear, in: Rectangle())
            .onDrop(of: [UTType.pdf, UTType.fileURL], isTargeted: $isTargeted) { providers in
                errorText = nil
                return handleDrop(providers)
            }

            if let errorText {
                Text(errorText)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.light)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                if url.pathExtension.lowercased() == "pdf" {
                    onFileChosen(url)
                } else {
                    errorText = "Please select a .pdf file."
                }
            case .failure(let err):
                print(err)
                onError(err)
                break
            }
        }
    }
    
    private var borderColor: Color {
        if isTargeted {
            return .accent
        } else {
            return .clear
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
                    print(err)
                    errorText = "Failed to load file."
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
