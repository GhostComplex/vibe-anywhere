import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Text content
                if !message.text.isEmpty {
                    Text(message.text)
                        .textSelection(.enabled)
                }

                // Streaming indicator
                if message.isStreaming && message.text.isEmpty {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Thinking…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Tool uses
                ForEach(message.toolUses) { tool in
                    ToolUseCard(tool: tool)
                }

                // Streaming cursor
                if message.isStreaming && !message.text.isEmpty {
                    Circle()
                        .fill(.primary)
                        .frame(width: 6, height: 6)
                        .opacity(0.5)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    private var bubbleBackground: some ShapeStyle {
        message.role == .user
            ? AnyShapeStyle(.blue)
            : AnyShapeStyle(.secondary.opacity(0.15))
    }
}

// MARK: - Tool Use Card

struct ToolUseCard: View {
    let tool: ToolUseInfo
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.caption)
                    Text(tool.tool)
                        .font(.caption.bold())
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(tool.input)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
