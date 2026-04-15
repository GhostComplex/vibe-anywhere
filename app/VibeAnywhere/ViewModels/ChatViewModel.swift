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
    var isError: Bool = false
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
    let messages = MessageStore()
    private(set) var isWaiting = false
    private(set) var hasError = false

    /// Streaming state — isolated @Observable so chunk updates
    /// never trigger ForEach diff on the messages array.
    @ObservationIgnored let streaming = StreamingState()

    private(set) var turnUsage: TurnUsage?
    private(set) var sessionAgent: String = "claude"
    private(set) var currentModel: String?
    private(set) var currentMode: String?
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
        guard !trimmed.isEmpty, !hasError else { return }

        messages.appendUser(trimmed)
        messages.appendStreamingPlaceholder()
        streaming.begin()
        isWaiting = true
        turnUsage = nil

        wsService.send(.sessionMessage(sessionId: sessionId, content: trimmed))
    }

    func cancelTurn() {
        guard isWaiting else { return }
        wsService.send(.sessionCancel(sessionId: sessionId))
    }

    func setMode(_ mode: String) {
        wsService.send(.sessionSetMode(sessionId: sessionId, mode: mode))
        currentMode = mode
    }

    func setModel(_ model: String) {
        wsService.send(.sessionSetModel(sessionId: sessionId, model: model))
        currentModel = model
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
        case .eventText(let sid, let content, let replay):
            guard sid == sessionId else { return }
            if replay {
                messages.appendReplayAssistant(content)
            } else {
                streaming.appendText(content)
            }

        case .eventUserText(let sid, let content, let replay):
            guard sid == sessionId else { return }
            if replay {
                messages.appendReplayUser(content)
            }

        case .eventToolCall(let sid, let toolCallId, let tool, let status, let replay):
            guard sid == sessionId else { return }
            if replay {
                messages.appendReplayToolCall(toolCallId: toolCallId, tool: tool, status: status)
            } else {
                streaming.appendToolCall(id: toolCallId, tool: tool, status: status)
            }

        case .eventToolCallUpdate(let sid, let toolCallId, let status, _, let replay):
            guard sid == sessionId else { return }
            if replay {
                messages.updateReplayToolCall(toolCallId: toolCallId, status: status)
            } else {
                streaming.updateToolCall(id: toolCallId, status: status)
            }

        case .eventReplayEnd(let sid):
            guard sid == sessionId else { return }
            if messages.isLoadingHistory {
                messages.endReplay()
            }

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
            if currentModel == nil, let first = models?.first {
                currentModel = first
            }
            if currentMode == nil, let first = modes?.first {
                currentMode = first
            }

        case .error(let message, _):
            appendError(message)

        default:
            break
        }
    }

    // MARK: - Streaming lifecycle

    private func finalizeStreaming() {
        let result = streaming.finalize()
        messages.finalizeAssistant(text: result.text, toolUses: result.toolUses)
        isWaiting = false
    }

    private func appendError(_ message: String) {
        if hasError { return }

        if let lastIndex = messages.items.indices.last,
           messages.items[lastIndex].role == .assistant,
           messages.items[lastIndex].isStreaming {
            let result = streaming.finalize()
            messages.finalizeAssistant(text: result.text, toolUses: result.toolUses)
        }
        messages.appendError(message)
        hasError = true
        isWaiting = false
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
