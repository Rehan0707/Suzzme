#if os(macOS)
import AppKit
import SwiftUI

private final class MacGuidancePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A brief visual reference only. It cannot receive clicks or activate another app.
@MainActor
final class MacGuidanceOverlay {
    /// Image-free evidence admitted by this owner, never raw model coordinates.
    struct Presentation: Equatable {
        let reference: SpatialReference
        let context: ScreenContextMetadata
        let target: CGPoint
        let visibleFrame: CGRect
    }

    enum EndReason { case completed, invalidated }

    private(set) var presentation: Presentation?
    private var returningPresentation: Presentation?
    var onDismiss: ((Presentation, EndReason) -> Void)?
    private var panel: NSPanel?
    private var autoHideTask: Task<Void, Never>?
    private var lifetimeToken = UUID()
    private var companionPresent = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var displayObserver: NSObjectProtocol?
    private var shownReference: SpatialReference?
    private var shownContext: ScreenContextMetadata?
    private var retiredReference: SpatialReference?
    private var retiredContext: ScreenContextMetadata?

    @discardableResult
    func show(reference: SpatialReference, context: ScreenContextMetadata, currentRequestID: UUID) -> Bool {
        guard let screen = matchingScreen(reference: reference, context: context, requestID: currentRequestID)
        else { dismiss(); return false }
        guard retiredReference != reference || retiredContext != context else { return false }
        if shownReference == reference && shownContext == context && panel?.isVisible == true {
            guard let presentation, isCurrent(presentation) else { dismiss(); return false }
            return true
        }
        dismiss()

        // Normalized image coordinates have a top-left origin; NSScreen frames
        // have a global bottom-left origin, including negative secondary origins.
        let target = CGPoint(x: context.display.x + reference.normalizedX * context.display.width,
                             y: context.display.y + (1 - reference.normalizedY) * context.display.height)
        let visible = screen.frame
        let size = CGSize(width: min(260, visible.width), height: min(100, visible.height))
        let frame = CGRect(
            x: max(visible.minX, min(target.x - size.width / 2, visible.maxX - size.width)),
            y: max(visible.minY, min(target.y - size.height / 2, visible.maxY - size.height)),
            width: size.width, height: size.height
        )
        let overlayPanel = MacGuidancePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        overlayPanel.level = .floating
        overlayPanel.isOpaque = false
        overlayPanel.backgroundColor = .clear
        overlayPanel.hasShadow = false
        overlayPanel.ignoresMouseEvents = true
        overlayPanel.hidesOnDeactivate = false
        overlayPanel.isExcludedFromWindowsMenu = true
        overlayPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel = overlayPanel
        shownReference = reference
        shownContext = context
        let admitted = Presentation(reference: reference, context: context, target: target, visibleFrame: screen.visibleFrame)
        presentation = admitted
        updateMarker()
        installDismissalObservers()
        overlayPanel.orderFrontRegardless()
        let token = lifetimeToken
        let remainingAge = ScreenContext.maximumAgeSeconds - Date.now.timeIntervalSince(context.capturedAt)
        let lifetime = max(0, min(4, remainingAge))
        autoHideTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(lifetime)) }
            catch { return }
            guard let self, self.lifetimeToken == token, self.presentation == admitted else { return }
            self.dismiss(reason: self.isCurrent(admitted) ? .completed : .invalidated)
        }
        return true
    }

    func isCurrent(_ candidate: Presentation) -> Bool {
        guard presentation == candidate,
              let screen = matchingScreen(reference: candidate.reference, context: candidate.context,
                                          requestID: candidate.reference.requestID) else { return false }
        return screen.visibleFrame == candidate.visibleFrame
    }

    func isReturnCurrent(_ candidate: Presentation) -> Bool {
        guard returningPresentation == candidate,
              let screen = matchingScreen(reference: candidate.reference, context: candidate.context,
                                          requestID: candidate.reference.requestID) else { return false }
        return screen.visibleFrame == candidate.visibleFrame
    }

    func finishReturn(_ candidate: Presentation) {
        guard returningPresentation == candidate else { return }
        returningPresentation = nil
        lifetimeToken = UUID()
        autoHideTask?.cancel()
        autoHideTask = nil
        removeDismissalObservers()
    }

    /// The cursor companion supplies the full Face while parked beside the ring.
    func setCompanionPresent(_ present: Bool) {
        guard companionPresent != present else { return }
        companionPresent = present
        updateMarker()
    }

    func dismiss(reason: EndReason = .invalidated) {
        let ended = presentation ?? returningPresentation
        let keepsReturnOwnership = reason == .completed && companionPresent && onDismiss != nil
        lifetimeToken = UUID()
        if let shownReference, let shownContext {
            retiredReference = shownReference
            retiredContext = shownContext
        }
        autoHideTask?.cancel()
        autoHideTask = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
        shownReference = nil
        shownContext = nil
        presentation = nil
        returningPresentation = keepsReturnOwnership ? ended : nil
        companionPresent = false
        if !keepsReturnOwnership { removeDismissalObservers() }
        if keepsReturnOwnership, let ended {
            // A near-expired capture must not gain extra life during the return.
            let token = lifetimeToken
            let remaining = max(0, ScreenContext.maximumAgeSeconds - Date.now.timeIntervalSince(ended.context.capturedAt))
            autoHideTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(remaining)) }
                catch { return }
                guard let self, self.lifetimeToken == token, self.returningPresentation == ended else { return }
                self.dismiss()
            }
        }
        if let ended { onDismiss?(ended, reason) }
    }

    private func matchingScreen(reference: SpatialReference, context: ScreenContextMetadata, requestID: UUID) -> NSScreen? {
        guard reference.isValid(for: context, requestID: requestID),
              let processID = context.activeApplicationPID,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == processID,
              MacScreenContextSource.matchesWindow(context) else { return nil }
        return NSScreen.screens.first { MacScreenContextSource.geometry(for: $0) == context.display }
    }

    private func updateMarker() {
        guard let panel, let presentation else { return }
        panel.contentView = NSHostingView(rootView: MacGuidanceMarker(
            label: presentation.reference.label.trimmingCharacters(in: .whitespacesAndNewlines),
            target: CGPoint(x: presentation.target.x - panel.frame.minX, y: panel.frame.maxY - presentation.target.y),
            showsFace: !companionPresent
        ))
    }

    isolated deinit {
        autoHideTask?.cancel()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        panel?.contentView = nil
        panel?.close()
    }

    private func installDismissalObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let reference = shownReference
        let context = shownContext
        for notification in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification,
                             NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(workspaceCenter.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let current = self.presentation ?? self.returningPresentation,
                          current.reference == reference, current.context == context else { return }
                    self.dismiss()
                }
            })
        }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let current = self.presentation ?? self.returningPresentation,
                      current.reference == reference, current.context == context else { return }
                self.dismiss()
            }
        }
    }

    private func removeDismissalObservers() {
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
    }
}

