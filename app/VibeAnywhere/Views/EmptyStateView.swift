import SwiftUI

struct EmptyStateView: View {
    let onChipTapped: (String) -> Void

    private let chips = [
        ("sparkles", "Ask Anything"),
        ("doc.text", "Create Code"),
        ("chart.bar", "Analytics"),
        ("calendar", "Schedule"),
        ("gearshape.2", "Debug"),
    ]

    var body: some View {
        VStack(spacing: Theme.paddingLg) {
            Spacer()

            // Logo
            logoView

            // Welcome text
            Text("What can I help you today?")
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)

            // Quick action chips
            chipGrid

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Theme.paddingLg)
    }

    private var logoView: some View {
        ZStack {
            Circle()
                .fill(Theme.surface)
                .frame(width: 80, height: 80)
                .overlay(
                    Circle()
                        .stroke(Theme.border.opacity(0.6), lineWidth: 0.5)
                )

            Image(systemName: "waveform.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var chipGrid: some View {
        FlowLayout(spacing: Theme.paddingSm) {
            ForEach(chips, id: \.1) { icon, label in
                chipButton(icon: icon, label: label)
            }
        }
    }

    private func chipButton(icon: String, label: String) -> some View {
        Button {
            onChipTapped(label)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.subheadline)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.border.opacity(0.6), lineWidth: 0.5))
            .shadow(color: Theme.cardShadow, radius: 3, y: 1)
        }
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(subviews: subviews, width: proposal.width ?? .infinity)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, width: bounds.width)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(subviews: Subviews, width: CGFloat) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x - spacing)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
