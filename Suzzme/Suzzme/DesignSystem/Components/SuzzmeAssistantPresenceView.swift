import SwiftUI

/// A resolved action's visual projection, never an authorization token.
struct SuzzmePresenceReview: Equatable, Sendable {
    let id: UUID
    let title: String
    let confirmationLabel: String
    let isDestructive: Bool
}

/// Shared in-app presentation for the one Suzzme assistant state machine.
struct SuzzmeAssistantPresenceView: View {
    let state: SuzzmeAssistantState
    var theme: SuzzmePresenceTheme = .suzzmePurple
    var animation: SuzzmePresenceAnimation = .gentle
    var proactiveSignal: SuzzmeProactivePresenceSignal = .none
    var showsCancel: Bool = true
    var systemSurface = false
    var audioLevel: Double = 0
    var speechProgress: Double = 0
    var contextTitle: String? = nil
    var onCancel: (() -> Void)?
    var onInvoke: (() -> Void)?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var presentation: SuzzmeAssistantPresentation { .make(for: state) }

    @ViewBuilder var body: some View {
        if !isCancellable, let onInvoke {
            Button(action: onInvoke) { presenceContent }
                .buttonStyle(.plain)
                .accessibilityLabel(displayStatus)
                .accessibilityHint("Opens Suzzme for details")
        } else {
            presenceContent
        }
    }

    @ViewBuilder private var presenceContent: some View {
        if systemSurface {
            systemPresenceContent
        } else {
            inAppPresenceContent
        }
    }

