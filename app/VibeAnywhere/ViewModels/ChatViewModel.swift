import Foundation
import Observation

enum ChatMessageRole: Sendable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Sendable {
    let id = UUID()
    let role: ChatMessageRole
    var text: String
    var toolUses: [ToolUseInfo] = []
    var isStreaming: Bool = false
}

struct ToolUseInfo: Identifiable, Sendable {
    let id = UUID()
    let tool: String
    let input: String
}

@Observable
@MainActor
final class ChatViewModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var isWaiting = false

    let sessionId: String
    private let wsService: WebSocketService

    init(sessionId: String, wsService: WebSocketService) {
        self.sessionId = sessionId
        self.wsService = wsService
    }

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Add user message
        messages.append(ChatMessage(role: .user, text: trimmed))

        // Start assistant placeholder
        messages.append(ChatMessage(role: .assistant, text: "", isStreaming: true))
        isWaiting = true

        wsService.send(.sessionMessage(sessionId: sessionId, content: trimmed))
    }

    func handleDaemonMessage(_ msg: DaemonMessage) {
        print("[chat] handleDaemonMessage: \(msg), mySessionId=\(sessionId)")
        switch msg {
        case .streamText(let sid, let content):
            guard sid == sessionId else {
                print("[chat] sessionId mismatch: \(sid) != \(sessionId)")
                return
            }
            print("[chat] appendToStreaming: \(content.prefix(100)), messages.count=\(messages.count)")
            appendToStreaming(content)

        case .streamToolUse(let sid, let tool, let input):
            guard sid == sessionId else { return }
            let inputStr = formatToolInput(input)
            appendToolUse(tool: tool, input: inputStr)

        case .streamEnd(let sid, _):
            guard sid == sessionId else { return }
            print("[chat] finalizeStreaming, lastMessage=\(messages.last?.text.prefix(100) ?? "nil")")
            finalizeStreaming()

        case .error(let message):
            appendError(message)

        default:
            break
        }
    }

    // MARK: - Private

    private func appendToStreaming(_ text: String) {
        guard let lastIndex = messages.indices.last,
              messages[lastIndex].role == .assistant,
              messages[lastIndex].isStreaming else { return }

        messages[lastIndex].text += text
    }

    private func appendToolUse(tool: String, input: String) {
        guard let lastIndex = messages.indices.last,
              messages[lastIndex].role == .assistant,
              messages[lastIndex].isStreaming else { return }

        messages[lastIndex].toolUses.append(
            ToolUseInfo(tool: tool, input: input)
        )
    }

    private func finalizeStreaming() {
        guard let lastIndex = messages.indices.last,
              messages[lastIndex].role == .assistant else { return }

        messages[lastIndex].isStreaming = false
        isWaiting = false
    }

    private func appendError(_ message: String) {
        // Finalize any streaming message, then add error
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == .assistant,
           messages[lastIndex].isStreaming {
            messages[lastIndex].isStreaming = false
            messages[lastIndex].text += "\n\n⚠️ \(message)"
        } else {
            messages.append(ChatMessage(role: .assistant, text: "⚠️ \(message)"))
        }
        isWaiting = false
    }

    private func formatToolInput(_ input: [String: AnyCodable]) -> String {
        guard let data = try? JSONEncoder().encode(input),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
              let str = String(data: pretty, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}
