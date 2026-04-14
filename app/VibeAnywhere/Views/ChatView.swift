import SwiftUI

struct ChatView: View {
    let viewModel: ChatViewModel
    @State private var inputText = ""
    @State private var showSettings = false
    @State private var scrollTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if viewModel.messages.isEmpty && !viewModel.isWaiting {
                    EmptyStateView { chip in
                        inputText = chip
                        send()
                    }
                } else {
                    messageList
                }

                usageBar

                if !viewModel.hasError {
                    inputBar
                }
            }
        }
        .navigationTitle(viewModel.sessionAgent.capitalized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SessionSettingsSheet(viewModel: viewModel)
                .presentationDetents([.medium])
        }
        .overlay(alignment: .bottom) {
            if let request = viewModel.pendingPermission {
                PermissionModalView(
                    request: request,
                    onApprove: { viewModel.approvePermission(optionId: $0) },
                    onDeny: { viewModel.denyPermission() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 80)
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.pendingPermission != nil)
        .onAppear { isInputFocused = true }
        .onDisappear { scrollTask?.cancel() }
    }

    // MARK: - Messages

    private var messageList: some View {
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
            .onChange(of: viewModel.messages.count) { _, _ in debouncedScroll(proxy) }
            .onChange(of: viewModel.messages.last?.text) { _, _ in debouncedScroll(proxy) }
        }
    }

    // MARK: - Usage

    @ViewBuilder
    private var usageBar: some View {
        if let usage = viewModel.turnUsage, !viewModel.isWaiting {
            HStack {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.caption2)
                Text("\(usage.inputTokens)↓ \(usage.outputTokens)↑")
                    .font(.caption2.monospacedDigit())
            }
            .foregroundStyle(Theme.textTertiary)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .onSubmit { send() }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            if viewModel.isWaiting {
                Button { viewModel.cancelTurn() } label: {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.red)
                        .clipShape(Circle())
                }
            } else {
                Button { send() } label: {
                    Image(systemName: "arrow.up")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Theme.textTertiary : Theme.buttonDark
                        )
                        .clipShape(Circle())
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, Theme.paddingMd)
        .padding(.vertical, Theme.paddingSm)
        .background(.ultraThinMaterial)
        .shadow(color: Theme.cardShadow, radius: 4, y: -2)
    }

    // MARK: - Helpers

    private func send() {
        let text = inputText
        inputText = ""
        viewModel.sendMessage(text)
    }

    private func debouncedScroll(_ proxy: ScrollViewProxy) {
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            scrollToBottom(proxy)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastId = viewModel.messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }
}
