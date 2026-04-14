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

            if message.role == .assistant && !message.isError { Spacer(minLength: 60) }
        }
    }

    // MARK: - Text

    @ViewBuilder
    private var textContent: some View {
        if message.isError {
            errorCard
        } else if message.role == .user {
            Text(message.text)
                .textSelection(.enabled)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.6), Theme.border.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: Theme.cardShadow, radius: 4, y: 2)
        } else {
            assistantCard
        }
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
            .foregroundStyle(Theme.textPrimary)
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
