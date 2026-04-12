import Foundation
import Observation

enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
}

@Observable
@MainActor
final class WebSocketService {
    private(set) var state: ConnectionState = .disconnected
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var config: ConnectionConfig = .empty
    private var reconnectTask: Task<Void, Never>?
    private var maxReconnectAttempts = 10
    private var isManualDisconnect = false

    /// Stream of daemon messages for consumers
    var onMessage: ((DaemonMessage) -> Void)?

    func connect(config: ConnectionConfig) {
        guard config.isValid, let url = config.wsURL else { return }

        isManualDisconnect = false
        self.config = config
        state = .connecting

        var request = URLRequest(url: url)
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        request.setValue("2", forHTTPHeaderField: "X-Protocol-Version")
        request.timeoutInterval = 10

        let urlSession = URLSession(configuration: .default)
        self.session = urlSession

        let wsTask = urlSession.webSocketTask(with: request)
        self.task = wsTask
        wsTask.resume()

        state = .connected
        startReceiving()
    }

    func disconnect() {
        isManualDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        state = .disconnected
    }

    func send(_ message: ClientMessage) {
        guard state == .connected, let task else { return }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(message),
              let string = String(data: data, encoding: .utf8) else { return }

        task.send(.string(string)) { [weak self] error in
            if let error {
                print("[ws] Send error: \(error.localizedDescription)")
                Task { @MainActor in
                    self?.handleDisconnect()
                }
            }
        }
    }

    // MARK: - Private

    private func startReceiving() {
        guard let task else { return }

        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }

                switch result {
                case .success(let message):
                    self.handleWSMessage(message)
                    self.startReceiving() // Continue receiving
                case .failure(let error):
                    print("[ws] Receive error: \(error.localizedDescription)")
                    self.handleDisconnect()
                }
            }
        }
    }

    private func handleWSMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text):
            guard let d = text.data(using: .utf8) else { return }
            data = d
        case .data(let d):
            data = d
        @unknown default:
            return
        }

        let decoder = JSONDecoder()
        let daemonMessage: DaemonMessage
        do {
            daemonMessage = try decoder.decode(DaemonMessage.self, from: data)
        } catch {
            print("[ws] Failed to decode message: \(error)")
            if let text = String(data: data, encoding: .utf8) {
                print("[ws] Raw message: \(text.prefix(500))")
            }
            return
        }

        #if DEBUG
        // Skip logging high-frequency text events
        if case .eventText = daemonMessage {} else {
            print("[ws] Received: \(daemonMessage)")
        }
        #endif
        onMessage?(daemonMessage)
    }

    private func handleDisconnect() {
        task = nil
        session?.invalidateAndCancel()
        session = nil

        guard !isManualDisconnect else {
            state = .disconnected
            return
        }

        // Auto-reconnect with exponential backoff
        scheduleReconnect(attempt: 1)
    }

    private func scheduleReconnect(attempt: Int) {
        guard attempt <= maxReconnectAttempts else {
            state = .disconnected
            return
        }

        state = .reconnecting(attempt: attempt)

        reconnectTask = Task { [weak self, config] in
            let delay = min(pow(2.0, Double(attempt - 1)), 30.0) // 1, 2, 4, 8, ... max 30s
            try? await Task.sleep(for: .seconds(delay))

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, !self.isManualDisconnect else { return }
                self.connect(config: config)
            }
        }
    }
}
