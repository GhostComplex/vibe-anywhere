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

    /// Cache of chat view models by session ID
    private var chatVMs: [String: ChatViewModel] = [:]

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

    func createSession(cwd: String) {
        wsService.send(.sessionCreate(cwd: cwd))
        isLoading = true
    }

    func destroySession(_ sessionId: String) {
        wsService.send(.sessionDestroy(sessionId: sessionId))
        sessions.removeAll { $0.sessionId == sessionId }
        chatVMs.removeValue(forKey: sessionId)
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
            activeChatVM = existing
            return existing
        }
        let vm = ChatViewModel(sessionId: sessionId, wsService: wsService)
        chatVMs[sessionId] = vm
        activeChatVM = vm
        return vm
    }

    func clearError() {
        error = nil
    }

    // MARK: - Private

    private func handleMessage(_ msg: DaemonMessage) {
        // Forward stream events to active chat
        switch msg {
        case .streamText, .streamToolUse, .streamEnd:
            print("[session-vm] Forwarding to activeChatVM: \(activeChatVM != nil)")
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

        case .error(let message):
            if activeChatVM == nil {
                error = message
            }

        default:
            break
        }
    }
}
