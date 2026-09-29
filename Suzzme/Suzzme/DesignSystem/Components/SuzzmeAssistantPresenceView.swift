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
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            ZStack {
                Circle().fill(signalColor.opacity(reduceTransparency ? 0.18 : increasedContrast ? 0.42 : 0.28))
                SuzzmeFace(state: state, color: signalColor, lineWidth: 3.5, animation: animation).padding(10)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle).font(.subheadline.weight(.semibold)).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(displayStatus).font(.caption).foregroundStyle(.secondary).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(displayStatus)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsCancel, isCancellable {
                Button("Cancel", action: { onCancel?() })
                    .buttonStyle(.bordered).controlSize(.small)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("Cancel Suzzme")
                    .accessibilityHint("Stops listening and cancels the current request")
            }
        }
        .padding(12)
        .background { backgroundStyle.clipShape(RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.card, style: .continuous)) }
        .overlay {
            let shape = RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.card, style: .continuous)
            shape
                .strokeBorder(signalColor.opacity(reduceTransparency ? 0.55 : increasedContrast ? 0.72 : 0.20), lineWidth: increasedContrast ? 1.75 : 1)
            SuzzmePresenceEdgeTrace(
                shape: shape,
                primary: signalColor,
                secondary: theme.colors(for: colorScheme).secondary,
                highlight: theme.colors(for: colorScheme).highlight,
                isActive: presentation.emphasis != .ambient,
                animation: animation
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(displayStatus)
        .contentShape(Rectangle())
    }

    private var systemPresenceContent: some View {
        let compact = state == .idle && proactiveSignal == .none
        let colors = theme.colors(for: .dark)
        return HStack(spacing: compact ? 9 : 12) {
            ZStack {
                if !compact {
                    Circle().fill(colors.primary.opacity(reduceTransparency ? 0.25 : 0.16))
                }
                SuzzmeFace(
                    state: state,
                    color: colors.face,
                    lineWidth: compact ? 3 : 3.5,
                    animation: animation
                )
                .padding(compact ? 1 : 8)
            }
            .frame(width: compact ? 24 : 40, height: compact ? 24 : 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !compact {
                    Text(displayStatus)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 4)

            if showsCancel, isCancellable {
                Button(action: { onCancel?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.76))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(reduceTransparency ? 0.16 : 0.10), in: Circle())
                        .overlay { Circle().stroke(.white.opacity(0.18), lineWidth: 0.75) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel Suzzme")
                .accessibilityHint("Stops the current request")
            } else if state == .success {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, compact ? 14 : 16)
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
    private var displayTitle: String { state == .idle && proactiveSignal != .none ? proactiveSignal.title : presentation.title }
    private var displayStatus: String { state == .idle && proactiveSignal != .none ? proactiveSignal.status : presentation.systemStatus }

    private var signalColor: Color {
        switch presentation.emphasis {
        case .error: .red
        case .success: .green
        case .ambient, .active, .confirmation: theme.colors(for: colorScheme).highlight
        }
    }

    @ViewBuilder private var backgroundStyle: some View {
        if reduceTransparency { SuzzmeTheme.surface }
        else { Rectangle().fill(.regularMaterial) }
    }
}

struct SuzzmeAssistantPresenceOverlay: View {
    let state: SuzzmeAssistantState
    var theme: SuzzmePresenceTheme = .suzzmePurple
    var animation: SuzzmePresenceAnimation = .gentle
    var proactiveSignal: SuzzmeProactivePresenceSignal = .none
    var onCancel: (() -> Void)?
    var onInvoke: (() -> Void)?
    var onDismiss: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var suppressedState: SuzzmeAssistantState?
    private var presentation: SuzzmeAssistantPresentation { .make(for: state) }

    var body: some View {
        if (presentation.isVisible || proactiveSignal != .none), suppressedState != state {
            SuzzmeAssistantPresenceView(state: state, theme: theme, animation: animation, proactiveSignal: proactiveSignal, onCancel: onCancel, onInvoke: onInvoke)
                .frame(maxWidth: 420)
                .padding(.horizontal, 20)
                .padding(.top, SuzzmeTheme.Spacing.xs)
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: SuzzmeTheme.Motion.standard), value: state)
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
/// It follows the selected Presence theme and becomes static with Reduce Motion.
struct SuzzmePresenceEdgeTrace<S: Shape>: View {
    let shape: S
    let primary: Color
    let secondary: Color
    let highlight: Color
    let isActive: Bool
    let animation: SuzzmePresenceAnimation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = 0.0

    var body: some View {
        shape
            .stroke(
                AngularGradient(
                    colors: [.clear, .clear, primary.opacity(0.35), highlight, secondary, .clear, .clear],
                    center: .center,
                    startAngle: .degrees(phase),
                    endAngle: .degrees(phase + 360)
                ),
                lineWidth: contrast == .increased ? 2 : isActive ? 1.5 : 0.75
            )
            .shadow(color: reduceTransparency ? .clear : primary.opacity(isActive ? 0.22 : 0.06), radius: isActive ? 5 : 2)
            .opacity(isActive ? 1 : 0.55)
            .allowsHitTesting(false)
            .task(id: "\(isActive)-\(animation.rawValue)-\(reduceMotion)-\(scenePhase == .active)") {
                phase = 0
                guard isActive, animation.duration > 0, !reduceMotion, scenePhase == .active else { return }
                withAnimation(.linear(duration: max(2.4, animation.duration * 1.7)).repeatForever(autoreverses: false)) {
                    phase = 360
                }
            }
            .accessibilityHidden(true)
    }
}
