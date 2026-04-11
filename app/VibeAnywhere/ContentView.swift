import SwiftUI

struct ContentView: View {
    @State private var wsService = WebSocketService()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack {
                if wsService.state == .disconnected {
                    ContentUnavailableView(
                        "Not Connected",
                        systemImage: "wifi.slash",
                        description: Text("Configure your server connection in Settings.")
                    )
                } else {
                    Text("Connected")
                        .font(.headline)
                    // Session list will go here (#21)
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
