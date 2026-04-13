import SwiftUI

struct NewSessionView: View {
    let viewModel: SessionViewModel
    var onDismiss: () -> Void

    @State private var path = ""
    @State private var selectedAgent = "claude"
    @State private var favorites: [String] = []

    private static let favoritesKey = "savedDirectories"

    private let agents = ["claude", "codex", "gemini"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.paddingMd) {
                    directorySection
                    agentSection

                    if !favorites.isEmpty {
                        recentSection
                    }
                }
                .padding(.horizontal, Theme.paddingMd)
                .padding(.top, Theme.paddingSm)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createSession()
                    }
                    .disabled(path.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                loadFavorites()
            }
        }
    }

    // MARK: - Sections

    private var directorySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("PROJECT DIRECTORY")

            VStack(spacing: 0) {
                fieldRow {
                    TextField("~/projects/my-app", text: $path)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("AGENT")

            VStack(spacing: 0) {
                ForEach(Array(agents.enumerated()), id: \.element) { index, agent in
                    if index > 0 {
                        Divider().foregroundStyle(Theme.border)
                    }
                    Button {
                        selectedAgent = agent
                    } label: {
                        HStack {
                            Image(systemName: agentIcon(for: agent))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 20)
                            Text(agent.capitalized)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if selectedAgent == agent {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                                    .font(.subheadline.bold())
                            }
                        }
                        .padding(.horizontal, Theme.paddingMd)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("RECENT")

            VStack(spacing: 0) {
                ForEach(Array(favorites.enumerated()), id: \.element) { index, dir in
                    if index > 0 {
                        Divider().foregroundStyle(Theme.border)
                    }
                    Button {
                        path = dir
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 20)
                            Text(dir)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                        .padding(.horizontal, Theme.paddingMd)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
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

    private func createSession() {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if !favorites.contains(trimmed) {
            favorites.insert(trimmed, at: 0)
            if favorites.count > 10 { favorites = Array(favorites.prefix(10)) }
            saveFavorites()
        }

        viewModel.createSession(cwd: trimmed, agent: selectedAgent)
        onDismiss()
    }

    private func loadFavorites() {
        favorites = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? []
    }

    private func saveFavorites() {
        UserDefaults.standard.set(favorites, forKey: Self.favoritesKey)
    }

    private func agentIcon(for agent: String) -> String {
        switch agent {
        case "claude": return "brain.head.profile"
        case "codex": return "terminal"
        case "gemini": return "sparkles"
        default: return "cpu"
        }
    }
}
