import SwiftUI

struct SessionSettingsSheet: View {
    let viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                agentSection
                modelSection
                modeSection
                sessionInfoSection
                permissionSection
            }
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

    @ViewBuilder
    private var agentSection: some View {
        Section("Agent") {
            LabeledContent("Type", value: viewModel.sessionAgent.capitalized)
        }
    }

    @ViewBuilder
    private var modelSection: some View {
        if let models = viewModel.availableModels, !models.isEmpty {
            Section("Model") {
                ForEach(models, id: \.self) { model in
                    modelRow(model)
                }
            }
        }
    }

    @ViewBuilder
    private var modeSection: some View {
        if let modes = viewModel.availableModes, !modes.isEmpty {
            Section("Mode") {
                ForEach(modes, id: \.self) { mode in
                    modeRow(mode)
                }
            }
        }
    }

    @ViewBuilder
    private var sessionInfoSection: some View {
        Section("Session") {
            LabeledContent("ID") {
                Text(viewModel.sessionId)
                    .font(.caption2.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let usage = viewModel.turnUsage {
                LabeledContent("Last Turn") {
                    Text("\(usage.inputTokens)↓ \(usage.outputTokens)↑ tokens")
                        .font(.caption.monospacedDigit())
                }
            }
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if !viewModel.permissionHistory.isEmpty {
            Section {
                NavigationLink {
                    PermissionHistoryView(history: viewModel.permissionHistory)
                } label: {
                    Label("Permission History", systemImage: "lock.shield")
                        .badge(viewModel.permissionHistory.count)
                }
            }
        }
    }

    // MARK: - Rows

    private func modelRow(_ model: String) -> some View {
        Button {
            viewModel.setModel(model)
        } label: {
            HStack {
                Text(model)
                    .foregroundStyle(.primary)
                Spacer()
                if viewModel.currentModel == model {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    private func modeRow(_ mode: String) -> some View {
        Button {
            viewModel.setMode(mode)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.capitalized)
                        .foregroundStyle(.primary)
                    let desc = modeDescription(mode)
                    if !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if viewModel.currentMode == mode {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
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
