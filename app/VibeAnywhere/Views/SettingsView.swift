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
            ScrollView {
                VStack(spacing: Theme.paddingMd) {
                    connectionSection
                    authSection
                    statusSection

                    if let saveError {
                        errorSection(saveError)
                    }
                }
                .padding(.horizontal, Theme.paddingMd)
                .padding(.top, Theme.paddingSm)
            }
            .background(Theme.background.ignoresSafeArea())
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

    // MARK: - Sections

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("CONNECTION")

            VStack(spacing: 0) {
                fieldRow {
                    TextField("Host or IP", text: $host)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Divider()
                    .foregroundStyle(Theme.border)

                fieldRow {
                    TextField("Port", text: $portText)
                        .keyboardType(.numberPad)
                }
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(Theme.border.opacity(0.6), lineWidth: 0.5)
            )
        }
    }

    private var authSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("AUTHENTICATION")

            VStack(spacing: 0) {
                fieldRow {
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
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(Theme.border.opacity(0.6), lineWidth: 0.5)
            )
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("STATUS")

            VStack(spacing: 0) {
                fieldRow {
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(Theme.border.opacity(0.6), lineWidth: 0.5)
            )
        }
    }

    private func errorSection(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(message)
                .foregroundStyle(.red)
                .font(.subheadline)
        }
        .padding(Theme.paddingMd)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(Theme.textTertiary)
            .tracking(1)
            .padding(.horizontal, 4)
            .padding(.bottom, Theme.paddingSm)
    }

    private func fieldRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, Theme.paddingMd)
            .padding(.vertical, 14)
    }

    // MARK: - Status

    private var statusColor: Color {
        switch wsService.state {
        case .connected: Theme.accent
        case .connecting, .reconnecting: Theme.accentWarm
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

    // MARK: - Actions

    private func saveAndConnect() {
        let trimmed = ConnectionConfig(
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: Int(portText) ?? 7842,
            token: token.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            try KeychainService.saveConfig(trimmed)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
        wsService.connect(config: trimmed)
        onDismiss()
    }
}
