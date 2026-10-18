import SwiftUI
import PDFKit

/// Lets the chat ask the PDF pane to jump to a page (used by citation chips).
@MainActor
@Observable
final class PDFNavigator {
    struct Request: Equatable {
        let page: Int
        let id = UUID()
    }

    var request: Request?

    func show(page: Int) {
        request = Request(page: page)
    }
}

/// Actions the menu bar can run on the focused window.
struct ChatActions {
    var newChat: (() -> Void)?
    var openPDF: (() -> Void)?
}

extension FocusedValues {
    @Entry var chatActions: ChatActions?
}

struct ChatPDFCommands: Commands {
    @FocusedValue(\.chatActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") { actions?.newChat?() }
                .keyboardShortcut("n")
                .disabled(actions?.newChat == nil)
            Button("Open PDF…") { actions?.openPDF?() }
                .keyboardShortcut("o")
                .disabled(actions?.openPDF == nil)
        }
    }
}

extension ChatMessage {
    /// Distinct, sorted page numbers cited by this answer ("[1] page 12, chunk 3, score 0.812").
    var citedPages: [Int] {
        let pages = sources.compactMap { source -> Int? in
            guard let range = source.range(of: #"page (\d+)"#, options: .regularExpression) else { return nil }
            return Int(source[range].dropFirst("page ".count))
        }
        return Array(Set(pages)).sorted()
    }
}
