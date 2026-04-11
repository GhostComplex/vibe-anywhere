import SwiftUI

struct ContentView: View {
    @State private var wsService = WebSocketService()
    @State private var sessionVM: SessionViewModel?
    @State private var showSettings = false
    @State private var selectedSessionId: String?

    var body: some View {
        NavigationStack {
            Group {
                switch wsService.state {
                case .disconnected:
                    ContentUnavailableView(
                        "Not Connected",
                        systemImage: "wifi.slash",
                        description: Text("Configure your server connection in Settings.")
                    )
                case .connecting, .reconnecting:
                    ProgressView("Connecting…")
                case .connected:
                    if let vm = sessionVM {
                        SessionListView(viewModel: vm)
                    }
                }
            }
            .navigationTitle("Vibe Anywhere")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
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
    }

    private func autoConnect() {
        let config = KeychainService.loadConfig()
        if config.isValid {
            wsService.connect(config: config)
        }
    }
}