private struct MacGuidanceMarker: View {
    let label: String
    let target: CGPoint
    var showsFace = true
    @AppStorage(InvocationCoordinator.presenceThemeKey) private var storedTheme = SuzzmePresenceTheme.suzzmePurple.rawValue
    @AppStorage(InvocationCoordinator.presenceAnimationKey) private var storedAnimation = SuzzmePresenceAnimation.gentle.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @State private var arrived = false
    @State private var pulseProgress: CGFloat = 0

    private var theme: SuzzmePresenceTheme {
        SuzzmePresenceTheme(rawValue: storedTheme) ?? .suzzmePurple
    }

    private var allowsMotion: Bool {
        !reduceMotion && scenePhase == .active && (SuzzmePresenceAnimation(rawValue: storedAnimation) ?? .gentle) != .minimal
    }

    var body: some View {
        let colors = SuzzmePresenceColors.mascot(for: colorScheme)
        let focusColor = colorScheme == .dark ? colors.highlight : colors.primary
        GeometryReader { geometry in
            ZStack {
                ZStack {
                    if allowsMotion && !reduceTransparency && contrast != .increased {
                        Circle()
                            .stroke(colors.glow.opacity(0.48), lineWidth: SuzzmeTheme.hairline * 2)
                            .scaleEffect(1 + pulseProgress / 2)
                            .opacity(1 - pulseProgress)
                    }
                    // Two edges keep the target legible over both light and dark content.
                    Circle()
                        .stroke(SuzzmeTheme.backgroundPrimary.opacity(0.94), lineWidth: contrast == .increased ? 6 : 5)
                    Circle()
                        .stroke(
                            LinearGradient(colors: [focusColor, colors.secondary, focusColor],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: contrast == .increased ? 4 : 3
                        )
                }
                    .frame(width: SuzzmeTheme.Spacing.extraLarge, height: SuzzmeTheme.Spacing.extraLarge)
                    .scaleEffect(allowsMotion && !arrived ? 0.82 : 1)
                    .position(target)
                    .accessibilityHidden(true)

                HStack(spacing: SuzzmeTheme.Spacing.xs) {
                    if showsFace {
                        SuzzmeFace(color: focusColor, lineWidth: SuzzmeTheme.hairline * 1.5, animation: .minimal)
                            .frame(width: SuzzmeTheme.Spacing.medium, height: SuzzmeTheme.Spacing.medium)
                    }
                    Text(label)
                        .font(.system(.caption, design: .default).weight(.medium))
                        .foregroundStyle(SuzzmeTheme.textPrimary)
                        .lineLimit(1)
                }
                    .padding(.horizontal, SuzzmeTheme.Spacing.small)
                    .padding(.vertical, SuzzmeTheme.Spacing.xs)
                    .suzzmeGlassControlSurface(cornerRadius: SuzzmeTheme.Radius.largeSurface,
                                               tint: focusColor.opacity(0.1))
                    .overlay(Capsule().stroke(focusColor.opacity(contrast == .increased ? 1 : 0.42), lineWidth: SuzzmeTheme.hairline))
                    .offset(y: allowsMotion && !arrived ? SuzzmeTheme.Spacing.xs : 0)
                    .frame(maxWidth: max(1, geometry.size.width - SuzzmeTheme.Spacing.medium),
                           alignment: labelAlignment(in: geometry.size.width))
                    .position(x: geometry.size.width / 2,
                              y: target.y > geometry.size.height / 2 ? max(18, target.y - 34) : min(geometry.size.height - 18, target.y + 34))
            }
            .opacity(allowsMotion && !arrived ? 0 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Suzzme is pointing to \(label)")
        .accessibilityValue("Visual guidance")
        .allowsHitTesting(false)
        .task(id: allowsMotion) {
            var immediate = Transaction()
            immediate.disablesAnimations = true
            withTransaction(immediate) {
                arrived = !allowsMotion
                pulseProgress = 0
            }
            guard allowsMotion else { return }
            withAnimation(.spring(response: SuzzmeTheme.Motion.standard,
                                  dampingFraction: SuzzmeTheme.Motion.presenceDamping)) {
                arrived = true
            }
            do { try await Task.sleep(for: .seconds(SuzzmeTheme.Motion.standard)) }
            catch { return }
            guard !Task.isCancelled else { return }
            // One arrival pulse resolves to a still ring; the existing owner dismisses it.
            withAnimation(.easeOut(duration: SuzzmeTheme.Motion.calm)) {
                pulseProgress = 1
            }
        }
    }

    private func labelAlignment(in width: CGFloat) -> Alignment {
        if target.x < width / 3 { return .leading }
        if target.x > width * 2 / 3 { return .trailing }
        return .center
    }
}
#endif
