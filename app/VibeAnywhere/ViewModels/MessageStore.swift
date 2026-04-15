import Foundation
import Observation

/// Owns the message array and replay buffer.
/// Isolated from streaming — ForEach only re-diffs when messages
/// are actually added/finalized, never during streaming chunks.
@Observable
@MainActor
final class MessageStore {
    private(set) var items: [ChatMessage] = []
    private(set) var isLoadingHistory = false
    private var replayBuffer: [ChatMessage] = []

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }
    var last: ChatMessage? { items.last }

    // MARK: - Mutations

    func appendUser(_ text: String) {
        items.append(ChatMessage(role: .user, text: text))
    }

    /// Add a finalized assistant message.
    func appendAssistant(text: String, toolUses: [ToolUseInfo]) {
        items.append(ChatMessage(role: .assistant, text: text, toolUses: toolUses))
    }

    func appendError(_ message: String) {
        items.append(ChatMessage(role: .assistant, text: message, isError: true))
    }

    // MARK: - Replay (history loading)

    func beginReplay() {
        isLoadingHistory = true
        replayBuffer = []
    }

    /// True briefly after endReplay, to prevent onChange(count) from scrolling
    /// while isLoadingHistory transitions from true→false in the same cycle.
    private(set) var didJustEndReplay = false

    func endReplay() {
        didJustEndReplay = true
        items = replayBuffer
        replayBuffer = []
        isLoadingHistory = false
    }

    func clearReplayFlag() {
        didJustEndReplay = false
    }

    func appendReplayUser(_ text: String) {
        if let lastIndex = replayBuffer.indices.last,
           replayBuffer[lastIndex].role == .user {
            replayBuffer[lastIndex].text += text
        } else {
            replayBuffer.append(ChatMessage(role: .user, text: text))
        }
    }

    func appendReplayAssistant(_ text: String) {
        if let lastIndex = replayBuffer.indices.last,
           replayBuffer[lastIndex].role == .assistant {
            replayBuffer[lastIndex].text += text
        } else {
            replayBuffer.append(ChatMessage(role: .assistant, text: text))
        }
    }

    func appendReplayToolCall(toolCallId: String, tool: String, status: String) {
        if replayBuffer.isEmpty || replayBuffer.last?.role != .assistant {
            replayBuffer.append(ChatMessage(role: .assistant, text: ""))
        }
        let lastIndex = replayBuffer.indices.last!
        replayBuffer[lastIndex].toolUses.append(
            ToolUseInfo(id: toolCallId, tool: tool, status: status)
        )
    }

    func updateReplayToolCall(toolCallId: String, status: String?) {
        for i in replayBuffer.indices.reversed() {
            if let toolIndex = replayBuffer[i].toolUses.firstIndex(where: { $0.id == toolCallId }),
               let status {
                replayBuffer[i].toolUses[toolIndex].status = status
                return
            }
        }
    }
}
