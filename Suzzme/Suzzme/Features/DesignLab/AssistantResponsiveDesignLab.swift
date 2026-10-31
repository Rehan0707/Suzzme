#if DEBUG
import SwiftUI

enum PresenceAnimationCurve: String, CaseIterable, Identifiable {
    case smooth, easeInOut, spring
    var id: String { rawValue }
    var title: String { self == .easeInOut ? "Ease In Out" : rawValue.capitalized }
}

struct PresenceAnimationConfiguration: Equatable {
    var curve: PresenceAnimationCurve = .spring
    var springResponse = SuzzmeTheme.Motion.presenceResponse
    var damping = SuzzmeTheme.Motion.presenceDamping
    var duration = SuzzmeTheme.Motion.presenceExpansion
    var delay = 0.08
    var expansionWidth = 360.0
    var expansionHeight = 96.0
    var cornerRadius = Double(SuzzmeTheme.Radius.hero)
    var glowIntensity = 0.18
    var purpleIntensity = 0.72
    var simulateReducedMotion = false

    static let approved = Self(
        curve: .spring,
        springResponse: 0.42,
        damping: 0.88,
        duration: 0.30,
        delay: 0.04,
        expansionWidth: 372,
        expansionHeight: 94,
        cornerRadius: 30,
        glowIntensity: 0.14,
        purpleIntensity: 0.64
    )

    var animation: Animation? {
        guard !simulateReducedMotion else { return nil }
        switch curve {
        case .smooth:
            return Animation.smooth(duration: duration).delay(delay)
        case .easeInOut:
            return Animation.easeInOut(duration: duration).delay(delay)
        case .spring:
            return Animation.spring(response: springResponse, dampingFraction: damping).delay(delay)
        }
    }
}

