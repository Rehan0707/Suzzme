import SwiftUI

enum SuzzmeTheme {
    static let backgroundPrimary = Color("Canvas")
    static let backgroundSecondary = Color("Surface")
    static let surface = Color("Surface")
    static let surfaceElevated = Color("Canvas")
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color.secondary.opacity(0.72)
    static let separator = Color.primary.opacity(0.10)
    static let controlFill = Color.primary.opacity(0.06)
    static let intelligencePrimary = Color("AccentColor")
    static let intelligenceSecondary = Color(red: 203 / 255, green: 195 / 255, blue: 227 / 255)
    static let intelligenceHighlight = Color(red: 218 / 255, green: 177 / 255, blue: 218 / 255)
    static let intelligenceSurface = Color("PurpleWash")
    static let success = Color.green
    static let warning = Color.orange
    static let destructive = Color.red

    // Compatibility aliases. New feature UI should use the semantic names.
    static let background = backgroundPrimary
    static let accent = intelligencePrimary
    static let lavender = Color(red: 218 / 255, green: 177 / 255, blue: 218 / 255)
    static let lilac = Color(red: 203 / 255, green: 195 / 255, blue: 227 / 255)
    static let wash = intelligenceSurface

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let extraLarge: CGFloat = 32
        static let hero: CGFloat = 48
    }

    enum Radius {
        static let control: CGFloat = 12
        static let card: CGFloat = 20
        static let largeSurface: CGFloat = 28
        static let hero: CGFloat = 36
    }

    enum Motion {
        static let quick = 0.18
        static let standard = 0.28
        static let calm = 0.45
        static let presenceGlow = 0.12
        static let presenceExpansion = 0.28
        static let presenceResponse = 0.42
        static let presenceDamping = 0.9
    }

    static let cornerRadius = Radius.card
    static let compactCornerRadius = Radius.control
    static let spacing = Spacing.large
    static let hairline: CGFloat = 1

    static var launchGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundPrimary, intelligenceSurface.opacity(0.55), backgroundPrimary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var pageGradient: LinearGradient {
        LinearGradient(colors: [backgroundPrimary, backgroundPrimary], startPoint: .top, endPoint: .bottom)
    }

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [intelligencePrimary, intelligenceSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
