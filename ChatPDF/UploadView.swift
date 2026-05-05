import SwiftUI

struct UploadView: View {
    let onFileChosen: (URL) -> Void

    @State private var isTargeted = false
    @State private var showImporter = false
    @State private var errorText: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(.appPrimary)
                Text("Drag & drop a PDF here")
                    .foregroundColor(.appPrimary)
                    .font(.headline)
                Text("or")
                    .foregroundColor(.appPrimary.opacity(0.7))
                    .font(.subheadline)
                Button(action: { 
                    errorText = nil
                    showImporter = true 
                }) {
                    Text("Select File")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.appAccent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(28)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.appSubBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(borderColor, lineWidth: 2)
                    )
            )
            .onDrop(of: ["public.file-url"], isTargeted: $isTargeted) { providers in
                errorText = nil
                return handleDrop(providers: providers)
            }

            if let errorText {
                Text(errorText)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                if url.pathExtension.lowercased() == "pdf" {
                    onFileChosen(url)
                } else {
                    errorText = "Please select a .pdf file."
                }
            case .failure:
                break
            }
        }
    }
    
    private var borderColor: Color {
        if errorText != nil {
            return .red
        } else if isTargeted {
            return .appAccent
        } else {
            return .clear
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let item = providers.first else { return false }
        if item.hasItemConformingToTypeIdentifier("public.file-url") {
            item.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    if url.pathExtension.lowercased() == "pdf" {
                        errorText = nil
                        onFileChosen(url)
                    } else {
                        errorText = "Only .pdf files are accepted."
                    }
                }
            }
            return true
        }
        return false
    }
}

#Preview {
    UploadView { _ in }
}
