import SwiftUI

struct SessionListView: View {
    let viewModel: SessionViewModel
    @State private var showNewSession = false
    @State private var sessionToDelete: String?
    @State private var showDeleteAll = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            Group {
                if viewModel.sessions.isEmpty && viewModel.hostSessions.isEmpty && !viewModel.isLoading {
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
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .shadow(color: Theme.cardShadow, radius: 3, y: 1)
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                if !viewModel.sessions.isEmpty {
                    Button(role: .destructive) {
                        showDeleteAll = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .alert("Delete All Sessions?", isPresented: $showDeleteAll) {
            Button("Delete All", role: .destructive) {
                viewModel.destroyAllSessions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will end all active sessions. This cannot be undone.")
        }
        .alert("Delete Session?", isPresented: .init(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let id = sessionToDelete {
                    viewModel.destroySession(id)
                    sessionToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                sessionToDelete = nil
            }
        } message: {
            Text("This session will be ended and removed.")
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
        VStack(spacing: Theme.paddingLg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 80, height: 80)
                    .shadow(color: Theme.cardShadow, radius: 4, y: 2)

                Image(systemName: "waveform.circle")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(spacing: 8) {
                Text("No Sessions")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)

                Text("Start a new session to begin coding\nwith your AI agent.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showNewSession = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("New Session")
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

    // MARK: - List

    private var sessionsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !viewModel.sessions.isEmpty {
                    sectionHeader("ACTIVE")

                    ForEach(viewModel.sessions) { session in
                        sessionCard(session)
                            .padding(.horizontal, Theme.paddingMd)
                            .padding(.bottom, Theme.paddingSm)
                    }
                }

                if !viewModel.hostSessions.isEmpty {
                    sectionHeader("RECENT")

                    ForEach(viewModel.hostSessions) { session in
                        hostSessionCard(session)
                            .padding(.horizontal, Theme.paddingMd)
                            .padding(.bottom, Theme.paddingSm)
                    }
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
                    Text(session.displayTitle)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

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

                // Delete button
                Button(role: .destructive) {
                    sessionToDelete = session.sessionId
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.paddingMd)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
                    .stroke(Theme.border.opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: Theme.cardShadow, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                sessionToDelete = session.sessionId
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func hostSessionCard(_ session: HostSessionInfo) -> some View {
        Button {
            viewModel.resumeHostSession(session)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .foregroundStyle(Theme.textTertiary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.displayTitle)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(displayPath(session.cwd))
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                if let date = session.relativeDate {
                    Text(date)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .layoutPriority(1)
                }
            }
            .padding(Theme.paddingMd)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    private func displayPath(_ cwd: String) -> String {
        if cwd.isEmpty || cwd == "/" { return "Unknown directory" }
        return cwd
    }
}
