import SwiftUI

// MARK: - Design Tokens

enum Theme {
    // Colors
    static let background = Color(hex: 0xF2F1EE)
    static let surface = Color.white
    static let border = Color(hex: 0xE8E7E3)
    static let borderLight = Color(hex: 0xF0EFEC)
    static let textPrimary = Color(hex: 0x1A1A1A)
    static let textSecondary = Color(hex: 0x666666)
    static let textTertiary = Color(hex: 0x999999)
    static let accent = Color(hex: 0x4CAF50)
    static let accentWarm = Color(hex: 0xF59E0B)
    static let buttonDark = Color(hex: 0x1A1A1A)

    // Spacing
    static let paddingSm: CGFloat = 8
    static let paddingMd: CGFloat = 16
    static let paddingLg: CGFloat = 24

    // Radius
    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16
    static let radiusXl: CGFloat = 24

    // Shadows
    static let cardShadow = Color.black.opacity(0.04)
}

// MARK: - Color Extension

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusLg)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .shadow(color: Theme.cardShadow, radius: 2, y: 1)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