    private var inAppPresenceContent: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: SuzzmeTheme.Spacing.small))
            : AnyLayout(HStackLayout(spacing: SuzzmeTheme.Spacing.small))
        return layout {
            SuzzmeMascot(state: state, size: SuzzmeTheme.Layout.touchTarget,
                animation: animation, audioLevel: audioLevel, speechProgress: speechProgress)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                Text(displayTitle).font(.subheadline.weight(.semibold)).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if state == .listening {
                    SuzzmeListeningField(level: audioLevel, color: signalColor, animation: animation)
                } else if state == .speaking {
                    SuzzmeSpeechProgressField(progress: speechProgress, color: signalColor, animation: animation)
                } else if state == .idle {
                    Text(proactiveSignal == .none ? "Ready when you are" : proactiveSignal.status)
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(displayStatus)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsCancel, isCancellable {
                Button(action: { onCancel?() }) {
                    Text("Cancel").frame(minWidth: 44, minHeight: 44)
                }
                    .buttonStyle(.bordered)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("Cancel Suzzme")
                    .accessibilityHint("Stops listening and cancels the current request")
            }
        }
        .padding(SuzzmeTheme.Spacing.small)
        .suzzmeContentSurface(cornerRadius: SuzzmeTheme.Radius.card,
                              tint: signalColor.opacity(isQuietIdle ? 0.04 : 0.12))
        .overlay {
            let shape = RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.card, style: .continuous)
            shape
                .strokeBorder(isQuietIdle ? SuzzmeTheme.separator : signalColor.opacity(reduceTransparency ? 0.55 : increasedContrast ? 0.72 : 0.20), lineWidth: increasedContrast ? 1.75 : 1)
            if !isQuietIdle {
                SuzzmePresenceEdgeTrace(
                    shape: shape,
                    primary: signalColor,
                    secondary: SuzzmePresenceColors.mascot(for: colorScheme).secondary,
                    highlight: SuzzmePresenceColors.mascot(for: colorScheme).highlight,
                    state: state,
                    isActive: presentation.emphasis != .ambient,
                    animation: animation
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(displayStatus)
        .contentShape(Rectangle())
    }

    private var systemPresenceContent: some View {
        let compact = isQuietIdle
        let colors = SuzzmePresenceColors.mascot(for: .dark)
        return HStack(spacing: SuzzmeTheme.Spacing.small) {
            SuzzmeMascot(
                state: state,
                size: compact ? 24 : SuzzmeTheme.Layout.touchTarget,
                animation: animation,
                audioLevel: audioLevel,
                speechProgress: speechProgress
            )
            .accessibilityHidden(true)

            if !compact {
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                    Text(displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.interpolate)
                    if state == .listening {
                        SuzzmeListeningField(level: audioLevel, color: colors.highlight, animation: animation)
                    } else if state == .speaking {
                        SuzzmeSpeechProgressField(progress: speechProgress, color: colors.highlight, animation: animation)
                    }
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: SuzzmeTheme.Spacing.xxs)

                if showsCancel, isCancellable {
                    Button(action: { onCancel?() }) {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(increasedContrast ? 1 : 0.82))
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(reduceTransparency ? 0.16 : 0.10), in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel Suzzme")
                    .accessibilityHint("Stops the current request")
                } else if state == .success || state == .error {
                    Image(systemName: state == .success ? "checkmark" : "exclamationmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(state == .success ? SuzzmeTheme.success : SuzzmeTheme.destructive)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, SuzzmeTheme.Spacing.medium)
        .padding(.top, compact ? 6 : 12)
        .padding(.bottom, compact ? 7 : 12)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(displayStatus)
        .contentShape(Rectangle())
    }

    private var isCancellable: Bool {
        switch state {
        case .listening, .transcribing, .understanding, .gatheringContext, .reasoning, .planning, .acting, .speaking: true
        case .idle, .awaitingConfirmation, .success, .error: false
        }
    }

    private var increasedContrast: Bool { colorSchemeContrast == .increased }
    private var isQuietIdle: Bool { state == .idle && proactiveSignal == .none }
    private var displayTitle: String {
        if state == .idle && proactiveSignal != .none { return proactiveSignal.title }
        if let title = contextTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { return title }
        return switch state {
        case .transcribing: "Finishing your words…"
        case .gatheringContext: "Checking what matters…"
        default: presentation.title
        }
    }
    private var displayStatus: String {
        if state == .idle && proactiveSignal != .none { return proactiveSignal.status }
        if contextTitle != nil { return "Suzzme. \(displayTitle)" }
        return switch state {
        case .transcribing: "Suzzme finishing your words"
        case .gatheringContext: "Suzzme checking what matters"
        default: presentation.systemStatus
        }
    }

    private var signalColor: Color {
        switch presentation.emphasis {
        case .error: SuzzmeTheme.warning
        case .success: .green
        case .ambient, .active, .confirmation: SuzzmePresenceColors.mascot(for: colorScheme).highlight
        }
    }

}

/// A tiny voice field driven only by measured microphone input. The fixed
/// weights spread that one input across the field without simulated activity.
struct SuzzmeListeningField: View {
    let level: Double
    var color: Color = SuzzmeTheme.intelligencePrimary
    var animation: SuzzmePresenceAnimation = .gentle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    private static let weights: [CGFloat] = [0.25, 0.42, 0.68, 0.86, 1, 0.86, 0.68, 0.42, 0.25]
    private var energy: CGFloat { level.isFinite ? CGFloat(min(max(level, 0), 1)) : 0 }
    private var allowsMotion: Bool { !reduceMotion && animation != .minimal && scenePhase == .active }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Self.weights.indices, id: \.self) { index in
                Capsule()
                    .fill(color.opacity(contrast == .increased ? 1 : 0.82))
                    .frame(width: 2, height: 2 + (allowsMotion ? energy : 0) * Self.weights[index] * 10)
            }
        }
        .frame(height: 14)
        .animation(allowsMotion ? .easeOut(duration: SuzzmeTheme.Motion.quick) : nil, value: energy)
        .accessibilityHidden(true)
    }
}

/// Word progress supplied by Apple's speech delegate. It conveys completion,
/// not invented loudness, and needs no clock or rendering loop.
private struct SuzzmeSpeechProgressField: View {
    let progress: Double
    let color: Color
    let animation: SuzzmePresenceAnimation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    private var fraction: CGFloat { progress.isFinite ? CGFloat(min(max(progress, 0), 1)) : 0 }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(contrast == .increased ? 0.35 : 0.18))
                Capsule().fill(color).frame(width: geometry.size.width * fraction)
            }
            .frame(height: 3)
            .frame(maxHeight: .infinity)
        }
        .frame(width: 60, height: 14)
        .animation(reduceMotion || animation == .minimal || scenePhase != .active ? nil : .easeOut(duration: SuzzmeTheme.Motion.quick), value: fraction)
        .accessibilityHidden(true)
    }
}

