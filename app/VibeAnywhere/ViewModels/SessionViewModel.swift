import Foundation
import Observation

@Observable
@MainActor
final class SessionViewModel {
    private(set) var sessions: [SessionInfo] = []
    private(set) var isLoading = false
    private(set) var error: String?

    private let wsService: WebSocketService

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
    }

    func resumeSession(_ sessionId: String) {
        wsService.send(.sessionResume(sessionId: sessionId))
        onSelectSession?(sessionId)
    }

    func clearError() {
        error = nil
    }

    // MARK: - Private

    private func handleMessage(_ msg: DaemonMessage) {
        isLoading = false
        error = nil

        switch msg {
        case .sessionList(let list):
            sessions = list

        case .sessionCreated(let sessionId, _):
            // Refresh list then navigate
            refreshSessions()
            onSelectSession?(sessionId)

        case .error(let message):
            error = message

        default:
            break // stream events handled elsewhere
        }
    }
}
