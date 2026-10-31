#if os(macOS)
import AppKit
import CoreGraphics
import Observation
import SwiftUI

/// A system-adjacent surface must respond to the first click even when the
/// main Suzzme window is inactive. The panel remains app-owned and uses only
/// public AppKit behavior.
private final class MacAssistantHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // Only a deliberate click gives this nonactivating surface keyboard focus.
    // Confirmation and Escape remain usable with Input Monitoring disabled.
    override var needsPanelToBecomeKey: Bool { true }
}

enum MacGitHubConnectionDecision: Sendable { case decline, later, connect }

struct MacGitHubConnectionRequest: Equatable, Sendable {
    let repository: String
    var id = UUID()
    var alreadyAllowed = false
}

private final class MacAssistantPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor
final class MacAssistantPanelController {
    private let observesPointer: Bool
    private var panel: MacAssistantPanel?
    private var autoHideTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var mouseMonitors: [Any] = []
    private var notchEntryRect: NSRect = .null
    private var pointerWasInNotch = false
    private struct PresentationIdentity: Equatable {
        let state: SuzzmeAssistantState
        let theme: SuzzmePresenceTheme
        let animation: SuzzmePresenceAnimation
        let signal: SuzzmeProactivePresenceSignal
        let hasNotch: Bool
        let notchWidth: CGFloat
        let notchHeight: CGFloat
        let review: SuzzmePresenceReview?
        let connectionRequest: MacGitHubConnectionRequest?
        let response: String?
        let contextLabels: [String]
        let interactionID: UUID?
    }
    private var renderedIdentity: PresentationIdentity?
    private var suppressedIdentity: PresentationIdentity?
    private var currentState: SuzzmeAssistantState = .idle
    private var currentTheme: SuzzmePresenceTheme = .suzzmePurple
    private var currentAnimation: SuzzmePresenceAnimation = .gentle
    private var currentSignal: SuzzmeProactivePresenceSignal = .none
    private var currentCancel: (() -> Void)?
    private var currentInvoke: (() -> Void)?
    private var currentResponse: String?
    private var currentContextLabels: [String] = []
    private var currentAudioLevel: Double = 0
    private var renderedAudioLevel: Double = 0
    private var currentSpeechProgress: Double = 0
    private var renderedSpeechProgress: Double = 0
    private var currentInteractionID: UUID?
    private var displayOwnership = MacPresenceDisplayOwnership()
    private var currentReview: SuzzmePresenceReview?
    private var currentConnectionRequest: MacGitHubConnectionRequest?
    private var currentConnectionDecision: ((MacGitHubConnectionDecision) -> Void)?
    private var currentConfirmation: ((Bool) -> Void)?

    init(observesPointer: Bool = true) {
        self.observesPointer = observesPointer
    }

    func update(state: SuzzmeAssistantState, theme: SuzzmePresenceTheme, animation: SuzzmePresenceAnimation, signal: SuzzmeProactivePresenceSignal = .none, review: SuzzmePresenceReview? = nil, connectionRequest: MacGitHubConnectionRequest? = nil, response: String? = nil, audioLevel: Double = 0, speechProgress: Double = 0, interactionID: UUID? = nil, contextLabels: [String] = [], onConfirmation: ((Bool) -> Void)? = nil, onConnectionDecision: ((MacGitHubConnectionDecision) -> Void)? = nil, onCancel: @escaping () -> Void, onInvoke: @escaping () -> Void) {
        // Completion can return the core to idle before the UI reading deadline.
        // Keep only the current environment-owned answer through that deadline.
        currentResponse = [.idle, .understanding, .speaking, .success, .error].contains(state) ? response : nil
        currentAudioLevel = state == .listening && audioLevel.isFinite ? min(max(audioLevel, 0), 1) : 0
        currentSpeechProgress = state == .speaking && speechProgress.isFinite ? min(max(speechProgress, 0), 1) : 0
        currentInteractionID = interactionID
        currentContextLabels = Array(contextLabels.prefix(2)).map { String($0.prefix(40)) }
        currentState = state
        currentTheme = theme
        currentAnimation = animation
        currentSignal = signal
        currentCancel = onCancel
        currentInvoke = onInvoke
        currentReview = state == .awaitingConfirmation ? review : nil
        currentConnectionRequest = connectionRequest
        currentConnectionDecision = connectionRequest == nil ? nil : onConnectionDecision
        currentConfirmation = onConfirmation
        refreshPresentation()
    }

    func dismiss() {
        collapseTask?.cancel()
        collapseTask = nil
        removeMouseMonitors()
        autoHideTask?.cancel()
        autoHideTask = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.onEscape = nil
        renderedIdentity = nil
        suppressedIdentity = nil
        currentCancel = nil
        currentInvoke = nil
        currentReview = nil
        currentConnectionRequest = nil
        currentConnectionDecision = nil
        currentResponse = nil
        currentConfirmation = nil
        displayOwnership.reset()
    }

