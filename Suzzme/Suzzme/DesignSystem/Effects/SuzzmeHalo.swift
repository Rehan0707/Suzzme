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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @State private var expanded = false

    var body: some View {
        ZStack {
            if !reduceTransparency {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [SuzzmeTheme.lavender.opacity(0.58), SuzzmeTheme.lilac.opacity(0.36)],
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
                        colors: [SuzzmeTheme.lavender, SuzzmeTheme.lilac, SuzzmeTheme.lavender],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 96, height: 6)
                .scaleEffect(x: expanded ? 1.06 : 1)
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Suzzme presence")
        .accessibilityValue(state.rawValue.capitalized)
        .task(id: "\(reduceMotion)-\(state.rawValue)-\(scenePhase == .active)") {
            expanded = false
            guard !reduceMotion, scenePhase == .active else { return }
            withAnimation(.easeInOut(duration: state.haloDuration).repeatForever(autoreverses: true)) {
                expanded = true
            }
        }
    }
}

#Preview("Halo states") {
    VStack { ForEach(SuzzmeAssistantState.allCases, id: \.self) { SuzzmeHalo(state: $0) } }
        .padding().background(SuzzmeTheme.background)
}
