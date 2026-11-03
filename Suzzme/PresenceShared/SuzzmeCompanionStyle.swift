import SwiftUI

struct SuzzmeActivityFace: View {
    let phase: SuzzmeLiveActivityPhase
    let color: Color
    let motionEnabled: Bool
    let stale: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    private var animates: Bool { motionEnabled && !stale && !reduceMotion && !luminanceReduced }

    private var tilt: Double {
        guard animates else { return 0 }
        switch phase {
        case .understanding: return -3
        case .checking: return 3
        default: return 0
        }
    }

    private var scale: CGFloat {
        guard animates else { return 1 }
        switch phase {
        case .listening: return 1.04
        case .understanding: return 0.96
        case .checking: return 1.02
        case .confirmation, .summaryReady, .urgentReady, .completed: return 1
        case .working: return 0.98
        case .speaking: return 1.03
        }
    }

    var body: some View {
        SuzzmeCharacterArtwork()
            .scaleEffect(scale)
            .rotationEffect(.degrees(tilt))
            .animation(animates ? .spring(duration: 0.42, bounce: 0.12) : nil, value: phase)
            .accessibilityLabel("Suzzme")
            .accessibilityValue(stale ? "Open Suzzme to continue" : phase.title)
    }
}

struct SuzzmeActivitySymbol: View {
    let phase: SuzzmeLiveActivityPhase
    let stale: Bool
    let color: Color
    let motionEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    var body: some View {
        let animates = motionEnabled && !stale && !reduceMotion && !luminanceReduced
        Image(systemName: stale ? "moon" : phase.symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
            .contentTransition(animates ? .symbolEffect(.replace) : .identity)
            .animation(animates ? .easeInOut(duration: 0.3) : nil, value: phase)
            .accessibilityLabel(stale ? "Open Suzzme to continue" : phase.title)
    }
}

extension SuzzmeLiveActivityAppearance {
    var islandColor: Color { color(dark: true) }
    func color(dark: Bool) -> Color {
        switch self {
        case .blue: dark ? Color(red: 0.49, green: 0.74, blue: 0.98) : Color(red: 0.12, green: 0.43, blue: 0.82)
        case .pink: dark ? Color(red: 0.98, green: 0.49, blue: 0.72) : Color(red: 0.69, green: 0.20, blue: 0.43)
        case .red: dark ? Color(red: 0.98, green: 0.49, blue: 0.52) : Color(red: 0.76, green: 0.22, blue: 0.27)
        case .orange: dark ? Color(red: 0.98, green: 0.66, blue: 0.49) : Color(red: 0.72, green: 0.34, blue: 0.12)
        case .yellow: dark ? Color(red: 0.98, green: 0.87, blue: 0.49) : Color(red: 0.54, green: 0.40, blue: 0.04)
        case .green: dark ? Color(red: 0.50, green: 0.98, blue: 0.49) : Color(red: 0.16, green: 0.48, blue: 0.20)
        case .teal: dark ? Color(red: 0.49, green: 0.98, blue: 0.89) : Color(red: 0.02, green: 0.48, blue: 0.46)
        case .purple: dark ? Color(red: 0.76, green: 0.49, blue: 0.98) : Color(red: 0.48, green: 0.25, blue: 0.70)
        case .suzzmePurple: dark ? Color(red: 0.80, green: 0.68, blue: 1) : Color(red: 0.38, green: 0.12, blue: 0.62)
        case .burgundy: dark ? Color(red: 0.94, green: 0.57, blue: 0.54) : Color(red: 0.50, green: 0.12, blue: 0.23)
        case .deepBlue: dark ? Color(red: 0.52, green: 0.77, blue: 1) : Color(red: 0.08, green: 0.25, blue: 0.57)
        case .silver: dark ? Color(red: 0.82, green: 0.86, blue: 0.91) : Color(red: 0.38, green: 0.42, blue: 0.49)
        case .graphite: dark ? Color(red: 0.88, green: 0.90, blue: 0.96) : Color(red: 0.17, green: 0.19, blue: 0.24)
        }
    }
}