    private func escapeCurrentPresentation() {
        // Cancel through the captured owner, never by manufacturing an action
        // or confirming whatever happens to be current after an actor hop.
        if currentConnectionRequest != nil {
            currentConnectionDecision?(.later)
        } else if currentReview != nil {
            currentConfirmation?(false)
        } else if [.idle, .success, .error].contains(currentState) {
            hideCurrentPresentation()
        } else {
            currentCancel?()
        }
    }

    /// Suppresses only the presentation the user pressed. A subsequent state,
    /// signal, response, or confirmation is allowed to become visible again.
    func hideCurrentPresentation() {
        if currentConnectionRequest != nil {
            currentConnectionDecision?(.later)
            return
        }
        autoHideTask?.cancel()
        autoHideTask = nil
        guard let renderedIdentity else { return }
        suppressedIdentity = renderedIdentity
        guard collapseTask == nil, let panel else { return }
        panel.ignoresMouseEvents = true
        guard panel.isVisible, currentAnimation != .minimal,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            return
        }
        let frame = panel.frame
        let collapsed = NSRect(x: frame.minX, y: frame.maxY - 1, width: frame.width, height: 1)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = SuzzmeTheme.Motion.presenceExpansion
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(collapsed, display: true)
            panel.animator().alphaValue = 0
        }
        collapseTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(SuzzmeTheme.Motion.presenceExpansion)) }
            catch { return }
            guard let self, self.suppressedIdentity == renderedIdentity else { return }
            self.panel?.orderOut(nil)
            self.collapseTask = nil
        }
    }

    isolated deinit {
        autoHideTask?.cancel()
        collapseTask?.cancel()
        for monitor in mouseMonitors { NSEvent.removeMonitor(monitor) }
        panel?.contentView = nil
        panel?.close()
    }

    /// Event-driven reveal: no idle polling, keyboard capture, or permission prompt.
    /// Re-entry is required after a hold-to-hide so the same pointer cannot undo it.
    func pointerMoved(to point: NSPoint) {
        updatePointerCapture(to: point)
        let isInside = MacPresencePointerRegion.contains(point, in: notchEntryRect)
        defer { pointerWasInNotch = isInside }
        guard isInside, !pointerWasInNotch,
              Self.autoHideDelay(for: currentState, signal: currentSignal) != nil,
              suppressedIdentity != nil else { return }
        suppressedIdentity = nil
        renderedIdentity = nil
        refreshPresentation()
    }

    private func installMouseMonitors() {
        guard observesPointer else { return }
        guard mouseMonitors.isEmpty else { return }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            Task { @MainActor [weak self] in self?.pointerMoved(to: NSEvent.mouseLocation) }
        }) { mouseMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved(to: NSEvent.mouseLocation) }
            return event
        }) { mouseMonitors.append(monitor) }
    }

    private func removeMouseMonitors() {
        for monitor in mouseMonitors { NSEvent.removeMonitor(monitor) }
        mouseMonitors.removeAll()
        notchEntryRect = .null
        pointerWasInNotch = false
    }

    private func refreshPresentation() {
        let presentation = SuzzmeAssistantPresentation.make(for: currentState)
        guard currentCancel != nil, currentInvoke != nil else {
            dismiss()
            return
        }
        let screens = NSScreen.screens
        let notchScreen = screens.first(where: Self.hasNotch)
        // The built-in notch remains an invocation affordance when an external
        // monitor is primary. Its entry listener is independent of an answer's
        // owned display, which must remain stable throughout the interaction.
        notchEntryRect = notchScreen.map(Self.notchEntryRect(for:)) ?? .null
        let hasInteraction = currentState != .idle || currentResponse != nil || currentReview != nil || currentConnectionRequest != nil || currentSignal != .none
        let preferredNotch = hasInteraction ? nil : notchScreen
        guard let preferred = preferredNotch ?? screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main ?? screens.first else { return }
        let displayID = displayOwnership.resolve(
            interactionID: currentInteractionID,
            retainsInteraction: currentState != .idle || currentResponse != nil || currentReview != nil || currentConnectionRequest != nil,
            preferredID: Self.displayID(for: preferred),
            availableIDs: Set(screens.map(Self.displayID(for:)))
        )
        let screen = screens.first(where: { Self.displayID(for: $0) == displayID }) ?? preferred
        let hasNotch = Self.hasNotch(screen)
        // A physical notch is Suzzme's persistent invocation affordance. The
        // top-center fallback appears only while there is real assistant or
        // proactive activity, avoiding a permanent floating control on Macs
        // without a notch.
        guard hasNotch || presentation.isVisible || currentSignal != .none || currentResponse != nil || currentConnectionRequest != nil else {
            dismiss()
            return
        }
        let notchWidth: CGFloat
        if hasNotch, let right = screen.auxiliaryTopRightArea, let left = screen.auxiliaryTopLeftArea {
            notchWidth = max(0, right.minX - left.maxX)
        } else {
            notchWidth = 0
        }
        // Mouse movement is event-driven, including on non-notched displays.
        // Never install a cursor polling loop or another keyboard monitor.
        installMouseMonitors()
        let notchHeight = hasNotch ? screen.safeAreaInsets.top : 0
        let size = MacAssistantSurfaceMetrics.size(
            state: currentState,
            signal: currentSignal,
            notchWidth: notchWidth,
            review: currentReview,
            response: currentResponse,
            connectionRequest: currentConnectionRequest,
            notchHeight: notchHeight,
            contextLabels: currentContextLabels
        )
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.onEscape = { [weak self] in self?.escapeCurrentPresentation() }
        panel.setAccessibilityLabel("Suzzme. \(presentation.title)")
        panel.level = hasNotch ? .statusBar : .floating
        let identity = PresentationIdentity(state: currentState, theme: currentTheme, animation: currentAnimation, signal: currentSignal, hasNotch: hasNotch, notchWidth: notchWidth, notchHeight: notchHeight, review: currentReview, connectionRequest: currentConnectionRequest, response: currentResponse, contextLabels: currentContextLabels, interactionID: currentInteractionID)
        let retainsDismissedAnswer = currentState == .idle && currentResponse != nil
            && suppressedIdentity?.response == currentResponse
            && suppressedIdentity?.signal == currentSignal
            && (currentInteractionID == nil || suppressedIdentity?.interactionID == currentInteractionID)
        if suppressedIdentity == identity || retainsDismissedAnswer {
            // Returning to idle is the end of the same interaction, not new
            // activity. Never resurrect an answer the user already dismissed.
            if collapseTask == nil { panel.orderOut(nil) }
            return
        }
        collapseTask?.cancel()
        collapseTask = nil
        panel.alphaValue = 1
        suppressedIdentity = nil
        let identityChanged = renderedIdentity != identity
        if identityChanged || renderedAudioLevel != currentAudioLevel || renderedSpeechProgress != currentSpeechProgress {
            if identityChanged {
                autoHideTask?.cancel()
                autoHideTask = nil
            }
            let surface = MacAssistantNotchSurface(
                state: currentState, theme: currentTheme, animation: currentAnimation,
                signal: currentSignal, hasNotch: hasNotch, notchWidth: notchWidth, notchHeight: notchHeight, review: currentReview, connectionRequest: currentConnectionRequest, response: currentResponse, audioLevel: currentAudioLevel, speechProgress: currentSpeechProgress, contextLabels: currentContextLabels,
                onConfirmation: currentConfirmation,
                onConnectionDecision: currentConnectionDecision,
                onCancel: { [weak self] in self?.currentCancel?() },
                onInvoke: { [weak self] in self?.currentInvoke?() },
                onDismiss: { [weak self] in self?.hideCurrentPresentation() }
            )
            if let host = panel.contentView as? MacAssistantHostingView<MacAssistantNotchSurface> {
                host.rootView = surface
            } else {
                panel.contentView = MacAssistantHostingView(rootView: surface)
            }
            renderedIdentity = identity
            renderedAudioLevel = currentAudioLevel
            renderedSpeechProgress = currentSpeechProgress
            if identityChanged, currentConnectionRequest == nil,
               let delay = Self.autoHideDelay(for: currentState == .idle && currentResponse != nil ? .success : currentState, signal: currentSignal) {
                autoHideTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(delay)) }
                    catch { return }
                    guard let self, self.renderedIdentity == identity else { return }
                    self.hideCurrentPresentation()
                }
            }
        }
        let visible = screen.visibleFrame
        let frame = MacAssistantPanelPlacement.frame(
            size: size,
            screenFrame: screen.frame,
            visibleFrame: visible,
            hasNotch: hasNotch,
            notchCenterX: hasNotch ? Self.notchEntryRect(for: screen).midX : screen.frame.midX
        )
        if panel.frame != frame {
            let shouldAnimate = currentAnimation != .minimal && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if !panel.isVisible {
                panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - 1, width: frame.width, height: 1), display: false)
            }
            if shouldAnimate {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = SuzzmeTheme.Motion.presenceExpansion
                    context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
                    panel.animator().setFrame(frame, display: true)
                } completionHandler: { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, self.renderedIdentity == identity,
                              self.suppressedIdentity == nil, self.collapseTask == nil else { return }
                        // A stationary pointer must be clickable after growth;
                        // the initial check may have sampled the collapsed frame.
                        self.updatePointerCapture(to: NSEvent.mouseLocation)
                    }
                }
            } else { panel.setFrame(frame, display: true) }
        }
        // Public window behavior can be reset when macOS reorders a panel.
        panel.collectionBehavior = Self.collectionBehavior
        panel.orderFrontRegardless()
        updatePointerCapture(to: NSEvent.mouseLocation)
    }

    private func updatePointerCapture(to point: NSPoint) {
        guard let panel else { return }
        guard panel.isVisible, collapseTask == nil, let identity = renderedIdentity else {
            panel.ignoresMouseEvents = true
            return
        }
        let radii = MacAssistantSurfaceMetrics.cornerRadii(state: identity.state, signal: identity.signal,
                                                         hasDetail: identity.review != nil || identity.connectionRequest != nil || identity.response != nil)
        let shape = SuzzmeNotchSurfaceShape(attached: identity.hasNotch, neckWidth: identity.notchWidth,
                                           topCornerRadius: radii.top, bottomCornerRadius: radii.bottom)
        panel.ignoresMouseEvents = !MacPresencePointerRegion.contains(point, in: panel.frame, shape: shape)
    }

    private static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0 && screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
    }

    private static func notchEntryRect(for screen: NSScreen) -> NSRect {
        guard hasNotch(screen), let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return .null }
        return NSRect(x: left.maxX, y: screen.frame.maxY - screen.safeAreaInsets.top,
                      width: max(0, right.minX - left.maxX), height: screen.safeAreaInsets.top)
    }

    private static let collectionBehavior: NSWindow.CollectionBehavior =
        [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

    static func autoHideDelay(for state: SuzzmeAssistantState, signal: SuzzmeProactivePresenceSignal) -> Double? {
        switch state {
        case .idle: signal == .none ? 3 : 8
        case .success: 5
        case .error: 8
        default: nil
        }
    }

    private static func displayID(for screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private func makePanel() -> MacAssistantPanel {
        let panel = MacAssistantPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The SwiftUI shape owns its shadow. An NSPanel shadow follows the
        // rectangular window frame and makes the surface look detached.
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = Self.collectionBehavior
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        return panel
    }
}

/// Shared geometry for bezel entry and native window click-through.
enum MacPresencePointerRegion {
    /// NSRect.contains excludes the maximum edge. A cursor at the physical
    /// bezel reports exactly maxY, which must remain an accessible target.
    static func contains(_ point: NSPoint, in rect: NSRect) -> Bool {
        guard !rect.isNull, !rect.isInfinite, rect.size.width > 0, rect.size.height > 0,
              rect.origin.x.isFinite, rect.origin.y.isFinite, rect.size.width.isFinite, rect.size.height.isFinite,
              point.x.isFinite, point.y.isFinite else { return false }
        return point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    /// Test the shared visual silhouette in top-origin SwiftUI coordinates.
    /// Transparent corners and the edge bloom belong to the app underneath.
    static func contains(_ point: NSPoint, in frame: NSRect, shape: SuzzmeNotchSurfaceShape) -> Bool {
        guard contains(point, in: frame) else { return false }
        let local = CGPoint(x: point.x - frame.minX,
                            y: min(max(frame.maxY - point.y, 0.5), max(0.5, frame.height - 0.5)))
        return shape.path(in: CGRect(origin: .zero, size: frame.size)).contains(local)
    }
}

/// Pins one interaction to its display. Cursor movement and audio updates are
/// presentation inputs, never reasons to migrate an ongoing answer or review.
struct MacPresenceDisplayOwnership {
    private(set) var displayID: UInt32?
    private var ownerID: UUID?

    mutating func resolve(interactionID: UUID?, retainsInteraction: Bool,
                          preferredID: UInt32, availableIDs: Set<UInt32>) -> UInt32 {
        guard retainsInteraction else { reset(); return preferredID }
        if let displayID, availableIDs.contains(displayID),
           interactionID == nil || interactionID == ownerID {
            return displayID
        }
        ownerID = interactionID
        displayID = preferredID
        return preferredID
    }

    mutating func reset() { displayID = nil; ownerID = nil }
}

enum MacAssistantPanelPlacement {
    static func frame(
        size: CGSize,
        screenFrame: NSRect,
        visibleFrame: NSRect,
        hasNotch: Bool,
        notchCenterX: CGFloat
    ) -> NSRect {
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, hasNotch ? screenFrame.height : visibleFrame.height)
        let centerX = hasNotch ? notchCenterX : visibleFrame.midX
        let x = min(max(visibleFrame.minX, centerX - width / 2), visibleFrame.maxX - width)
        let topEdge = hasNotch ? screenFrame.maxY : visibleFrame.maxY - 8
        let minimumY = hasNotch ? screenFrame.minY : visibleFrame.minY
        let maximumY = hasNotch ? screenFrame.maxY : visibleFrame.maxY
        let y = min(max(minimumY, topEdge - height), maximumY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

struct MacAssistantNotchSurface: View {
    let state: SuzzmeAssistantState
    let theme: SuzzmePresenceTheme
    let animation: SuzzmePresenceAnimation
    let signal: SuzzmeProactivePresenceSignal
    let hasNotch: Bool
    var notchWidth: CGFloat = 180
    var notchHeight: CGFloat = 0
    var edgeGlow = SuzzmeTheme.Motion.presenceGlow
    var review: SuzzmePresenceReview?
    var connectionRequest: MacGitHubConnectionRequest?
    var response: String?
    var audioLevel: Double = 0
    var speechProgress: Double = 0
    var contextLabels: [String] = []
    var onConfirmation: ((Bool) -> Void)?
    var onConnectionDecision: ((MacGitHubConnectionDecision) -> Void)?
    let onCancel: () -> Void
    let onInvoke: () -> Void
    var onDismiss: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    private var presentation: SuzzmeAssistantPresentation { .make(for: state) }

    var body: some View {
        let colors = theme.colors(for: .dark)
        let radii = MacAssistantSurfaceMetrics.cornerRadii(state: state, signal: signal, hasDetail: review != nil || connectionRequest != nil || response != nil)
        let shape = SuzzmeNotchSurfaceShape(
            attached: hasNotch, neckWidth: notchWidth,
            topCornerRadius: radii.top, bottomCornerRadius: radii.bottom
        )
        // Keep one view identity as the phase changes so the same fill and rim
        // morph together. Active controls retain their own native gestures.
        return surface(colors: colors, shape: shape)
            // The native panel already gates the exact silhouette. Include its
            // bezel boundary here so SwiftUI does not discard an edge click.
            .contentShape(Rectangle().inset(by: -0.5))
            .gesture(
                LongPressGesture(minimumDuration: 0.7)
                    .onEnded { _ in onDismiss() }
                    .exclusively(before: TapGesture().onEnded { onInvoke() }),
                including: surfaceTapInvokes ? .all : .subviews
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.7).onEnded { _ in onDismiss() },
                including: surfaceTapInvokes ? .subviews : .all
            )
            .accessibilityAddTraits(surfaceTapInvokes ? .isButton : [])
            .accessibilityAction {
                if surfaceTapInvokes { onInvoke() }
            }
            .accessibilityAction(named: "Hide Suzzme", onDismiss)
            .contextMenu {
                Button("Hide Suzzme", action: onDismiss)
            }
            .accessibilityHint(surfaceTapInvokes
                ? "Click to talk to Suzzme. Press and hold to hide."
                : "Press and hold to hide Suzzme")
    }

    private func surface(colors: SuzzmePresenceColors, shape: SuzzmeNotchSurfaceShape) -> some View {
        VStack(spacing: 8) {
            SuzzmeAssistantPresenceView(
                state: state,
                theme: theme,
                animation: animation,
                proactiveSignal: signal,
                systemSurface: true,
                audioLevel: audioLevel,
                speechProgress: speechProgress,
                contextTitle: !contextLabels.isEmpty && [.understanding, .gatheringContext, .reasoning].contains(state) ? "Looking at this…" : nil,
                onCancel: onCancel
            )
            if !contextLabels.isEmpty {
                HStack(spacing: 6) { contextChips }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SuzzmeTheme.Spacing.medium)
            }
            if let response {
                ScrollView {
                    SuzzmeAnswerCard(text: response, systemSurface: true)
                }
                .scrollBounceBehavior(.basedOnSize)
                .padding(.horizontal, SuzzmeTheme.Spacing.medium)
                HStack(spacing: SuzzmeTheme.Spacing.small) {
                    ShareLink(item: response) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                    }
                    .help("Share this answer")
                    Spacer()
                    Button("Done", action: onDismiss)
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                        .keyboardShortcut(.cancelAction)
                        .help("Hide this answer")
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .padding(.horizontal, SuzzmeTheme.Spacing.medium)
                .padding(.bottom, SuzzmeTheme.Spacing.small)
            }
            if let review {
                ScrollView {
                    Text(review.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .scrollBounceBehavior(.basedOnSize)
                .padding(.horizontal, SuzzmeTheme.Spacing.medium)
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    Button("Cancel", role: .cancel) { onConfirmation?(false) }
                        .frame(minHeight: 44)
                        .keyboardShortcut(.cancelAction)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    Button(review.confirmationLabel, role: review.isDestructive ? .destructive : nil) { onConfirmation?(true) }
                        .frame(minHeight: 44)
                        .keyboardShortcut(.defaultAction)
                        .tint(review.isDestructive ? .red : .accentColor)
                        .foregroundStyle(review.isDestructive ? Color.red : Color.primary)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
            }
            if let connectionRequest {
                VStack(alignment: .leading, spacing: 8) {
                    Label("GitHub connection request", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.82))
                    Text(connectionRequest.alreadyAllowed ? "Repository already allowed" : "Connect GitHub to Suzzme?")
                        .font(.headline).foregroundStyle(.white)
                    Text(connectionRequest.alreadyAllowed
                         ? "\(connectionRequest.repository) is allowed by your recently verified GitHub connection. This request did not read repository content."
                         : "Detected \(connectionRequest.repository). Yes opens GitHub setup with this repository prefilled. Suzzme reads nothing until you choose access and verify it.")
                        .font(.caption).foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        if connectionRequest.alreadyAllowed {
                            Button { onConnectionDecision?(.later) } label: {
                                Text("Done").frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                            }
                                .accessibilityIdentifier("suzzme-github-request-already-allowed")
                                .keyboardShortcut(.defaultAction)
                        } else {
                        Button { onConnectionDecision?(.decline) } label: {
                            Text("No").frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                        }
                            .accessibilityIdentifier("suzzme-github-request-no")
                        Button { onConnectionDecision?(.later) } label: {
                            Text("Not now").frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                        }
                            .accessibilityIdentifier("suzzme-github-request-later")
                        Spacer(minLength: 0)
                        Button { onConnectionDecision?(.connect) } label: {
                            Text("Yes").frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                        }
                            .buttonStyle(.borderedProminent)
                            .tint(theme.colors(for: .dark).primary)
                            .accessibilityIdentifier("suzzme-github-request-yes")
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                .padding(.horizontal, SuzzmeTheme.Spacing.medium)
                .padding(.bottom, SuzzmeTheme.Spacing.small)
            }
        }
        .padding(.top, hasNotch ? notchHeight : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.black, in: shape)
        .clipShape(shape)
        .overlay {
            SuzzmeNotchEdgeTrace(
                shape: shape,
                glow: edgeGlow,
                primary: statusAccent ?? colors.primary,
                secondary: statusAccent ?? colors.secondary,
                highlight: statusAccent ?? colors.highlight,
                state: state,
                isActive: presentation.emphasis != .ambient,
                animation: animation
            )
        }
        .animation(surfaceTransition, value: state)
        .animation(surfaceTransition, value: review?.id)
        .animation(surfaceTransition, value: response != nil)
        .animation(surfaceTransition, value: signal)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.systemStatus)
    }

    private var contextChips: some View {
        ForEach(contextLabels, id: \.self) { label in
            Text(label)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .accessibilityLabel(label)
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, SuzzmeTheme.Spacing.xs)
                .padding(.vertical, SuzzmeTheme.Spacing.xxs)
                .background(.white.opacity(reduceTransparency ? 0.18 : 0.09), in: Capsule())
        }
    }

    private var surfaceTapInvokes: Bool {
        guard review == nil, connectionRequest == nil, response == nil else { return false }
        return switch state {
        case .idle, .success, .error: true
        default: false
        }
    }

    private var statusAccent: Color? {
        switch presentation.emphasis {
        case .success: SuzzmeTheme.success
        case .error: SuzzmeTheme.warning
        case .ambient, .active, .confirmation: nil
        }
    }

    private var surfaceTransition: Animation? {
        guard !reduceMotion, animation != .minimal, scenePhase == .active else { return nil }
        return .spring(duration: SuzzmeTheme.Motion.presenceExpansion, bounce: animation == .pulse ? 0.12 : 0.04)
    }
}

/// The entire silhouette attaches to the display's top edge. The measured
/// cutout controls minimum width; its height is a content inset, never a gap
/// in the black surface. The fill and glow share one path.
struct SuzzmeNotchSurfaceShape: Shape {
    var attached: Bool
    var neckWidth: CGFloat
    var topCornerRadius: CGFloat = 8
    var bottomCornerRadius: CGFloat = 18

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        guard isValid(rect) else { return Path() }
        guard attached else { return RoundedRectangle(cornerRadius: 24, style: .continuous).path(in: rect) }
        var path = skirtPath(in: rect)
        path.closeSubpath()
        return path
    }

    /// Open skirt: concave top corners, sides and rounded bottom. Its endpoints
    /// touch the display edge; the flat bezel line remains deliberately dark.
    func skirtPath(in rect: CGRect) -> Path {
        guard isValid(rect) else { return Path() }
        guard attached else { return RoundedRectangle(cornerRadius: 24, style: .continuous).path(in: rect) }
        let neck = min(nonnegative(neckWidth), rect.width)
        let top = min(nonnegative(topCornerRadius), rect.height, (rect.width - neck) / 2)
        let bottom = min(nonnegative(bottomCornerRadius), rect.width / 2 - top, rect.height - top)
        let bodyTop = rect.minY
        let left = rect.minX + top
        let right = rect.maxX - top
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: bodyTop))
        path.addQuadCurve(to: CGPoint(x: left, y: bodyTop + top), control: CGPoint(x: left, y: bodyTop))
        path.addLine(to: CGPoint(x: left, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: left + bottom, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - bottom), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: right, y: bodyTop + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: bodyTop), control: CGPoint(x: right, y: bodyTop))
        return path
    }

    private func nonnegative(_ value: CGFloat) -> CGFloat { value.isFinite ? max(0, value) : 0 }

    private func isValid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite
            && rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
            && rect.maxX.isFinite && rect.maxY.isFinite
            && rect.size.width > 0 && rect.size.height > 0
    }
}

