import SwiftUI

struct SessionSettingsSheet: View {
    let viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.paddingMd) {
                    agentSection
                    modelSection
                    modeSection
                    sessionInfoSection
                    permissionSection
                }
                .padding(.horizontal, Theme.paddingMd)
                .padding(.top, Theme.paddingSm)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Session Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("AGENT")

            VStack(spacing: 0) {
                fieldRow {
                    LabeledContent("Type", value: viewModel.sessionAgent.capitalized)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .themedCard()
        }
    }

    @ViewBuilder
    private var modelSection: some View {
        if let models = viewModel.availableModels, !models.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("MODEL")

                VStack(spacing: 0) {
                    ForEach(Array(models.enumerated()), id: \.element) { index, model in
                        if index > 0 {
                            Divider().foregroundStyle(Theme.border)
                        }
                        selectableRow(
                            title: model,
                            isSelected: viewModel.currentModel == model
                        ) {
                            viewModel.setModel(model)
                        }
                    }
                }
                .themedCard()
            }
        }
    }

    @ViewBuilder
    private var modeSection: some View {
        if let modes = viewModel.availableModes, !modes.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("MODE")

                VStack(spacing: 0) {
                    ForEach(Array(modes.enumerated()), id: \.element) { index, mode in
                        if index > 0 {
                            Divider().foregroundStyle(Theme.border)
                        }
                        selectableRow(
                            title: mode.capitalized,
                            subtitle: modeDescription(mode),
                            isSelected: viewModel.currentMode == mode
                        ) {
                            viewModel.setMode(mode)
                        }
                    }
                }
                .themedCard()
            }
        }
    }

    private var sessionInfoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("SESSION")

            VStack(spacing: 0) {
                fieldRow {
                    LabeledContent("ID") {
                        Text(viewModel.sessionId)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(Theme.textPrimary)
                }

                if let usage = viewModel.turnUsage {
                    Divider().foregroundStyle(Theme.border)
                    fieldRow {
                        LabeledContent("Last Turn") {
                            Text("\(usage.inputTokens)↓ \(usage.outputTokens)↑ tokens")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .themedCard()
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if !viewModel.permissionHistory.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("PERMISSIONS")

                VStack(spacing: 0) {
                    NavigationLink {
                        PermissionHistoryView(history: viewModel.permissionHistory)
                    } label: {
                        HStack {
                            Image(systemName: "lock.shield")
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 20)
                            Text("Permission History")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(viewModel.permissionHistory.count)")
                                .font(.caption.bold())
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Theme.background)
                                .clipShape(Capsule())
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.horizontal, Theme.paddingMd)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
                .themedCard()
            }
        }
    }

    // MARK: - Components

    private func selectableRow(
        title: String,
        subtitle: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Theme.textPrimary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
                if isSelected {
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

    private func modeDescription(_ mode: String) -> String {
        switch mode.lowercased() {
        case "code": return "Optimized for writing code"
        case "chat": return "General conversation"
        case "edit": return "Focused on editing files"
        case "plan": return "Planning and architecture"
        default: return ""
        }
    }
}

// MARK: - Themed Card Modifier

private extension View {
    func themedCard() -> some View {
        self
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}
