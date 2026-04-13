import Foundation
import Observation
import os

private let wsLog = Logger(subsystem: "com.ghostcomplex.VibeAnywhere", category: "WebSocket")

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
    private var wsTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var config: ConnectionConfig = .empty
    private var reconnectTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var maxReconnectAttempts = 10
    private var isManualDisconnect = false
    private var wsDelegate: WebSocketDelegate?

    var onMessage: ((DaemonMessage) -> Void)?

    func connect(config: ConnectionConfig) {
        guard config.isValid, let url = config.wsURL else {
            wsLog.error("[ws] invalid config or URL")
            return
        }

        isManualDisconnect = false
        self.config = config
        state = .connecting

        var request = URLRequest(url: url)
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        request.setValue("2", forHTTPHeaderField: "X-Protocol-Version")
        request.timeoutInterval = 10

        let delegate = WebSocketDelegate()
        self.wsDelegate = delegate

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        self.urlSession = session

        let task = session.webSocketTask(with: request)
        self.wsTask = task

        // Start detached receive loop — must NOT run on MainActor.
        // Capture only the task (Sendable) and a weak reference-free callback.
        let taskRef = task
        receiveTask?.cancel()
        receiveTask = Task.detached { [weak self] in
            await self?.receiveLoop(task: taskRef)
        }

        task.resume()
        wsLog.info("[ws] connecting to \(url.absoluteString)")
    }

    func disconnect() {
        isManualDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        state = .disconnected
    }

    func send(_ message: ClientMessage) {
        guard state == .connected, let wsTask else { return }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(message),
              let string = String(data: data, encoding: .utf8) else { return }

        wsTask.send(.string(string)) { error in
            if let error {
                wsLog.error("[ws] send error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

    /// Called from detached task. The method itself is MainActor-isolated,
    /// but the `task.receive()` call will suspend and yield the actor,
    /// allowing other MainActor work to proceed.
    private func receiveLoop(task: URLSessionWebSocketTask) async {
        wsLog.info("[ws] receive loop started")

        do {
            while !Task.isCancelled {
                wsLog.debug("[ws] awaiting message...")
                // This is the key call — it suspends until a message arrives.
                // Because this method is @MainActor, the suspension point
                // releases the main actor for other work.
                let message = try await task.receive()
                wsLog.info("[ws] message received")
                handleWSMessage(message)
            }
        } catch {
            if !Task.isCancelled {
                wsLog.error("[ws] receive error: \(error.localizedDescription)")
                handleDisconnect()
            }
        }

        wsLog.info("[ws] receive loop ended")
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
            wsLog.error("[ws] decode error: \(error.localizedDescription)")
            return
        }

        if case .hello = daemonMessage {
            wsLog.info("[ws] hello → connected")
            state = .connected
            return
        }

        onMessage?(daemonMessage)
    }

    private func handleDisconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        wsTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        guard !isManualDisconnect else {
            state = .disconnected
            return
        }

        scheduleReconnect(attempt: 1)
    }

    private func scheduleReconnect(attempt: Int) {
        guard attempt <= maxReconnectAttempts else {
            state = .disconnected
            return
        }

        state = .reconnecting(attempt: attempt)

        reconnectTask = Task { [weak self, config] in
            let delay = min(pow(2.0, Double(attempt - 1)), 30.0)
            try? await Task.sleep(for: .seconds(delay))

            guard !Task.isCancelled else { return }

            self?.connect(config: config)
        }
    }
}

// MARK: - URLSession WebSocket Delegate

private final class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol_: String?) {
        wsLog.info("[ws] didOpen (protocol: \(protocol_ ?? "nil"))")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        wsLog.info("[ws] didClose (code: \(closeCode.rawValue))")
    }
}
