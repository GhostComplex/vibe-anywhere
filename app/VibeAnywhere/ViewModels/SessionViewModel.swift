import Foundation
import Observation

@Observable
@MainActor
final class SessionViewModel {
    private(set) var sessions: [SessionInfo] = []
    private(set) var isLoading = false
    private(set) var error: String?

    let wsService: WebSocketService

    /// Currently active chat view model (receives stream events)
    var activeChatVM: ChatViewModel?

    /// Cache of chat view models by session ID (LRU, max 10)
    private var chatVMs: [String: ChatViewModel] = [:]
    private var chatVMOrder: [String] = [] // oldest first
    private let maxCachedVMs = 10

    /// Callback when a session is created or tapped (navigate to chat)
    var onSelectSession: ((String) -> Void)?

    init(wsService: WebSocketService) {
        self.wsService = wsService
        wsService.onMessage = { [weak self] msg in
            Task { @MainActor in
                self?.handleMessage(msg)
            }
        }
    }

    func refreshSessions() {
        wsService.send(.sessionList)
        isLoading = true
    }

    func createSession(cwd: String, agent: String? = nil) {
        wsService.send(.sessionCreate(cwd: cwd, agent: agent))
        isLoading = true
    }

    func destroySession(_ sessionId: String) {
        wsService.send(.sessionDestroy(sessionId: sessionId))
        sessions.removeAll { $0.sessionId == sessionId }
        chatVMs.removeValue(forKey: sessionId)
        chatVMOrder.removeAll { $0 == sessionId }
        if activeChatVM?.sessionId == sessionId {
            activeChatVM = nil
        }
    }

    func resumeSession(_ sessionId: String) {
        wsService.send(.sessionResume(sessionId: sessionId))
        onSelectSession?(sessionId)
    }

    func chatViewModel(for sessionId: String) -> ChatViewModel {
        if let existing = chatVMs[sessionId] {
            // Move to end (most recent)
            chatVMOrder.removeAll { $0 == sessionId }
            chatVMOrder.append(sessionId)
            activeChatVM = existing
            return existing
        }
        let vm = ChatViewModel(sessionId: sessionId, wsService: wsService)
        chatVMs[sessionId] = vm
        chatVMOrder.append(sessionId)
        // Evict oldest if over limit
        while chatVMOrder.count > maxCachedVMs {
            let evicted = chatVMOrder.removeFirst()
            chatVMs.removeValue(forKey: evicted)
        }
        activeChatVM = vm
        return vm
    }

    func clearError() {
        error = nil
    }

    // MARK: - Private

    private func handleMessage(_ msg: DaemonMessage) {
        // Forward event messages to active chat
        switch msg {
        case .eventText, .eventToolCall, .eventToolCallUpdate,
             .eventUsage, .eventTurnEnd, .eventError, .eventSessionInfo:
            activeChatVM?.handleDaemonMessage(msg)
            return
        // permission requests also go to chat (for now — #47 will add modal)
        case .eventPermissionRequest:
            activeChatVM?.handleDaemonMessage(msg)
            return
        case .error:
            activeChatVM?.handleDaemonMessage(msg)
        default:
            break
        }

        isLoading = false
        error = nil

        switch msg {
        case .sessionList(let list):
            sessions = list

        case .sessionCreated(let sessionId, _):
            refreshSessions()
            onSelectSession?(sessionId)

        case .sessionDestroyed:
            break // already removed in destroySession

        case .error(let message, _):
            if activeChatVM == nil {
                error = message
            }

        default:
            break
        }
    }
}