/// Animates exactly the same radii as the fill without closing the bezel edge.
private struct SuzzmeNotchRimShape: Shape {
    var surface: SuzzmeNotchSurfaceShape

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { surface.animatableData }
        set { surface.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path { surface.skirtPath(in: rect) }
}

private struct SuzzmeNotchEdgeTrace: View {
    let shape: SuzzmeNotchSurfaceShape
    let glow: Double
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
    @State private var sweep: CGFloat = 0
    private var motion: SuzzmePresenceMotion { .make(for: state) }

    var body: some View {
        SuzzmeNotchRimShape(surface: shape)
            .stroke(
                LinearGradient(
                    colors: isActive ? [primary, secondary, highlight, primary] : [.white.opacity(0.18), .white.opacity(0.3)],
                    startPoint: UnitPoint(x: phase * motion.travel, y: 0),
                    endPoint: UnitPoint(x: 1 - phase * motion.travel, y: 1)
                ),
                style: StrokeStyle(
                    lineWidth: contrast == .increased ? 2 : isActive ? 1.6 : 0.7,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .background {
                if isActive && !reduceTransparency && contrast != .increased {
                    SuzzmeNotchRimShape(surface: shape)
                        .stroke(primary.opacity(0.18 + Double(phase) * 0.12), lineWidth: 5)
                        .blur(radius: 3)
                }
            }
            .overlay {
                // One finite pass follows the same open rim as the black fill.
                // It never crosses the physical cutout or loops while waiting.
                SuzzmeNotchRimShape(surface: shape)
                    .trim(from: max(0, sweep - 0.22), to: sweep)
                    .stroke(highlight, style: StrokeStyle(lineWidth: contrast == .increased ? 2.5 : 2,
                                                         lineCap: .round, lineJoin: .round))
                    .opacity(isActive ? Double(phase) * 0.9 : 0)
            }
            .shadow(
                color: reduceTransparency || contrast == .increased || !isActive ? .clear : primary.opacity(glow + Double(phase) * 0.1),
                radius: isActive ? 2 + phase * 3 : 0
            )
            .opacity(isActive ? 0.78 + Double(phase) * 0.22 : 0.36)
            .allowsHitTesting(false)
            .task(id: "\(state.rawValue)-\(animation.rawValue)-\(reduceMotion)-\(scenePhase == .active)") {
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { phase = 0; sweep = 0 }
                guard isActive, SuzzmePresenceMotion.allowsMotion(state: state, animation: animation,
                                                                  reduceMotion: reduceMotion, isActive: scenePhase == .active) else { return }
                let duration = motion.entryDuration(for: animation)
                withAnimation(.smooth(duration: duration)) { phase = 1 }
                withAnimation(.easeInOut(duration: min(1.2, duration + 0.45))) { sweep = 1 }
                do { try await Task.sleep(for: .seconds(duration)) }
                catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: SuzzmeTheme.Motion.calm)) { phase = 0 }
            }
            .accessibilityHidden(true)
    }
}

enum MacAssistantSurfaceMetrics {
    static func cornerRadii(state: SuzzmeAssistantState, signal: SuzzmeProactivePresenceSignal, hasDetail: Bool) -> (top: CGFloat, bottom: CGFloat) {
        if hasDetail { return (12, 22) }
        if state == .idle && signal == .none { return (6, 12) }
        return (8, 18)
    }

