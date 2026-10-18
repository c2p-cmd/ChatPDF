import MarkdownUI
import SwiftUI

struct ChatView: View {
    @Binding var viewModel: ChatViewModel
    var navigator: PDFNavigator

    var body: some View {
        Group {
            if viewModel.messages.isEmpty {
                EmptyChat { question in
                    viewModel.input = question
                    viewModel.send()
                }
            } else {
                Messages(
                    messages: viewModel.messages,
                    isRunning: viewModel.isRunning,
                    navigator: navigator,
                    onRetry: viewModel.retryLast
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Composer(
                text: $viewModel.input,
                isRunning: viewModel.isRunning,
                onSend: viewModel.send,
                onStop: viewModel.stop
            )
        }
    }
}

private struct EmptyChat: View {
    var onAsk: (String) -> Void

    private let prompts = [
        "Summarize this document",
        "What are the key points?",
        "What conclusions does it reach?"
    ]

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Ask about this PDF")
                    .font(.headline)
                Text("Answers are written by a model on this Mac and can be wrong. Check the cited pages.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            VStack(spacing: 8) {
                ForEach(prompts, id: \.self) { prompt in
                    Button(prompt) { onAsk(prompt) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }
        }
        .padding(24)
    }
}

private struct Messages: View {
    var messages: [ChatMessage]
    var isRunning: Bool
    var navigator: PDFNavigator
    var onRetry: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(messages) { message in
                        MessageBubble(
                            message: message,
                            canRetry: !isRunning && message.id == messages.last?.id && message.role == .assistant,
                            navigator: navigator,
                            onRetry: onRetry
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
            .scrollIndicators(.automatic)
            .onAppear {
                if let last = messages.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
            .onChange(of: messages.last?.text) {
                if let last = messages.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
            .onChange(of: messages.count) {
                if let last = messages.last?.id {
                    withAnimation(.easeOut(duration: 0.22)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct Composer: View {
    var text: Binding<String>
    var isRunning: Bool
    var onSend: () -> Void
    var onStop: () -> Void

    private var isEmpty: Bool {
        text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            MacTextViewWithEnterToSend(
                text: text,
                placeholder: "Ask about this PDF",
                onCommit: onSend
            )
            .frame(minHeight: 28, maxHeight: 110)

            if isRunning {
                Button(action: onStop) {
                    Label("Stop", systemImage: "stop.fill")
                        .labelStyle(.iconOnly)
                }
                .help("Stop answering")
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
            } else {
                Button(action: onSend) {
                    Label("Send", systemImage: "arrow.up")
                        .labelStyle(.iconOnly)
                }
                .help("Send (Return)")
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .disabled(isEmpty)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    var canRetry: Bool
    var navigator: PDFNavigator
    var onRetry: () -> Void

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: .leading, spacing: 4) {
                bubble
                if message.role != .typing {
                    actions
                }
            }
            .frame(maxWidth: 640, alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer(minLength: 48) }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        Group {
            if message.role == .typing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Answering")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if !message.modelThoughtIsEmpty, let modelThought = message.modelThought {
                        DisclosureGroup("Show Model Thought") {
                            Text(modelThought)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                        .foregroundStyle(.secondary)
                    }
                    Markdown(message.text)
                        .markdownTheme(.docC)
                        .textSelection(.enabled)
                    if !message.citedPages.isEmpty {
                        sources
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isUser ? AnyShapeStyle(Color.accentColor.opacity(0.14)) : AnyShapeStyle(.quaternary))
        )
    }

    private var sources: some View {
        HStack(spacing: 6) {
            Text("Sources")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(message.citedPages, id: \.self) { page in
                Button("p. \(page)") { navigator.show(page: page) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .help("Show page \(page)")
                    .accessibilityLabel("Go to page \(page)")
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            Button("Copy", systemImage: "document.on.document") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(message.text, forType: .string)
            }
            .help("Copy")
            if canRetry {
                Button("Retry", systemImage: "arrow.clockwise", action: onRetry)
                    .help("Ask again")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.regular)
        .buttonStyle(.borderless)
        .frame(minHeight: 28)
        .padding(.horizontal, 6)
    }
}

/// Plain-text field: Return sends, Shift-Return inserts a newline.
private final class PlaceholderTextView: NSTextView {
    var placeholder = ""

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let container = textContainer else { return }
        let origin = NSPoint(
            x: textContainerInset.width + container.lineFragmentPadding,
            y: textContainerInset.height
        )
        placeholder.draw(at: origin, withAttributes: [
            .font: font ?? NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.placeholderTextColor
        ])
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}

private struct MacTextViewWithEnterToSend: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onCommit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PlaceholderTextView()
        textView.placeholder = placeholder
        textView.isEditable = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = text
        textView.setAccessibilityLabel("Message")

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onCommit = onCommit
        if let textView = nsView.documentView as? NSTextView, textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onCommit: () -> Void

        init(text: Binding<String>, onCommit: @escaping () -> Void) {
            _text = text
            self.onCommit = onCommit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Intercept Enter key to send, allow Shift-Enter to insert newline
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    return false // allow newline
                } else {
                    onCommit()
                    return true // handled
                }
            }
            return false
        }
    }
}

#Preview {
    let messages = [
        ChatMessage(role: .user, text: "hello"),
        ChatMessage(role: .assistant, text: "Hello, How can I help you today?"),
        ChatMessage(role: .user, text: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat."),
        ChatMessage(
            role: .assistant,
            answer: ChatAnswer(
                finalAnswer: "Yes, that is the case",
                thinking: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore.",
                sources: [
                    "[1] page 1, chunk 0, score 0.812",
                    "[2] page 2, chunk 3, score 0.700"
                ]
            )
        ),
        ChatMessage(role: .typing, text: "")
    ]
    MainSplitView(fileURL: nil, chatVM: .constant(ChatViewModel(messages: messages)), navigator: PDFNavigator())
        .frame(width: 800, height: 450)
}
