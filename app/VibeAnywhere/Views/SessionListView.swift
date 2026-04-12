import SwiftUI

struct SessionListView: View {
    let viewModel: SessionViewModel
    @State private var showNewSession = false

    var body: some View {
        Group {
            if viewModel.sessions.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "terminal",
                    description: Text("Create a new session to start coding.")
                )
            } else {
                List {
                    ForEach(viewModel.sessions) { session in
                        SessionRow(session: session)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.resumeSession(session.sessionId)
                            }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let session = viewModel.sessions[index]
                            viewModel.destroySession(session.sessionId)
                        }
                    }
                }
                .refreshable {
                    viewModel.refreshSessions()
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewSession = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewSession) {
            NewSessionView(viewModel: viewModel) {
                showNewSession = false
            }
        }
        .onAppear {
            viewModel.refreshSessions()
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = viewModel.error {
                Text(error)
            }
        }
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: SessionInfo

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(directoryName)
                    .font(.headline)
                Text(session.cwd)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(session.agentDisplayName)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }

    private var directoryName: String {
        session.cwd.components(separatedBy: "/").last ?? session.cwd
    }
}
