import SwiftUI
import PDFKit

struct PDFPreview: View {
    let url: URL?
    var navigator: PDFNavigator

    var body: some View {
        Group {
            if let url, let pdfDoc = PDFDocument(url: url) {
                PDFKitView(document: pdfDoc, request: navigator.request)
            } else {
                ContentUnavailableView("No Document", systemImage: "doc")
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    let request: PDFNavigator.Request?

    final class Coordinator {
        var lastRequestID: UUID?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = NSColor.clear
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
        guard let request, request.id != context.coordinator.lastRequestID else { return }
        context.coordinator.lastRequestID = request.id
        guard let page = document.page(at: request.page - 1) else { return }

        nsView.go(to: page)
        // Flash the cited page so the eye lands on it.
        let selection = page.selection(for: page.bounds(for: .cropBox))
        nsView.highlightedSelections = selection.map { [$0] }
        selection?.color = NSColor.controlAccentColor.withAlphaComponent(0.25)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            nsView.highlightedSelections = nil
        }
    }
}

#Preview {
    PDFPreview(url: nil, navigator: PDFNavigator())
        .frame(width: 500, height: 400)
}
