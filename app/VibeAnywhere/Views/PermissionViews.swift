import SwiftUI

struct PermissionModalView: View {
    let request: PermissionRequest
    let onApprove: (String) -> Void
    let onDeny: () -> Void

    @State private var timeRemaining: TimeInterval = 60

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "lock.shield")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Permission Request")
                    .font(.headline)
                Spacer()
            }

            // Tool info
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(request.tool)
                        .font(.system(.body, design: .monospaced))
                } icon: {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Countdown
            HStack {
                Image(systemName: "clock")
                    .font(.caption)
                Text("Auto-deny in \(Int(timeRemaining))s")
                    .font(.caption)
            }
            .foregroundStyle(timeRemaining <= 10 ? .red : .secondary)

            // Action buttons
            HStack(spacing: 12) {
                Button(role: .destructive) {
                    onDeny()
                } label: {
                    Label("Deny", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                // Show approve options
                ForEach(approveOptions) { option in
                    Button {
                        onApprove(option.optionId)
                    } label: {
                        Label(option.name, systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
        .padding(.horizontal)
        .onReceive(timer) { _ in
            let elapsed = Date().timeIntervalSince(request.receivedAt)
            timeRemaining = max(0, 60 - elapsed)
        }
    }

    /// Filter to only show allow/approve options as buttons
    private var approveOptions: [PermissionOption] {
        request.options.filter { $0.kind.contains("allow") }
    }
}

// MARK: - Permission History

struct PermissionHistoryView: View {
    let history: [PermissionRecord]

    var body: some View {
        List(history) { record in
            HStack {
                Image(systemName: outcomeIcon(record.outcome))
                    .foregroundStyle(outcomeColor(record.outcome))
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.tool)
                        .font(.system(.body, design: .monospaced))
                    Text(record.outcome.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(record.resolvedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Permission History")
    }

    private func outcomeIcon(_ outcome: String) -> String {
        switch outcome {
        case "approved": return "checkmark.circle.fill"
        case "denied": return "xmark.circle.fill"
        case "auto-denied": return "clock.badge.xmark"
        default: return "questionmark.circle"
        }
    }

    private func outcomeColor(_ outcome: String) -> Color {
        switch outcome {
        case "approved": return .green
        case "denied": return .red
        case "auto-denied": return .orange
        default: return .secondary
        }
    }
}
