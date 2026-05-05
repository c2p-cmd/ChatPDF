import MarkdownUI
import SwiftUI

struct ChatView: View {
    @Binding var viewModel: ChatViewModel
    
    var body: some View {
        VStack(spacing: 10) {
            Messages(messages: viewModel.messages)
                .onAppear {
//                    viewModel.messages = [ChatMessage(
//                        role: .assistant,
//                        text: "Hello there! How can I help you today?"
//                    )]
                }
            
            Composer(text: $viewModel.input, onSend: viewModel.send)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.white.opacity(0.55))
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(.white.opacity(0.8), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                )
        }
    }
}

private struct Messages: View {
    var messages: [ChatMessage]
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .center, spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.automatic)
            .onAppear {
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
    var onSend: () -> Void
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            MacTextViewWithEnterToSend(
                text: text,
                onCommit: onSend
            )
            .frame(minHeight: 20, maxHeight: 110)
            .padding(.horizontal, 12)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 10, y: 4)
                    .background(LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.95),
                            Color.accentColor.opacity(0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .clipShape(Circle())
            }
            .padding([.trailing, .bottom], 5)
            .contentShape(Circle())
            .buttonStyle(.borderless)
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
        }
        .padding(12)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    
    var alignment: Alignment {
        switch message.role {
        case .user: return .trailing
        case .assistant, .typing: return .leading
        }
    }
    
    var horizontalAlignment: HorizontalAlignment {
        switch message.role {
        case .user: return .trailing
        case .assistant, .typing: return .leading
        }
    }
    
    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 1) {
            HStack(alignment: .top) {
                if message.role == .user { Spacer(minLength: 48) }
                
                Group {
                    if message.role == .typing {
                        ProgressView()
                            .progressViewStyle(LinearProgressViewStyle())
                    } else {
                        VStack(alignment: .leading, spacing: 1) {
                            if !message.modelThoughtIsEmpty {
                                if let modelThought = message.modelThought {
                                    DisclosureGroup("Show Model Thought") {
                                        Text(modelThought)
                                            .padding(.bottom, 5)
                                    }
                                    .foregroundStyle(.white)
                                    .padding([.trailing])
                                    .padding(.leading, 5)
                                    .background(Color.blue.gradient)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                            Markdown(message.text)
                                .markdownTheme(.docC)
                                .textSelection(.enabled)
                            if !message.sources.isEmpty {
                                DisclosureGroup("Sources") {
                                    VStack(alignment: .leading, spacing: 1) {
                                        ForEach(message.sources.indices, id: \.self) { i in
                                            Text(message.sources[i])
                                                .foregroundStyle(.primary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                                .foregroundStyle(.primary.secondary)
                            }
                        }
                    }
                }
                .foregroundStyle(message.role == .user ? .white : Color.primary.opacity(0.92))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleBackground)
                .frame(maxWidth: .infinity, alignment: alignment)
                
                if message.role != .user { Spacer(minLength: 48) }
            }
            if message.role != .typing {
                Button("Copy", systemImage: "document.on.document") {
                    let pasteboard = NSPasteboard.general
                    print(pasteboard.clearContents())
                    pasteboard.setString(message.text, forType: .string)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.footnote)
                .padding(.horizontal)
            }
        }
    }
    
    @ViewBuilder
    var bubbleBackground: some View {
        if message.role == .user {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.78))
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.78))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                }
        }
    }
}

private struct ChatBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.14),
                    Color(red: 0.12, green: 0.14, blue: 0.20),
                    Color(red: 0.07, green: 0.09, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 80)
                .offset(x: -220, y: -160)
            
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: 260, y: 180)
        }
        .ignoresSafeArea()
    }
}

private extension View {
    @ViewBuilder
    func chatPanelGlass(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        
        if #available(macOS 26.0, *) {
            self
                .clipShape(shape)
                .glassEffect(.clear, in: shape)
                .overlay {
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.28),
                                    .white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        } else {
            self
                .background {
                    ZStack {
                        shape.fill(.white.opacity(0.08))
                        shape.fill(.ultraThinMaterial)
                    }
                }
                .overlay {
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.30),
                                    .white.opacity(0.07)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.20), radius: 18, y: 8)
                .clipShape(shape)
        }
    }
}

private struct MacTextViewWithEnterToSend: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = text
        
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView, textView.string != text {
            textView.string = text
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
        ChatMessage(role: .user, text: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet."),
        ChatMessage(
            role: .assistant,
            answer: ChatAnswer(
                finalAnswer: "Yes, that is the case",
                thinking: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet. Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet.",
                sources: [
                    "P[1]",
                    "P[2]"
                ]
            )
        ),
        ChatMessage(role: .typing, text: "")
    ]
    MainSplitView(fileURL: nil, chatVM: .constant(ChatViewModel(messages: messages)))
        .frame(width: 700, height: 400)
        .preferredColorScheme(.light)
}
