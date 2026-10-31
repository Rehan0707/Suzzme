import SwiftUI

/// A finite visual interpretation of the existing assistant state, not another
/// lifecycle. Each entry resolves to a still pose; listening alone follows RMS.
struct SuzzmePresenceMotion: Equatable {
    let scale: CGFloat
    let lift: CGFloat
    let tilt: Double
    let spread: CGFloat
    let travel: CGFloat
    let duration: Double

    static func make(for state: SuzzmeAssistantState) -> Self {
        switch state {
        case .idle: .init(scale: 0, lift: 0, tilt: 0, spread: 0, travel: 0, duration: 0)
        case .understanding: .init(scale: 0.045, lift: -1.8, tilt: 0, spread: 0.12, travel: 0.18, duration: SuzzmeTheme.Motion.quick)
        case .listening: .init(scale: 0.025, lift: -0.8, tilt: 0, spread: 0.08, travel: 0.12, duration: SuzzmeTheme.Motion.quick)
        case .transcribing: .init(scale: -0.035, lift: 0.8, tilt: 0, spread: -0.12, travel: -0.16, duration: SuzzmeTheme.Motion.standard)
        case .gatheringContext: .init(scale: 0.025, lift: -0.6, tilt: -2, spread: 0.16, travel: 0.35, duration: SuzzmeTheme.Motion.calm)
        case .reasoning: .init(scale: -0.018, lift: -1, tilt: 1.2, spread: -0.08, travel: -0.24, duration: SuzzmeTheme.Motion.calm)
        case .planning: .init(scale: 0.015, lift: -0.6, tilt: -1, spread: 0.08, travel: 0.24, duration: SuzzmeTheme.Motion.standard)
        case .awaitingConfirmation: .init(scale: 0.015, lift: 0, tilt: 0, spread: 0.04, travel: 0.06, duration: SuzzmeTheme.Motion.standard)
        case .acting: .init(scale: 0.03, lift: -1.2, tilt: -1.5, spread: 0.12, travel: 0.28, duration: SuzzmeTheme.Motion.standard)
        case .speaking: .init(scale: 0.035, lift: -0.8, tilt: 1.5, spread: 0.1, travel: 0.2, duration: SuzzmeTheme.Motion.standard)
        case .success: .init(scale: 0.05, lift: -1.2, tilt: 0, spread: 0.18, travel: 0.14, duration: SuzzmeTheme.Motion.standard)
        case .error: .init(scale: -0.025, lift: 0.7, tilt: 0, spread: -0.04, travel: -0.08, duration: SuzzmeTheme.Motion.standard)
        }
    }

    static func allowsMotion(state: SuzzmeAssistantState, animation: SuzzmePresenceAnimation,
                             reduceMotion: Bool, isActive: Bool) -> Bool {
        state != .idle && animation != .minimal && !reduceMotion && isActive
    }

    func entryDuration(for animation: SuzzmePresenceAnimation) -> Double {
        switch animation {
        case .minimal: 0
        case .flow: duration * 1.25
        case .pulse: duration * 0.8
        case .gentle: duration
        }
    }
}

/// Compatibility for existing layout callers. The retired stroke mark has no
/// renderer: every legacy Face now presents the same blue cloud companion.
/// Color/lineWidth remain source-compatible but never recolor the character.
struct SuzzmeFace: View {
    var state: SuzzmeAssistantState = .idle
    var color: Color = SuzzmeTheme.accent
    var lineWidth: CGFloat = 4
    var animation: SuzzmePresenceAnimation = .gentle
    var audioLevel: Double = 0
    var speechProgress: Double = 0

    var body: some View {
        GeometryReader { geometry in
            SuzzmeMascot(state: state,
                size: min(geometry.size.width, geometry.size.height),
                isAnimated: state != .idle,
                animation: animation,
                audioLevel: audioLevel, speechProgress: speechProgress)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

#Preview("Suzzme cloud") {
    HStack {
        ForEach(SuzzmeAssistantState.allCases, id: \.self) { state in
            SuzzmeFace(state: state).frame(width: 44, height: 44)
        }
    }.padding()
}
