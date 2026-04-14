import SwiftUI

struct ContentView: View {
    @State private var wsService = WebSocketService()
    @State private var sessionVM: SessionViewModel?
    @State private var showSettings = false
    @State private var connectingElapsed: Int = 0
    @State private var connectingTimer: Timer?
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
                        connectingOverlay
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
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(color: Theme.cardShadow, radius: 3, y: 1)
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
            .onAppear {
                autoConnect()
            }
            .onChange(of: wsService.state) { oldState, newState in
                if newState == .connected && sessionVM == nil {
                    let vm = SessionViewModel(wsService: wsService)
                    vm.onSelectSession = { sessionId in
                        selectedSessionId = sessionId
                    }
                    vm.onSessionDestroyed = { sessionId in
                        if selectedSessionId == sessionId {
                            selectedSessionId = nil
                        }
                    }
                    sessionVM = vm
                }
                handleTimerForState(newState)
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

    private func handleTimerForState(_ newState: ConnectionState) {
        if case .connecting = newState {
            connectingElapsed = 0
            connectingTimer?.invalidate()
            connectingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in connectingElapsed += 1 }
            }
        } else if case .reconnecting = newState {
            // Keep timer running
        } else {
            connectingTimer?.invalidate()
            connectingTimer = nil
            connectingElapsed = 0
        }
    }

    // MARK: - Connecting

    private var connectingOverlay: some View {
        ZStack {
            if #available(iOS 26.0, *) {
                Color.clear
                    .ignoresSafeArea()
                    .glassEffect()
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
            }

            connectingContent
        }
    }

    private var connectingContent: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                    .shadow(color: Theme.cardShadow, radius: 4, y: 2)

                ProgressView()
                    .scaleEffect(1.3)
            }

            VStack(spacing: 8) {
                Text(connectingTitle)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)

                Text(connectingSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                if connectingElapsed >= 5 {
                    Text("\(config.host):\(config.port)")
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 2)
                }
            }

            if connectingElapsed >= 10 {
                HStack(spacing: 12) {
                    Button {
                        wsService.disconnect()
                        let cfg = KeychainService.loadConfig()
                        if cfg.isValid {
                            wsService.connect(config: cfg)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Theme.buttonDark)
                        .clipShape(Capsule())
                    }

                    Button {
                        showSettings = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape")
                            Text("Settings")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: Theme.cardShadow, radius: 3, y: 1)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Theme.paddingLg)
        .animation(.easeInOut(duration: 0.3), value: connectingElapsed >= 5)
        .animation(.easeInOut(duration: 0.3), value: connectingElapsed >= 10)
    }

    private var connectingTitle: String {
        switch wsService.state {
        case .reconnecting(let attempt):
            "Reconnecting (\(attempt)/10)…"
        default:
            "Connecting…"
        }
    }

    private var connectingSubtitle: String {
        if connectingElapsed >= 10 {
            return "Taking longer than expected.\nCheck that your daemon is running."
        } else if connectingElapsed >= 5 {
            return "Still trying to reach your daemon…"
        } else {
            return "Establishing connection…"
        }
    }

    private var config: ConnectionConfig {
        KeychainService.loadConfig()
    }

    // MARK: - Disconnected

    private var disconnectedView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                    .shadow(color: Theme.cardShadow, radius: 4, y: 2)

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
