import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Text content
                if !message.text.isEmpty {
                    textContent
                }

                // Streaming indicator
                if message.isStreaming && message.text.isEmpty {
                    StreamingDots()
                }

                // Tool uses
                ForEach(message.toolUses) { tool in
                    toolCard(tool)
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    // MARK: - Text

    @ViewBuilder
    private var textContent: some View {
        if message.role == .user {
            Text(message.text)
                .textSelection(.enabled)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMd)
                        .stroke(Theme.border, lineWidth: 1)
                )
        } else {
            // Assistant: frosted glass card with Markdown
            assistantCard
        }
    }

    private var assistantCard: some View {
        MarkdownContentView(text: message.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .stroke(Theme.border.opacity(0.5), lineWidth: 0.5)
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
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.border.opacity(0.5), lineWidth: 0.5))
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

// MARK: - Streaming Dots Animation

private struct StreamingDots: View {
    @State private var phase = 0

    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

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
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}