    static func size(
        state: SuzzmeAssistantState,
        signal: SuzzmeProactivePresenceSignal,
        notchWidth: CGFloat,
        review: SuzzmePresenceReview?,
        response: String?,
        connectionRequest: MacGitHubConnectionRequest? = nil,
        notchHeight: CGFloat = 0,
        contextLabels: [String] = []
    ) -> CGSize {
        let hasDetail = review != nil || response != nil || connectionRequest != nil
        let compactIdle = state == .idle && signal == .none && !hasDetail
        let width: CGFloat
        let height: CGFloat

        // Never make the attachment narrower than the measured physical cutout.
        let cutoutWidth = notchWidth.isFinite ? max(0, notchWidth) : 0
        let activeWidth = max(cutoutWidth + SuzzmeTheme.Spacing.large,
                              min(max(328, cutoutWidth + 148), 380.0))
        if hasDetail {
            width = activeWidth
            if connectionRequest != nil {
                height = 292
            } else if review != nil {
                height = 248
            } else {
                let measured = (response ?? "") as NSString
                let textHeight = measured.boundingRect(
                    with: CGSize(width: activeWidth - 32, height: 1_000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: NSFont.preferredFont(forTextStyle: .body)]
                ).height
                height = min(344, max(200, ceil(textHeight) + 172))
            }
        } else if compactIdle {
            width = max(196, cutoutWidth + SuzzmeTheme.Spacing.large)
            height = 44
        } else if state == .idle {
            width = activeWidth
            height = 78
        } else {
            width = activeWidth
            height = state == .listening ? 96 : 78
        }
        return CGSize(width: width, height: height + max(0, notchHeight) + (contextLabels.isEmpty ? 0 : 32))
    }
}

/// One listen-only event tap sees both foreground and background keyboard edges.
/// Its source runs on the main run loop; no event is swallowed or rewritten.
@MainActor @Observable
final class MacInvocationShortcutMonitor {
    private(set) var status: MacGlobalShortcutStatus = .disabled
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var reducer = SuzzmePushToTalkEdgeReducer()
    private var shortcut: SuzzmeKeyboardShortcut = .disabled
    private var invoke: (() -> Void)?
    private var release: (() -> Void)?
    private var cancel: (() -> Void)?
    private var isInvocationActive: (() -> Bool)?
    private var availabilityChanged: ((Bool) -> Void)?

