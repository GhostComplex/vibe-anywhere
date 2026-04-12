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
    let id: String  // toolCallId from ACP
    let tool: String
    var status: String
    var input: String

    init(id: String = UUID().uuidString, tool: String, status: String = "running", input: String = "") {
        self.id = id
        self.tool = tool
        self.status = status
        self.input = input
    }
}

/// Token usage for a single turn
struct TurnUsage: Sendable {
    var inputTokens: Int
    var outputTokens: Int
}

/// A permission request pending user approval
struct PermissionRequest: Identifiable, Sendable {
    let id: String  // requestId
    let sessionId: String
    let tool: String
    let options: [PermissionOption]
    let receivedAt: Date
}

/// Record of a resolved permission
struct PermissionRecord: Identifiable, Sendable {
    let id = UUID()
    let tool: String
    let outcome: String  // "approved" or "denied" or "auto-denied"
    let resolvedAt: Date
}

@Observable
@MainActor
final class ChatViewModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var isWaiting = false
    private(set) var turnUsage: TurnUsage?
    private(set) var sessionAgent: String = "claude"
    private(set) var availableModels: [String]?
    private(set) var availableModes: [String]?
    private(set) var pendingPermission: PermissionRequest?
    private(set) var permissionHistory: [PermissionRecord] = []

    let sessionId: String
    private let wsService: WebSocketService
    private var permissionTimer: Task<Void, Never>?
    private static let permissionTimeoutSeconds: TimeInterval = 60

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
        turnUsage = nil

        wsService.send(.sessionMessage(sessionId: sessionId, content: trimmed))
    }

    func cancelTurn() {
        guard isWaiting else { return }
        wsService.send(.sessionCancel(sessionId: sessionId))
    }

    func approvePermission(optionId: String) {
        guard let request = pendingPermission else { return }
        wsService.send(.permissionRespond(
            sessionId: sessionId,
            requestId: request.id,
            optionId: optionId
        ))
        permissionHistory.append(PermissionRecord(
            tool: request.tool,
            outcome: "approved",
            resolvedAt: Date()
        ))
        dismissPermission()
    }

    func denyPermission() {
        guard let request = pendingPermission else { return }
        // Find a reject/deny option
        let denyOption = request.options.first { $0.kind.contains("reject") }
            ?? request.options.last
        if let option = denyOption {
            wsService.send(.permissionRespond(
                sessionId: sessionId,
                requestId: request.id,
                optionId: option.optionId
            ))
        }
        permissionHistory.append(PermissionRecord(
            tool: request.tool,
            outcome: "denied",
            resolvedAt: Date()
        ))
        dismissPermission()
    }

    func handleDaemonMessage(_ msg: DaemonMessage) {
        switch msg {
        // v1 stream events
        case .streamText(let sid, let content):
            guard sid == sessionId else { return }
            appendToStreaming(content)

        case .streamToolUse(let sid, let tool, let input):
            guard sid == sessionId else { return }
            let inputStr = formatToolInput(input)
            appendToolUse(tool: tool, input: inputStr)

        case .streamEnd(let sid, _):
            guard sid == sessionId else { return }
            finalizeStreaming()

        // v2 events
        case .eventText(let sid, let content):
            guard sid == sessionId else { return }
            appendToStreaming(content)

        case .eventToolCall(let sid, let toolCallId, let tool, let status):
            guard sid == sessionId else { return }
            appendToolCallV2(toolCallId: toolCallId, tool: tool, status: status)

        case .eventToolCallUpdate(let sid, let toolCallId, let status, _):
            guard sid == sessionId else { return }
            updateToolCall(toolCallId: toolCallId, status: status)

        case .eventPermissionRequest(let sid, let requestId, let tool, let options):
            guard sid == sessionId else { return }
            showPermissionRequest(requestId: requestId, tool: tool, options: options)

        case .eventUsage(let sid, let inputTokens, let outputTokens):
            guard sid == sessionId else { return }
            turnUsage = TurnUsage(inputTokens: inputTokens, outputTokens: outputTokens)

        case .eventTurnEnd(let sid, _):
            guard sid == sessionId else { return }
            finalizeStreaming()

        case .eventError(let sid, let message):
            guard sid == sessionId else { return }
            appendError(message)

        case .eventSessionInfo(let sid, let agent, let models, let modes):
            guard sid == sessionId else { return }
            sessionAgent = agent
            availableModels = models
            availableModes = modes

        case .error(let message, _):
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

    private func appendToolCallV2(toolCallId: String, tool: String, status: String) {
        guard let lastIndex = messages.indices.last,
              messages[lastIndex].role == .assistant,
              messages[lastIndex].isStreaming else { return }

        messages[lastIndex].toolUses.append(
            ToolUseInfo(id: toolCallId, tool: tool, status: status)
        )
    }

    private func updateToolCall(toolCallId: String, status: String?) {
        guard let lastIndex = messages.indices.last,
              messages[lastIndex].role == .assistant else { return }

        if let toolIndex = messages[lastIndex].toolUses.firstIndex(where: { $0.id == toolCallId }),
           let status {
            messages[lastIndex].toolUses[toolIndex].status = status
        }
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

    // MARK: - Permission handling

    private func showPermissionRequest(requestId: String, tool: String, options: [PermissionOption]) {
        permissionTimer?.cancel()
        pendingPermission = PermissionRequest(
            id: requestId,
            sessionId: sessionId,
            tool: tool,
            options: options,
            receivedAt: Date()
        )
        // Auto-deny after timeout
        permissionTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.permissionTimeoutSeconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.pendingPermission?.id == requestId else { return }
                self.permissionHistory.append(PermissionRecord(
                    tool: tool,
                    outcome: "auto-denied",
                    resolvedAt: Date()
                ))
                self.pendingPermission = nil
                self.permissionTimer = nil
            }
        }
    }

    private func dismissPermission() {
        permissionTimer?.cancel()
        permissionTimer = nil
        pendingPermission = nil
    }
}