/// Editorial hierarchy for the original answer; no content is generated here.
struct SuzzmeAnswerCard: View {
    let text: String
    var systemSurface = false
    private var parts: (lead: String, detail: String?) {
        let boundary = text.range(of: "\n\n") ?? text.range(of: "(?<=[.!?])\\s+", options: .regularExpression)
        guard let boundary else { return (text, nil) }
        return (String(text[..<boundary.lowerBound]), String(text[boundary.upperBound...]))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
            Text(parts.lead).font(.headline)
                .foregroundStyle(systemSurface ? Color.white : SuzzmeTheme.textPrimary)
            if let detail = parts.detail, !detail.isEmpty {
                Text(detail).font(.body)
                    .foregroundStyle(systemSurface ? Color.white.opacity(0.88) : SuzzmeTheme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

struct SuzzmeAssistantPresenceOverlay: View {
    let state: SuzzmeAssistantState
    var theme: SuzzmePresenceTheme = .suzzmePurple
    var animation: SuzzmePresenceAnimation = .gentle
    var proactiveSignal: SuzzmeProactivePresenceSignal = .none
    var audioLevel: Double = 0
    var speechProgress: Double = 0
    var onCancel: (() -> Void)?
    var onInvoke: (() -> Void)?
    var onDismiss: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var suppressedState: SuzzmeAssistantState?
    private var presentation: SuzzmeAssistantPresentation { .make(for: state) }

    var body: some View {
        if (presentation.isVisible || proactiveSignal != .none), suppressedState != state {
            SuzzmeAssistantPresenceView(state: state, theme: theme, animation: animation, proactiveSignal: proactiveSignal, audioLevel: audioLevel, speechProgress: speechProgress, onCancel: onCancel, onInvoke: onInvoke)
                .frame(maxWidth: 420)
                .padding(.horizontal, 20)
                .padding(.top, SuzzmeTheme.Spacing.xs)
                .transition(.opacity)
                .animation(reduceMotion || animation.duration == 0 ? nil : .easeInOut(duration: SuzzmeTheme.Motion.standard), value: state)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.7).onEnded { _ in
                        suppressedState = state
                        onDismiss?()
                    }
                )
                .accessibilityIdentifier("suzzme-assistant-presence")
                .accessibilityHint("Press and hold to hide Suzzme")
                .accessibilityAction(named: "Hide Suzzme") {
                    suppressedState = state
                    onDismiss?()
                }
        }
        EmptyView()
            .onChange(of: state) { oldValue, newValue in
                guard oldValue != newValue else { return }
                suppressedState = nil
            }
    }
}

/// A bounded, state-driven edge accent shared by in-app and Mac Presence.
/// It follows the selected companion color and becomes static with Reduce Motion.
struct SuzzmePresenceEdgeTrace<S: Shape>: View {
    let shape: S
    let primary: Color
    let secondary: Color
    let highlight: Color
    let state: SuzzmeAssistantState
    let isActive: Bool
    let animation: SuzzmePresenceAnimation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase: CGFloat = 0
    private var motion: SuzzmePresenceMotion { .make(for: state) }

    var body: some View {
        shape
            .stroke(
                LinearGradient(
                    colors: [primary.opacity(0.24), highlight.opacity(0.72 + Double(phase) * 0.2), secondary.opacity(0.64)],
                    startPoint: UnitPoint(x: 0.1 + phase * motion.travel, y: 0),
                    endPoint: UnitPoint(x: 0.9 - phase * motion.travel, y: 1)
                ),
                lineWidth: contrast == .increased ? 2 : isActive ? 1.25 : 0.75
            )
            .shadow(color: reduceTransparency ? .clear : primary.opacity(isActive ? 0.12 : 0.04), radius: isActive ? 3 : 1)
            .opacity(isActive ? 1 : 0.55)
            .allowsHitTesting(false)
            .task(id: "\(state.rawValue)-\(isActive)-\(animation.rawValue)-\(reduceMotion)-\(scenePhase == .active)") {
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { phase = 0 }
                guard isActive, SuzzmePresenceMotion.allowsMotion(state: state, animation: animation,
                                                                  reduceMotion: reduceMotion, isActive: scenePhase == .active) else { return }
                let duration = motion.entryDuration(for: animation)
                withAnimation(.smooth(duration: duration)) { phase = 1 }
                do { try await Task.sleep(for: .seconds(duration)) }
                catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: SuzzmeTheme.Motion.calm)) { phase = 0 }
            }
            .accessibilityHidden(true)
    }
}