struct PresenceAnimationPlayground: View {
    @State private var configuration = PresenceAnimationConfiguration.approved
    @State private var state: SuzzmeAssistantState = .idle
    @State private var expanded = false
    @State private var sequenceTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.large) {
                    stage.frame(maxWidth: .infinity, minHeight: 420)
                    controls.frame(width: min(340, proxy.size.width * 0.38))
                }
                ScrollView { VStack(spacing: SuzzmeTheme.Spacing.large) { stage; controls } }
            }
            .padding(SuzzmeTheme.Layout.pageInset)
        }
        .navigationTitle("Presence Animation Playground")
        .onDisappear { sequenceTask?.cancel() }
    }

    private var stage: some View {
        ZStack {
            SuzzmeTheme.backgroundSecondary
            VStack(spacing: SuzzmeTheme.Spacing.large) {
                Text("Visual simulation only — microphone and AI are inactive")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: SuzzmeTheme.Spacing.medium) {
                    SuzzmeFace(state: state, audioLevel: state == .listening ? 0.7 : 0).frame(width: 46, height: 46)
                    if expanded {
                        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                            Text(SuzzmeAssistantPresentation.make(for: state).title).font(.headline)
                            Text(SuzzmeAssistantPresentation.make(for: state).systemStatus).font(.caption).foregroundStyle(.secondary)
                        }
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .padding(.horizontal, SuzzmeTheme.Spacing.large)
                .frame(width: expanded ? configuration.expansionWidth : 112, height: expanded ? configuration.expansionHeight : 58)
                .background(SuzzmeTheme.intelligenceSurface.opacity(configuration.purpleIntensity), in: RoundedRectangle(cornerRadius: configuration.cornerRadius, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: configuration.cornerRadius).strokeBorder(SuzzmeTheme.intelligencePrimary.opacity(0.22)) }
                .shadow(color: SuzzmeTheme.intelligencePrimary.opacity(configuration.glowIntensity), radius: expanded ? 28 : 10)
                .animation(configuration.animation, value: expanded)
                .animation(configuration.animation, value: state)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.largeSurface))
    }

    private var controls: some View {
        Form {
            Section("Playback") {
                Picker("Curve", selection: $configuration.curve) { ForEach(PresenceAnimationCurve.allCases) { Text($0.title).tag($0) } }
                Toggle("Simulate Reduced Motion", isOn: $configuration.simulateReducedMotion)
                Button("Play Phase 1 · Activation") { play([.idle, .listening]) }
                Button("Play Phase 2 · Response") { play([.listening, .reasoning, .speaking, .idle]) }
                Button("Play Full Sequence") { play([.idle, .listening, .reasoning, .speaking, .idle]) }
                Button("Reset") { reset() }
            }
            Section("Motion") {
                slider("Spring response", value: $configuration.springResponse, range: 0.15...1.2)
                slider("Damping", value: $configuration.damping, range: 0.4...1)
                slider("Duration", value: $configuration.duration, range: 0.1...1.5)
                slider("Delay", value: $configuration.delay, range: 0...0.8)
            }
            Section("Geometry") {
                slider("Expansion width", value: $configuration.expansionWidth, range: 220...620)
                slider("Expansion height", value: $configuration.expansionHeight, range: 64...180)
                slider("Corner radius", value: $configuration.cornerRadius, range: 12...48)
                slider("Glow intensity", value: $configuration.glowIntensity, range: 0...0.45)
                slider("Purple intensity", value: $configuration.purpleIntensity, range: 0.15...1)
            }
        }
        .formStyle(.grouped)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(value.wrappedValue, format: .number.precision(.fractionLength(2)))").font(.caption)
            Slider(value: value, in: range)
        }
    }

    private func play(_ states: [SuzzmeAssistantState]) {
        sequenceTask?.cancel()
        sequenceTask = Task { @MainActor in
            for (index, next) in states.enumerated() {
                guard !Task.isCancelled else { return }
                withAnimation(configuration.animation) { state = next; expanded = next != .idle || index > 0 }
                guard !configuration.simulateReducedMotion else { continue }
                do { try await Task.sleep(for: .seconds(max(configuration.duration + configuration.delay, 0.2))) } catch { return }
            }
            if states.last == .idle { withAnimation(configuration.animation) { expanded = false } }
        }
    }

    private func reset() {
        sequenceTask?.cancel()
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { state = .idle; expanded = false }
    }
}

struct AssistantResponsiveDesignLab: View {
    @State private var concept: AssistantDesignConcept = .signature
    @State private var previewState: AssistantPreviewState = .success
    @State private var appearance: SuzzmeAppearance = .system

    var body: some View {
        GeometryReader { proxy in
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) { preview; Divider(); controls.frame(width: min(340, proxy.size.width * 0.34)) }
                ScrollView { VStack(spacing: 0) { preview.frame(minHeight: 620); Divider(); controls } }
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .navigationTitle("Assistant Design Lab")
    }
    private var preview: some View { AssistantDesignConceptView(concept: concept, previewState: previewState).frame(maxWidth: .infinity, maxHeight: .infinity) }
    private var controls: some View {
        Form {
            Section("Concept") {
                Picker("Variation", selection: $concept) { ForEach(AssistantDesignConcept.allCases) { Text($0.title).tag($0) } }
                Picker("Preview state", selection: $previewState) { ForEach(AssistantPreviewState.allCases) { Text($0.title).tag($0) } }
                Picker("Appearance", selection: $appearance) { ForEach(SuzzmeAppearance.allCases) { Text($0.title).tag($0) } }
            }
            Section("Animation") { NavigationLink("Open Presence playground") { PresenceAnimationPlayground() } }
            Section("Safety") {
                Label("Preview fixtures only", systemImage: "hammer")
                Text("This lab does not request permissions, access personal data, invoke a microphone, or call an AI model.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

#Preview("Design Lab") { NavigationStack { AssistantResponsiveDesignLab() } }
#Preview("Presence Animation Playground") { NavigationStack { PresenceAnimationPlayground() } }
#endif
