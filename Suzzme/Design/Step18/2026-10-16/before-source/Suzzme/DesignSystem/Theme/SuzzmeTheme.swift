import SwiftUI

enum SuzzmeAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

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
        static let card: CGFloat = 18
        static let largeSurface: CGFloat = 24
        static let hero: CGFloat = 32
    }

    /// Content measures, independent of a particular device or window size.
    enum Layout {
        static let companionWidth: CGFloat = 600
        static let suggestionWidth: CGFloat = 360
        static let companionFace: CGFloat = 80
        static let menuBarWidth: CGFloat = 320
        static let readingWidth: CGFloat = 680
        static let workspaceWidth: CGFloat = 920
        static let primaryColumnMinimum: CGFloat = 420
        static let secondaryColumnMinimum: CGFloat = 280
        static let pageInset: CGFloat = 24
        static let compactInset: CGFloat = 20
        static let touchTarget: CGFloat = 44
        static let rowMinimum: CGFloat = 52
        static let symbolColumn: CGFloat = 28
        static let sidebarMin: CGFloat = 200
        static let sidebarIdeal: CGFloat = 232
        static let sidebarMax: CGFloat = 280
        static let windowMinWidth: CGFloat = 640
        static let windowMinHeight: CGFloat = 500
    }

    enum Motion {
        static let quick = 0.18
        static let standard = 0.28
        static let calm = 0.45
        static let presenceGlow = 0.12
        static let presenceExpansion = 0.28
        static let presenceResponse = 0.42
        static let presenceDamping = 0.9

        /// Immediate control feedback; native keyboard actions stay instantaneous.
        static func feedback(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeOut(duration: quick)
        }

        /// Finite changes between readable interface states.
        static func transition(reduceMotion: Bool) -> Animation {
            reduceMotion ? .easeOut(duration: presenceGlow) : .smooth(duration: standard, extraBounce: 0)
        }

        static func presence(reduceMotion: Bool) -> Animation {
            reduceMotion ? .easeOut(duration: presenceGlow)
                : .spring(response: presenceResponse, dampingFraction: presenceDamping)
        }
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

    static var pageBackground: Color { backgroundPrimary }

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [intelligencePrimary, intelligenceSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
