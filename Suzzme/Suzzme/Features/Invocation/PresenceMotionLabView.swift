#if DEBUG
import SwiftUI

struct PresenceMotionLabView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var state: SuzzmeAssistantState = .idle
    @State private var signal: SuzzmeProactivePresenceSignal = .none
    @State private var response = SuzzmeTheme.Motion.presenceResponse
    @State private var damping = SuzzmeTheme.Motion.presenceDamping
    @State private var duration = SuzzmeTheme.Motion.presenceExpansion
    @State private var delay = 0.0
    @State private var glow = SuzzmeTheme.Motion.presenceGlow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var transitionTask: Task<Void, Never>?
    @State private var expanded = false
    @State private var previewInteraction = "Tap the compact Presence to verify interaction."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.large) {
                Text("Presence Motion Lab").font(.largeTitle.bold())
                Text("Development-only inspection of the shared assistant state. Values here are never saved.").foregroundStyle(SuzzmeTheme.textSecondary)
                preview
                SuzzmeCard {
                    Picker("Assistant state", selection: $state) { ForEach(SuzzmeAssistantState.allCases, id: \.self) { Text(label($0)).tag($0) } }
                    Picker("Proactive signal", selection: $signal) { ForEach(SuzzmeProactivePresenceSignal.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Toggle("Expanded", isOn: $expanded)
                }
                SuzzmeCard {
                    Text("Development parameters").font(.headline)
                    slider("Spring response", value: $response, range: 0.15...1)
                    slider("Damping", value: $damping, range: 0.45...1)
                    slider("Duration", value: $duration, range: 0...1.5)
                    slider("Delay", value: $delay, range: 0...0.5)
                    slider("Glow intensity", value: $glow, range: 0...0.6)
                }
                SuzzmeCard {
                    Text("Transitions").font(.headline)
                    ForEach(MotionTransition.allCases, id: \.self) { transition in
                        Button(transition.title) { run(transition) }.buttonStyle(.bordered)
                    }
                }
            }
            .padding(SuzzmeTheme.Spacing.large).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .navigationTitle("Motion Lab")
        .onDisappear { transitionTask?.cancel() }
    }

    @ViewBuilder private var preview: some View {
        #if os(macOS)
        let compactSize = MacAssistantSurfaceMetrics.size(
            state: state,
            signal: signal,
            notchWidth: 180,
            review: nil,
            response: nil
        )
        VStack(spacing: 0) {
            Text("Simulated notch · not physical alignment evidence").font(.caption).foregroundStyle(.secondary).padding(.bottom, 12)
            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).fill(.black).frame(width: 180, height: 28)
            MacAssistantNotchSurface(state: state, theme: environment.invocation.presenceTheme, animation: environment.invocation.presenceAnimation, signal: signal, hasNotch: true, notchWidth: 180, edgeGlow: glow, onCancel: {}, onInvoke: { previewInteraction = "Presence responded." })
                .frame(
                    width: expanded ? max(compactSize.width, 360) : compactSize.width,
                    height: expanded ? max(compactSize.height, 132) : compactSize.height
                )
                .animation(reduceMotion ? nil : .easeInOut(duration: duration), value: state)
                .animation(reduceMotion ? nil : .spring(response: response, dampingFraction: damping).delay(delay), value: expanded)
            Text(previewInteraction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("presence-preview-interaction")
        }.frame(maxWidth: .infinity, minHeight: 240, alignment: .top)
        #else
        SuzzmeAssistantPresenceView(state: state, theme: environment.invocation.presenceTheme, animation: environment.invocation.presenceAnimation, proactiveSignal: signal, showsCancel: state != .idle)
            .frame(maxWidth: expanded ? 520 : 330)
            .scaleEffect(expanded ? 1 : 0.98)
            .shadow(color: SuzzmeTheme.intelligencePrimary.opacity(glow), radius: 18)
            .frame(maxWidth: .infinity, minHeight: expanded ? 190 : 130)
            .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .animation(reduceMotion ? nil : .spring(response: response, dampingFraction: damping).delay(delay), value: expanded)
            .animation(reduceMotion ? nil : .easeInOut(duration: duration), value: state)
        #endif
    }

    private func run(_ transition: MotionTransition) {
        state = transition.from; expanded = transition.expandedFrom
        transitionTask?.cancel()
        transitionTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            withAnimation(reduceMotion ? nil : .spring(response: response, dampingFraction: damping)) { state = transition.to; expanded = transition.expandedTo }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) { Text("\(title): \(value.wrappedValue, format: .number.precision(.fractionLength(2)))").font(.caption); Slider(value: value, in: range) }
    }
    private func label(_ state: SuzzmeAssistantState) -> String {
        switch state { case .idle: "Idle"; case .listening: "Listening"; case .transcribing: "Transcribing"; case .understanding: "Understanding"; case .gatheringContext: "Gathering Context"; case .reasoning: "Reasoning"; case .planning: "Planning"; case .awaitingConfirmation: "Awaiting Confirmation"; case .acting: "Acting"; case .speaking: "Speaking"; case .success: "Success"; case .error: "Error" }
    }
}

private enum MotionTransition: CaseIterable {
    case compactExpanded, expandedCompact, idleListening, listeningUnderstanding, reasoningConfirmation, confirmationActing, actingSuccess, errorRecovery
    var title: String { switch self { case .compactExpanded: "Compact → expanded"; case .expandedCompact: "Expanded → compact"; case .idleListening: "Idle → listening"; case .listeningUnderstanding: "Listening → understanding"; case .reasoningConfirmation: "Reasoning → confirmation"; case .confirmationActing: "Confirmation → acting"; case .actingSuccess: "Acting → success (presentation only)"; case .errorRecovery: "Error → recovery" } }
    var from: SuzzmeAssistantState { switch self { case .compactExpanded, .expandedCompact, .idleListening: .idle; case .listeningUnderstanding: .listening; case .reasoningConfirmation: .reasoning; case .confirmationActing: .awaitingConfirmation; case .actingSuccess: .acting; case .errorRecovery: .error } }
    var to: SuzzmeAssistantState { switch self { case .compactExpanded, .expandedCompact: .idle; case .idleListening: .listening; case .listeningUnderstanding: .understanding; case .reasoningConfirmation: .awaitingConfirmation; case .confirmationActing: .acting; case .actingSuccess: .success; case .errorRecovery: .idle } }
    var expandedFrom: Bool { self == .expandedCompact || self == .reasoningConfirmation || self == .confirmationActing || self == .errorRecovery }
    var expandedTo: Bool { self == .compactExpanded || self == .reasoningConfirmation || self == .confirmationActing }
}

#Preview("Motion Lab") { NavigationStack { PresenceMotionLabView() }.environment(AppEnvironment.preview) }
#endif
