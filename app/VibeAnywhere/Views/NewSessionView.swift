import SwiftUI

struct NewSessionView: View {
    let viewModel: SessionViewModel
    var onDismiss: () -> Void

    @State private var selectedPath: String?
    @State private var selectedAgent = "claude"

    private let agents = ["claude"]

    private var allowedDirs: [String] {
        viewModel.wsService.allowedDirs
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.paddingMd) {
                    directorySection
                    agentSection
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
                    .disabled(selectedPath == nil)
                }
            }
            .onAppear {
                // Auto-select if only one allowed directory
                if allowedDirs.count == 1 {
                    selectedPath = allowedDirs[0]
                }
            }
        }
    }

    // MARK: - Sections

    private var directorySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("PROJECT DIRECTORY")

            VStack(spacing: 0) {
                ForEach(Array(allowedDirs.enumerated()), id: \.element) { index, dir in
                    if index > 0 {
                        Divider().foregroundStyle(Theme.border)
                    }
                    Button {
                        selectedPath = dir
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(selectedPath == dir ? Theme.accent : Theme.textTertiary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dir.components(separatedBy: "/").last ?? dir)
                                    .font(.body)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(dir)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Theme.textTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            if selectedPath == dir {
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
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(Theme.border.opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: Theme.cardShadow, radius: 4, y: 2)
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
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(Theme.border.opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: Theme.cardShadow, radius: 4, y: 2)
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

    private func createSession() {
        guard let path = selectedPath else { return }
        viewModel.createSession(cwd: path, agent: selectedAgent)
        onDismiss()
    }

    private func agentIcon(for agent: String) -> String {
        switch agent {
        case "claude": return "brain.head.profile"
        default: return "cpu"
        }
    }
}
