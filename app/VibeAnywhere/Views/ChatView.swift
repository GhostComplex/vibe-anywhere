import SwiftUI

struct ChatView: View {
    let viewModel: ChatViewModel
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: viewModel.messages.last?.text) { _, _ in
                    scrollToBottom(proxy)
                }
            }

            // Usage bar (shown after turn completes)
            if let usage = viewModel.turnUsage, !viewModel.isWaiting {
                HStack {
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .font(.caption2)
                    Text("\(usage.inputTokens)↓ \(usage.outputTokens)↑")
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }

            Divider()

            // Input bar
            HStack(spacing: 8) {
                TextField("Message…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit {
                        send()
                    }

                if viewModel.isWaiting {
                    // Cancel button while waiting
                    Button {
                        viewModel.cancelTurn()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                } else {
                    // Send button
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle(viewModel.sessionAgent.capitalized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !viewModel.permissionHistory.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        PermissionHistoryView(history: viewModel.permissionHistory)
                    } label: {
                        Image(systemName: "lock.shield")
                            .font(.caption)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let request = viewModel.pendingPermission {
                PermissionModalView(
                    request: request,
                    onApprove: { optionId in
                        viewModel.approvePermission(optionId: optionId)
                    },
                    onDeny: {
                        viewModel.denyPermission()
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 80)
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.pendingPermission != nil)
        .onAppear {
            isInputFocused = true
        }
    }

    private func send() {
        let text = inputText
        inputText = ""
        viewModel.sendMessage(text)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastId = viewModel.messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }
}
