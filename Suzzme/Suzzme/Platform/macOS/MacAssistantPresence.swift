#if os(macOS)
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A system-adjacent surface must respond to the first click even when the
/// main Suzzme window is inactive. The panel remains app-owned and uses only
/// public AppKit behavior.
private final class MacAssistantHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class MacAssistantPanelController {
    private var panel: NSPanel?
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
        let review: SuzzmePresenceReview?
        let response: String?
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
    private var currentReview: SuzzmePresenceReview?
    private var currentConfirmation: ((Bool) -> Void)?

    func update(state: SuzzmeAssistantState, theme: SuzzmePresenceTheme, animation: SuzzmePresenceAnimation, signal: SuzzmeProactivePresenceSignal = .none, review: SuzzmePresenceReview? = nil, response: String? = nil, onConfirmation: ((Bool) -> Void)? = nil, onCancel: @escaping () -> Void, onInvoke: @escaping () -> Void) {
        currentResponse = state == .speaking ? response.map { String($0.prefix(2_000)) } : nil
        currentState = state
        currentTheme = theme
        currentAnimation = animation
        currentSignal = signal
        currentCancel = onCancel
        currentInvoke = onInvoke
        currentReview = state == .awaitingConfirmation ? review : nil
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
        renderedIdentity = nil
        suppressedIdentity = nil
        currentCancel = nil
        currentInvoke = nil
        currentReview = nil
        currentResponse = nil
        currentConfirmation = nil
    }

    /// Suppresses only the presentation the user pressed. A subsequent state,
    /// signal, response, or confirmation is allowed to become visible again.
    func hideCurrentPresentation() {
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
        let isInside = notchEntryRect.contains(point)
        defer { pointerWasInNotch = isInside }
        guard isInside, !pointerWasInNotch, currentState == .idle,
              currentSignal == .none, suppressedIdentity != nil else { return }
        suppressedIdentity = nil
        renderedIdentity = nil
        refreshPresentation()
    }

    private func installMouseMonitors() {
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
        guard let screen = NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let hasNotch = screen.safeAreaInsets.top > 0 && screen.auxiliaryTopRightArea != nil && screen.auxiliaryTopLeftArea != nil
        // A physical notch is Suzzme's persistent invocation affordance. The
        // top-center fallback appears only while there is real assistant or
        // proactive activity, avoiding a permanent floating control on Macs
        // without a notch.
        guard hasNotch || presentation.isVisible || currentSignal != .none else {
            dismiss()
            return
        }
        let notchWidth: CGFloat
        if hasNotch, let right = screen.auxiliaryTopRightArea, let left = screen.auxiliaryTopLeftArea {
            notchWidth = max(0, right.minX - left.maxX)
            notchEntryRect = NSRect(x: left.maxX, y: screen.frame.maxY - screen.safeAreaInsets.top,
                                    width: notchWidth, height: screen.safeAreaInsets.top)
            installMouseMonitors()
        } else {
            notchWidth = 0
            removeMouseMonitors()
        }
        let size = MacAssistantSurfaceMetrics.size(
            state: currentState,
            signal: currentSignal,
            notchWidth: notchWidth,
            review: currentReview,
            response: currentResponse
        )
        let panel = panel ?? makePanel()
        self.panel = panel
        let identity = PresentationIdentity(state: currentState, theme: currentTheme, animation: currentAnimation, signal: currentSignal, hasNotch: hasNotch, notchWidth: notchWidth, review: currentReview, response: currentResponse)
        if suppressedIdentity == identity {
            if collapseTask == nil { panel.orderOut(nil) }
            return
        }
        collapseTask?.cancel()
        collapseTask = nil
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        suppressedIdentity = nil
        if renderedIdentity != identity {
            autoHideTask?.cancel()
            autoHideTask = nil
            panel.contentView = MacAssistantHostingView(rootView: MacAssistantNotchSurface(
                state: currentState, theme: currentTheme, animation: currentAnimation,
                signal: currentSignal, hasNotch: hasNotch, notchWidth: notchWidth, review: currentReview, response: currentResponse,
                onConfirmation: currentConfirmation,
                onCancel: { [weak self] in self?.currentCancel?() },
                onInvoke: { [weak self] in self?.currentInvoke?() },
                onDismiss: { [weak self] in self?.hideCurrentPresentation() }
            ))
            renderedIdentity = identity
            if currentState == .idle && currentSignal == .none {
                autoHideTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(8)) }
                    catch { return }
                    guard let self, self.renderedIdentity == identity else { return }
                    self.hideCurrentPresentation()
                }
            }
        }
        let visible = screen.visibleFrame
        // The top edge stays fixed at the physical cutout's lower edge.
        // All pixels belong to this app, below the hardware cutout.
        // A one-point overlap removes the bright seam that some display scales
        // reveal between the physical cutout and the app-owned surface.
        let anchor = hasNotch ? screen.frame.maxY - screen.safeAreaInsets.top + 1 : visible.maxY - 8
        let y = anchor - size.height
        // A side Dock changes visibleFrame's center, not the hardware cutout.
        let centerX = hasNotch ? notchEntryRect.midX : visible.midX
        let frame = NSRect(x: max(visible.minX, centerX - size.width / 2),
                           y: max(visible.minY, y), width: min(size.width, visible.width),
                           height: min(size.height, visible.height))
        if panel.frame != frame {
            let shouldAnimate = currentAnimation != .minimal && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if !panel.isVisible {
                panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - 1, width: frame.width, height: 1), display: false)
            }
            if shouldAnimate {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = SuzzmeTheme.Motion.presenceExpansion
                    panel.animator().setFrame(frame, display: true)
                }
            } else { panel.setFrame(frame, display: true) }
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
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
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        return panel
    }
}

