import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(12)
                    .onChange(of: viewModel.messages.count) { _ in
                        if let last = viewModel.messages.last?.id {
                            withAnimation {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
                .background(Color.appSubBackground)
                .onAppear {
                    if let last = viewModel.messages.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextEditorWithEnterToSend(text: $viewModel.input, onCommit: {
                    viewModel.send()
                    isInputFocused = false
                })
                .frame(minHeight: 40, maxHeight: 100)
                .padding(8)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .focused($isInputFocused)
                
                Button(action: {
                    viewModel.send()
                    isInputFocused = false
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.appAccent)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .background(Color.appSubBackground)
        }
        .background(Color.appSubBackground)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .assistant || message.role == .typing {
                Circle().fill(Color.appPrimary).frame(width: 8, height: 8).padding(.top, 6)
            } else {
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                switch message.role {
                case .user:
                    Text(message.text)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.appPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .frame(maxWidth: 320, alignment: .trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                case .assistant:
                    Text(message.text)
                        .foregroundColor(.appPrimary)
                        .padding(10)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .frame(maxWidth: 420, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .typing:
                    HStack(spacing: 6) {
                        Circle().fill(Color.gray.opacity(0.6)).frame(width: 6, height: 6)
                        Circle().fill(Color.gray.opacity(0.6)).frame(width: 6, height: 6)
                        Circle().fill(Color.gray.opacity(0.6)).frame(width: 6, height: 6)
                    }
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(maxWidth: 100, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if message.role == .assistant || message.role == .typing {
                Spacer(minLength: 0)
            }
        }
    }
}

private struct TextEditorWithEnterToSend: UIViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isScrollEnabled = true
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = UIColor(Color.white)
        textView.delegate = context.coordinator
        textView.returnKeyType = .send
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        var onCommit: () -> Void

        init(text: Binding<String>, onCommit: @escaping () -> Void) {
            _text = text
            self.onCommit = onCommit
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                onCommit()
                return false
            }
            return true
        }
    }
}

#Preview {
    ChatView(viewModel: ChatViewModel())
        .frame(width: 320, height: 500)
}