    var isPressed: Bool { reducer.isPressed }

    func start(
        shortcut: SuzzmeKeyboardShortcut,
        enabled: Bool = true,
        isInvocationActive: @escaping () -> Bool,
        invoke: @escaping () -> Void,
        release: @escaping () -> Void = {},
        cancel: @escaping () -> Void,
        availabilityChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        let shouldMonitor = enabled && shortcut.isEnabled
        let hasPermission = shouldMonitor && CGPreflightListenEventAccess()
        // Permission refreshes must not interrupt a held chord or replace its
        // owner callbacks. Reuse only a genuinely healthy tap, not stale status.
        if shouldMonitor, self.shortcut == shortcut, status == .ready, hasPermission,
           let eventTap, CFMachPortIsValid(eventTap), CGEvent.tapIsEnabled(tap: eventTap),
           let runLoopSource, CFRunLoopSourceIsValid(runLoopSource) {
            return
        }
        stop()
        self.shortcut = shortcut
        self.isInvocationActive = isInvocationActive
        self.invoke = invoke
        self.release = release
        self.cancel = cancel
        self.availabilityChanged = availabilityChanged
        guard shouldMonitor else { setStatus(.disabled); return }
        // Launch never requests permission. Only an explicit Settings action may.
        guard hasPermission else { setStatus(.needsPermission); return }
        // Reconfiguration or recovery cannot turn an already-held chord into
        // a new voice request. Wait for its release before accepting another.
        resetPressedState()
        let eventMask = [CGEventType.flagsChanged, .keyDown, .keyUp].reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { setStatus(.unavailable); return }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            setStatus(.unavailable)
            return
        }
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        if CGEvent.tapIsEnabled(tap: tap) {
            setStatus(.ready)
        } else {
            removeEventTap()
            setStatus(.unavailable)
        }
    }

