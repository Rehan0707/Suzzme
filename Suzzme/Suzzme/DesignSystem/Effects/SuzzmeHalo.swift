import SwiftUI

extension SuzzmeAssistantState {
    var haloDuration: Double {
        switch self {
        case .idle: 4
        case .listening, .transcribing: 2.5
        case .understanding, .gatheringContext, .reasoning, .planning: 1.8
        case .acting, .speaking, .success, .error, .awaitingConfirmation: 1.2
        }
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
    @State private var expanded = false

    init(state: SuzzmeAssistantState = .idle, theme: SuzzmePresenceTheme = .suzzmePurple, animation: SuzzmePresenceAnimation = .gentle) {
        self.state = state
        self.presenceTheme = theme
        self.animation = animation
    }

    var body: some View {
        let colors = presenceTheme.colors(for: colorScheme)
        ZStack {
            if !reduceTransparency {
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
                .scaleEffect(x: expanded ? 1.06 : 1)
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Suzzme presence")
        .accessibilityValue(state.rawValue.capitalized)
        .task(id: "\(reduceMotion)-\(state.rawValue)-\(animation.rawValue)-\(scenePhase == .active)") {
            expanded = false
            guard !reduceMotion, scenePhase == .active, state != .idle, animation.duration > 0 else { return }
            withAnimation(.easeInOut(duration: max(state.haloDuration, animation.duration)).repeatForever(autoreverses: true)) {
                expanded = true
            }
        }
    }
}

#Preview("Halo states") {
    VStack { ForEach(SuzzmeAssistantState.allCases, id: \.self) { SuzzmeHalo(state: $0) } }
        .padding().background(SuzzmeTheme.background)
}
