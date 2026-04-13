import SwiftUI

struct ContentView: View {
    @State private var wsService = WebSocketService()
    @State private var sessionVM: SessionViewModel?
    @State private var showSettings = false
    @State private var selectedSessionId: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                Group {
                    switch wsService.state {
                    case .disconnected:
                        disconnectedView
                    case .connecting, .reconnecting:
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Connecting…")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    case .connected:
                        if let vm = sessionVM {
                            SessionListView(viewModel: vm)
                        }
                    }
                }
            }
            .navigationTitle("Vibe Anywhere")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Theme.surface)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                    }
                }
            }
            .navigationDestination(item: $selectedSessionId) { sessionId in
                if let vm = sessionVM {
                    ChatView(viewModel: vm.chatViewModel(for: sessionId))
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(wsService: wsService) {
                    showSettings = false
                }
            }
            .onChange(of: wsService.state) { _, newState in
                if newState == .connected && sessionVM == nil {
                    let vm = SessionViewModel(wsService: wsService)
                    vm.onSelectSession = { sessionId in
                        selectedSessionId = sessionId
                    }
                    sessionVM = vm
                }
            }
            .onAppear {
                autoConnect()
            }
        }
        .preferredColorScheme(.light)
    }

    private func autoConnect() {
        let config = KeychainService.loadConfig()
        if config.isValid {
            wsService.connect(config: config)
        }
    }

    // MARK: - Disconnected

    private var disconnectedView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle().stroke(Theme.border.opacity(0.5), lineWidth: 0.5)
                    )

                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
            }

            VStack(spacing: 8) {
                Text("Not Connected")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)

                Text("Configure your daemon connection\nin Settings to get started.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showSettings = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                    Text("Open Settings")
                }
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Theme.buttonDark)
                .clipShape(Capsule())
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Theme.paddingLg)
    }
}
