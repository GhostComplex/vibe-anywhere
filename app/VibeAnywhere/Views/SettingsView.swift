import SwiftUI

struct SettingsView: View {
    @State private var host: String
    @State private var portText: String
    @State private var token: String
    @State private var showToken = false
    @State private var saveError: String?

    let wsService: WebSocketService
    var onDismiss: () -> Void

    init(wsService: WebSocketService, onDismiss: @escaping () -> Void) {
        self.wsService = wsService
        self.onDismiss = onDismiss

        let config = KeychainService.loadConfig()
        _host = State(initialValue: config.host)
        _portText = State(initialValue: String(config.port))
        _token = State(initialValue: config.token)
    }

    private var config: ConnectionConfig {
        ConnectionConfig(host: host, port: Int(portText) ?? 7842, token: token)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Host or IP", text: $host)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("Port", text: $portText)
                        .keyboardType(.numberPad)
                }

                Section("Authentication") {
                    HStack {
                        if showToken {
                            TextField("Bearer Token", text: $token)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("Bearer Token", text: $token)
                        }
                        Button {
                            showToken.toggle()
                        } label: {
                            Image(systemName: showToken ? "eye.slash" : "eye")
                        }
                    }
                }

                Section {
                    connectionStatus
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        saveAndConnect()
                    }
                    .disabled(!config.isValid)
                }
            }
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch wsService.state {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .disconnected: .red
        }
    }

    private var statusText: String {
        switch wsService.state {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .reconnecting(let attempt): "Reconnecting (attempt \(attempt))…"
        case .disconnected: "Disconnected"
        }
    }

    private func saveAndConnect() {
        do {
            // Trim whitespace before saving — prevents invisible newlines from clipboard paste
            let trimmed = ConnectionConfig(
                host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                port: Int(portText) ?? 7842,
                token: token.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try KeychainService.saveConfig(trimmed)
            saveError = nil
            wsService.connect(config: trimmed)
            onDismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
