import SwiftUI
import PDFKit

struct PDFPreview: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                if let pdfDoc = PDFDocument(url: url) {
                    PDFKitView(document: pdfDoc)
                } else {
                    PlaceholderView(fileName: url.lastPathComponent)
                }
            } else {
                PlaceholderView(fileName: "Untitled.pdf")
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        .padding()
    }
}

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .white
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = document
    }
}

private struct PlaceholderView: View {
    let fileName: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(fileName)
                .font(.headline)
                .foregroundColor(.appPrimary)
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 12)
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 12)
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 200)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }
}

#Preview {
    PDFPreview(url: nil)
        .frame(width: 500, height: 400)
}
