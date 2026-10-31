import SwiftUI

extension SuzzmeAssistantState {
    var haloDuration: Double {
        SuzzmePresenceMotion.make(for: self).duration + SuzzmeTheme.Motion.calm
    }
}


struct SuzzmeHalo: View {
    var state: SuzzmeAssistantState = .idle
    var presenceTheme: SuzzmePresenceTheme
    var animation: SuzzmePresenceAnimation = .gentle
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase: CGFloat = 0
    private var motion: SuzzmePresenceMotion { .make(for: state) }

    init(state: SuzzmeAssistantState = .idle, theme: SuzzmePresenceTheme = .suzzmePurple, animation: SuzzmePresenceAnimation = .gentle) {
        self.state = state
        self.presenceTheme = theme
        self.animation = animation
    }

    var body: some View {
        let colors = SuzzmePresenceColors.mascot(for: colorScheme)
        ZStack {
            if !reduceTransparency && colorSchemeContrast != .increased && state != .idle {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [colors.primary.opacity(colorSchemeContrast == .increased ? 0.78 : 0.58), colors.secondary.opacity(colorSchemeContrast == .increased ? 0.56 : 0.36)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 182, height: 28)
                    .blur(radius: 18)
            }
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [colors.primary, colors.secondary, colors.highlight],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 96, height: colorSchemeContrast == .increased ? 8 : 6)
                .scaleEffect(x: 1 + phase * motion.spread)
                .offset(x: phase * motion.travel * SuzzmeTheme.Spacing.small)
                .opacity(state == .idle ? 0.4 : 1)
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Suzzme presence")
        .accessibilityValue(SuzzmeAssistantPresentation.make(for: state).systemStatus)
        .task(id: "\(reduceMotion)-\(state.rawValue)-\(animation.rawValue)-\(scenePhase == .active)") {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { phase = 0 }
            guard SuzzmePresenceMotion.allowsMotion(state: state, animation: animation,
                                                     reduceMotion: reduceMotion, isActive: scenePhase == .active) else { return }
            let duration = motion.entryDuration(for: animation)
            withAnimation(.smooth(duration: duration)) { phase = 1 }
            do { try await Task.sleep(for: .seconds(duration)) }
            catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: SuzzmeTheme.Motion.calm)) { phase = 0 }
        }
    }
}

#Preview("Halo states") {
    VStack { ForEach(SuzzmeAssistantState.allCases, id: \.self) { SuzzmeHalo(state: $0) } }
        .padding().background(SuzzmeTheme.background)
}