struct MacAssistantNotchSurface: View {
    let state: SuzzmeAssistantState
    let theme: SuzzmePresenceTheme
    let animation: SuzzmePresenceAnimation
    let signal: SuzzmeProactivePresenceSignal
    let hasNotch: Bool
    var notchWidth: CGFloat = 180
    var edgeGlow = SuzzmeTheme.Motion.presenceGlow
    var review: SuzzmePresenceReview?
    var response: String?
    var onConfirmation: ((Bool) -> Void)?
    let onCancel: () -> Void
    let onInvoke: () -> Void
    var onDismiss: () -> Void = {}
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var presentation: SuzzmeAssistantPresentation { .make(for: state) }

    @ViewBuilder var body: some View {
        let colors = theme.colors(for: .dark)
        let shape = SuzzmeNotchSurfaceShape(attached: hasNotch, neckWidth: notchWidth)
        if surfaceTapInvokes {
            surface(colors: colors, shape: shape)
                .contentShape(shape)
                .gesture(
                    LongPressGesture(minimumDuration: 0.7)
                        .onEnded { _ in onDismiss() }
                        .exclusively(before: TapGesture().onEnded { onInvoke() })
                )
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onInvoke() }
                .accessibilityAction(named: "Hide Suzzme") { onDismiss() }
                .accessibilityHint("Click to open Suzzme. Press and hold to hide.")
        } else {
            surface(colors: colors, shape: shape)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.7).onEnded { _ in onDismiss() }
                )
                .accessibilityAction(named: "Hide Suzzme") { onDismiss() }
                .accessibilityHint("Press and hold to hide Suzzme")
        }
    }

    private func surface(colors: SuzzmePresenceColors, shape: SuzzmeNotchSurfaceShape) -> some View {
        VStack(spacing: 8) {
            SuzzmeAssistantPresenceView(
                state: state,
                theme: theme,
                animation: animation,
                proactiveSignal: signal,
                systemSurface: true,
                onCancel: onCancel
            )
            if let response {
                Text(response)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
            }
            if let review {
                Text(review.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                HStack {
                    Button("Cancel", role: .cancel) { onConfirmation?(false) }
                    Spacer()
                    Button(review.confirmationLabel, role: review.isDestructive ? .destructive : nil) { onConfirmation?(true) }
                        .tint(review.isDestructive ? .red : .accentColor)
                        .foregroundStyle(review.isDestructive ? Color.red : Color.primary)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black, in: shape)
        .overlay {
            SuzzmeNotchEdgeTrace(
                attached: hasNotch,
                primary: colors.primary,
                secondary: colors.secondary,
                highlight: colors.highlight,
                isActive: presentation.emphasis != .ambient,
                animation: animation
            )
        }
        .shadow(color: reduceTransparency ? .clear : colors.glow.opacity(state == .idle ? 0 : edgeGlow), radius: 5, y: 3)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.systemStatus)
    }

    private var surfaceTapInvokes: Bool {
        guard review == nil else { return false }
        return switch state {
        case .idle, .success, .error: true
        default: false
        }
    }
}

/// Concave shoulders meet the cutout below its hardware edge. No fake notch.
struct SuzzmeNotchSurfaceShape: Shape {
    var attached: Bool
    var neckWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        guard attached else { return RoundedRectangle(cornerRadius: 24, style: .continuous).path(in: rect) }
        let shoulderDepth = min(12.0, rect.height * 0.28)
        let radius = min(18.0, max(10.0, rect.height * 0.18))
        let neck = min(max(0, neckWidth), max(0, rect.width - 24))
        let left = rect.midX - neck / 2
        let right = rect.midX + neck / 2
        var path = Path()
        path.move(to: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: right, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + shoulderDepth), control1: CGPoint(x: right, y: rect.minY + shoulderDepth), control2: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + shoulderDepth))
        path.addCurve(to: CGPoint(x: left, y: rect.minY), control1: CGPoint(x: rect.minX, y: rect.minY), control2: CGPoint(x: left, y: rect.minY + shoulderDepth))
        path.closeSubpath()
        return path
    }
}

/// Only the lower perimeter glows. Leaving the top edge black makes the app
/// surface visually continuous with the physical notch instead of outlined.
private struct SuzzmeNotchRimShape: Shape {
    let attached: Bool