    func stop() {
        if reducer.isPressed { cancel?() }
        reducer = SuzzmePushToTalkEdgeReducer()
        removeEventTap()
        invoke = nil
        release = nil
        cancel = nil
        isInvocationActive = nil
        availabilityChanged = nil
        status = .disabled
    }

    private func removeEventTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    func resetPressedState() {
        _ = reducer.handle(.init(kind: .reset, modifiers: Self.modifiers(CGEventSource.flagsState(.combinedSessionState))), shortcut: shortcut)
    }

    isolated deinit { stop() }

    private func setStatus(_ status: MacGlobalShortcutStatus) {
        self.status = status
        availabilityChanged?(status == .ready)
    }

    private func handle(eventTypeRawValue: UInt32, keyCode: UInt16, modifiers: SuzzmeShortcutModifiers, isRepeat: Bool) {
        guard eventTap != nil, let eventType = CGEventType(rawValue: eventTypeRawValue) else { return }
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            let wasPressed = reducer.isPressed
            resetPressedState()
            // A lost key-up retires this held capture. An unrelated text or
            // already-released voice response does not belong to the tap.
            if wasPressed { cancel?() }
            guard let eventTap, CGPreflightListenEventAccess() else {
                removeEventTap()
                setStatus(.needsPermission)
                return
            }
            CGEvent.tapEnable(tap: eventTap, enable: true)
            if CGEvent.tapIsEnabled(tap: eventTap) {
                setStatus(.ready)
            } else {
                removeEventTap()
                setStatus(.unavailable)
            }
            return
        }
        guard status == .ready else { return }
        if eventType == .keyDown, keyCode == 53, !isRepeat,
           isInvocationActive?() == true {
            _ = reducer.handle(.init(kind: .reset, modifiers: modifiers), shortcut: shortcut)
            cancel?()
            return
        }
        let kind: SuzzmePushToTalkKeyEvent.Kind
        switch eventType {
        case .flagsChanged: kind = .flagsChanged
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        default: return
        }
        switch reducer.handle(.init(kind: kind, keyCode: keyCode, modifiers: modifiers,
                                  isRepeat: isRepeat), shortcut: shortcut) {
        case .none: break
        case .pressed: invoke?()
        case .released: release?()
        case .cancelled: cancel?()
        }
    }

    nonisolated private static func modifiers(_ flags: CGEventFlags) -> SuzzmeShortcutModifiers {
        var modifiers: SuzzmeShortcutModifiers = []
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        return modifiers
    }

    nonisolated private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        if let userInfo {
            let address = UInt(bitPattern: userInfo)
            let eventTypeRawValue = type.rawValue
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let modifiers = MacInvocationShortcutMonitor.modifiers(event.flags)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            MainActor.assumeIsolated {
                guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
                let monitor = Unmanaged<MacInvocationShortcutMonitor>.fromOpaque(pointer).takeUnretainedValue()
                monitor.handle(eventTypeRawValue: eventTypeRawValue, keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat)
            }
        }
        return Unmanaged.passUnretained(event)
    }
}

#endif
