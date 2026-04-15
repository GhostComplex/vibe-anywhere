import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    @State private var isUserTextExpanded = false

    private static let collapseLineLimit = 5
    private static let collapseCharLimit = 300

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if !message.text.isEmpty {
                    textContent
                }

                ForEach(message.toolUses) { tool in
                    toolCard(tool)
                }
            }

            if message.role == .assistant && !message.isError { Spacer(minLength: 60) }
        }
    }

    // MARK: - Text

    @ViewBuilder
    private var textContent: some View {
        if message.isError {
            errorCard
        } else if message.role == .user {
            userCard
        } else {
            assistantCard
        }
    }

    private var userCard: some View {
        let lines = message.text.components(separatedBy: "\n")
        let shouldCollapse = lines.count > Self.collapseLineLimit
            || message.text.count > Self.collapseCharLimit
        let truncated = shouldCollapse && !isUserTextExpanded
        let truncatedText = truncated
            ? String(lines.prefix(Self.collapseLineLimit).joined(separator: "\n").prefix(Self.collapseCharLimit))
            : message.text

        return VStack(alignment: .trailing, spacing: 6) {
            if shouldCollapse {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isUserTextExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isUserTextExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                        Text(isUserTextExpanded ? "Collapse" : "Expand")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Text(truncatedText)
                .textSelection(.enabled)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.6), Theme.border.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .mask {
            if truncated {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 32)
                }
            } else {
                Color.black
            }
        }
        .shadow(color: Theme.cardShadow, radius: 4, y: 2)
    }

    private var errorCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.body)

            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                .stroke(Color.orange.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: Theme.cardShadow, radius: 3, y: 1)
    }

    private var assistantCard: some View {
        MarkdownContentView(text: message.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.7), Theme.border.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: Theme.cardShadow, radius: 4, y: 2)
    }

    // MARK: - Tool Card

    private func toolCard(_ tool: ToolUseInfo) -> some View {
        HStack(spacing: 8) {
            // Status dot
            Circle()
                .fill(statusColor(tool.status))
                .frame(width: 6, height: 6)

            Text(tool.tool)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.textPrimary)

            if !tool.status.isEmpty && tool.status != "running" {
                Text(tool.status)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                .stroke(Theme.border.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: Theme.cardShadow, radius: 2, y: 1)
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "done", "completed", "success": return Theme.accent
        case "running", "working": return Theme.accentWarm
        case "error", "failed": return .red
        default: return Theme.textTertiary
        }
    }
}

// MARK: - Streaming Bubble (isolated observation scope)

/// A separate view struct so that reading `viewModel.streamingText`
/// does NOT cause the parent ForEach to re-diff the entire messages array.
struct StreamingBubble: View {
    let viewModel: ChatViewModel

    var body: some View {
        let _ = print("[StreamingBubble] body evaluated, text.count=\(viewModel.streamingText.count) tools=\(viewModel.streamingToolUses.count)")
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                if !viewModel.streamingText.isEmpty {
                    Text(viewModel.streamingText)
                        .textSelection(.enabled)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.7), Theme.border.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.5
                                )
                        )
                        .shadow(color: Theme.cardShadow, radius: 4, y: 2)
                }

                ForEach(viewModel.streamingToolUses) { tool in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(toolStatusColor(tool.status))
                            .frame(width: 6, height: 6)
                        Text(tool.tool)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.textPrimary)
                        if !tool.status.isEmpty && tool.status != "running" {
                            Text(tool.status)
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                            .stroke(Theme.border.opacity(0.5), lineWidth: 0.5)
                    )
                    .shadow(color: Theme.cardShadow, radius: 2, y: 1)
                }

                if viewModel.streamingText.isEmpty && viewModel.streamingToolUses.isEmpty {
                    StreamingDots()
                }
            }

            Spacer(minLength: 60)
        }
    }

    private func toolStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "done", "completed", "success": return Theme.accent
        case "running", "working": return Theme.accentWarm
        case "error", "failed": return .red
        default: return Theme.textTertiary
        }
    }
}

// MARK: - Streaming Dots Animation

struct StreamingDots: View {
    @State private var phase = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.textTertiary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(phase == i ? 1.0 : 0.5)
                    .opacity(phase == i ? 1.0 : 0.3)
            }
        }
        .padding(.vertical, 6)
        .animation(.easeInOut(duration: 0.3), value: phase)
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                Task { @MainActor in phase = (phase + 1) % 3 }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}
