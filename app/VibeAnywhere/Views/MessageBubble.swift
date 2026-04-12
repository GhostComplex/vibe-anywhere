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
                    streamingIndicator
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
            // Assistant: plain text, no background
            Text(message.text)
                .textSelection(.enabled)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: - Streaming

    private var streamingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.textTertiary)
                    .frame(width: 5, height: 5)
                    .opacity(0.4)
            }
        }
        .padding(.vertical, 4)
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
        .background(Theme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
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
