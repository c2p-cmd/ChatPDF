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
        guard let item = providers.first else { return false }
        item.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, err in
            if let err {
                Task { @MainActor in
                    self.errorText = "Failed to load file."
                }
                print(err)
                return
            }
            guard let data else { return }
            if let data = data as? URL, data.pathExtension.lowercased() == "pdf" {
                errorText = nil
                onFileChosen(data)
            }
            if let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                errorText = nil
                onFileChosen(url)
            }
        }
        return false
    }
}

#Preview {
    UploadView { _ in } onError: { _ in }
}
