import SwiftUI

struct SessionListView: View {
    let viewModel: SessionViewModel
    @State private var showNewSession = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            Group {
                if viewModel.sessions.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    sessionsList
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
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Theme.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.border, lineWidth: 1))
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

    // MARK: - Empty

    private var emptyState: some View {
        ContentUnavailableView(
            "No Sessions",
            systemImage: "terminal",
            description: Text("Create a new session to start coding.")
        )
    }

    // MARK: - List

    private var sessionsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                sectionHeader("ACTIVE")

                ForEach(viewModel.sessions) { session in
                    sessionCard(session)
                        .padding(.horizontal, Theme.paddingMd)
                        .padding(.bottom, Theme.paddingSm)
                }
            }
            .padding(.top, Theme.paddingSm)
        }
        .refreshable {
            viewModel.refreshSessions()
        }
    }

    // MARK: - Components

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(Theme.textTertiary)
                .tracking(1)
            Spacer()
        }
        .padding(.horizontal, Theme.paddingMd + 4)
        .padding(.vertical, Theme.paddingSm)
    }

    private func sessionCard(_ session: SessionInfo) -> some View {
        Button {
            viewModel.resumeSession(session.sessionId)
        } label: {
            HStack(spacing: 12) {
                // Folder icon
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.textTertiary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(directoryName(session.cwd))
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)

                    Text(session.cwd)
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                // Agent badge
                Text(session.agentDisplayName)
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.background)
                    .clipShape(Capsule())
            }
            .padding(Theme.paddingMd)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusLg)
                    .stroke(Theme.border.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: Theme.cardShadow, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                viewModel.destroySession(session.sessionId)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func directoryName(_ cwd: String) -> String {
        cwd.components(separatedBy: "/").last ?? cwd
    }
}