    func path(in rect: CGRect) -> Path {
        guard attached else {
            return RoundedRectangle(cornerRadius: 18, style: .continuous).path(in: rect)
        }
        let shoulderDepth = min(12.0, rect.height * 0.28)
        let radius = min(18.0, max(10.0, rect.height * 0.18))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + shoulderDepth))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - radius),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + shoulderDepth))
        return path
    }
}

private struct SuzzmeNotchEdgeTrace: View {
    let attached: Bool
    let primary: Color
    let secondary: Color
    let highlight: Color
    let isActive: Bool
    let animation: SuzzmePresenceAnimation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @State private var breathes = false

    var body: some View {
        SuzzmeNotchRimShape(attached: attached)
            .stroke(
                LinearGradient(
                    colors: [primary.opacity(0.72), highlight, secondary, highlight.opacity(0.82)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(
                    lineWidth: contrast == .increased ? 2 : isActive ? 1.35 : 0.7,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .shadow(
                color: reduceTransparency ? .clear : primary.opacity(isActive ? (breathes ? 0.38 : 0.18) : 0.08),
                radius: isActive ? (breathes ? 7 : 3) : 2
            )
            .opacity(isActive ? (breathes ? 1 : 0.78) : 0.36)
            .allowsHitTesting(false)
            .task(id: "\(isActive)-\(animation.rawValue)-\(reduceMotion)-\(scenePhase == .active)") {
                breathes = false
                guard isActive, animation.duration > 0, !reduceMotion, scenePhase == .active else { return }
                withAnimation(.easeInOut(duration: max(1.4, animation.duration)).repeatForever(autoreverses: true)) {
                    breathes = true
                }
            }
            .accessibilityHidden(true)
    }
}

enum MacAssistantSurfaceMetrics {
    static func size(
        state: SuzzmeAssistantState,
        signal: SuzzmeProactivePresenceSignal,
        notchWidth: CGFloat,
        review: SuzzmePresenceReview?,
        response: String?
    ) -> CGSize {
        let presentation = SuzzmeAssistantPresentation.make(for: state)
        let hasDetail = review != nil || response != nil
        let compactIdle = state == .idle && signal == .none && !hasDetail
        let width: CGFloat
        let height: CGFloat

        if hasDetail {
            width = min(max(390, notchWidth + 190), 440)
            height = review != nil ? 184 : 164
        } else if compactIdle {
            width = min(max(196, notchWidth + 20), 232)
            height = 38
        } else if state == .idle {
            width = min(max(282, notchWidth + 86), 340)
            height = 66
        } else {
            width = min(max(300, notchWidth + 104), 360)
            height = presentation.canExpand ? 96 : 76
        }
        return CGSize(width: width, height: height)
    }
}

@MainActor
final class MacInvocationShortcutMonitor {
    private static let signature: OSType = 0x53555A4D // "SUZM"
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var localMonitor: Any?
    private var invoke: (() -> Void)?
    private var cancel: (() -> Void)?
    private var isInvocationActive: (() -> Bool)?

    func start(
        shortcut: SuzzmeKeyboardShortcut,
        isInvocationActive: @escaping () -> Bool,
        invoke: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        stop()
        self.isInvocationActive = isInvocationActive
        self.invoke = invoke
        self.cancel = cancel

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53, self.isInvocationActive?() == true {
                self.cancel?()
                return nil
            }
            return event
        }

        guard shortcut != .disabled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installation = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard installation == noErr else { return }

        var reference: EventHotKeyRef?
        let registration = RegisterEventHotKey(
            shortcut.carbonKeyCode,
            shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard registration == noErr else {
            if let handler { RemoveEventHandler(handler) }
            handler = nil
            return
        }
        hotKey = reference
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        hotKey = nil
        handler = nil
        localMonitor = nil
        invoke = nil
        cancel = nil
        isInvocationActive = nil
    }

    isolated deinit { stop() }

    private func handleHotKey() { invoke?() }

    nonisolated private static let hotKeyHandler: EventHandlerUPP = { _, _, userData in
        guard let userData else { return noErr }
        // Carbon invokes this application event handler on the main event loop.
        // Resolve only while the registered handler owns a live monitor; never
        // carry its unretained address into an asynchronous task.
        let address = UInt(bitPattern: userData)
        MainActor.assumeIsolated {
            guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
            let monitor = Unmanaged<MacInvocationShortcutMonitor>.fromOpaque(pointer).takeUnretainedValue()
            monitor.handleHotKey()
        }
        return noErr
    }
}

private extension SuzzmeKeyboardShortcut {
    var carbonKeyCode: UInt32 {
        switch self {
        case .commandOptionSpace, .commandShiftSpace: UInt32(kVK_Space)
        case .commandOptionReturn: UInt32(kVK_Return)
        case .disabled: 0
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .commandOptionSpace, .commandOptionReturn: UInt32(cmdKey | optionKey)
        case .commandShiftSpace: UInt32(cmdKey | shiftKey)
        case .disabled: 0
        }
    }
}
#endif
