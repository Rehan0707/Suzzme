#if os(macOS)
// Adapted from Clicky's CompanionResponseOverlay.swift. Copyright (c) 2026 Farza.
// MIT license: Suzzme/ReferenceSource/Clicky/LICENSE.
import AppKit
import SwiftUI

private final class SuzzmeCursorResponsePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// An opt-in, click-through response surface. The existing invocation owner
/// supplies state; this adapter does not listen, capture, infer or execute.
@MainActor
final class MacCursorCompanion: NSObject, NSAnimationDelegate {
    private let environment: AppEnvironment
    private let guidance: MacGuidanceOverlay
    private var panel: NSPanel?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var dismissal: Task<Void, Never>?
    private var requestID: UUID?
    private var retiredRequestID: UUID?
    private var activeGuidance: MacGuidanceOverlay.Presentation?
    private var retiredGuidance: MacGuidanceOverlay.Presentation?
    private var movement: NSViewAnimation?
    private var movementCompletion: (() -> Void)?
    private var movementToken = UUID()
    private var returningToPointer = false
    private var motionObserver: NSObjectProtocol?

    init(environment: AppEnvironment, guidance: MacGuidanceOverlay) {
        self.environment = environment
        self.guidance = guidance
        super.init()
    }

    var isPointing: Bool { activeGuidance != nil }

    private var allowsMotion: Bool {
        environment.invocation.presenceAnimation != .minimal
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func update() {
        guard environment.invocation.cursorCompanionEnabled,
              let owner = environment.currentInteractionID,
              environment.screenConsentRequestID == nil,
              environment.presentedAction == nil else { dismiss(); return }
        if requestID != owner {
            dismiss()
            requestID = owner
        }
        guard retiredRequestID != owner else { return }
        if returningToPointer && !allowsMotion {
            guard let ended = retiredGuidance, guidance.isReturnCurrent(ended) else {
                retiredRequestID = owner
                dismiss()
                return
            }
            cancelMovement()
            guidance.finishReturn(ended)
            positionNearCursor()
        }
        if let activeGuidance {
            guard guidance.isCurrent(activeGuidance) else {
                endGuidance(activeGuidance, reason: .invalidated)
                return
            }
            if !allowsMotion {
                // Resolve a preference change immediately, without another trip.
                retiredGuidance = activeGuidance
                self.activeGuidance = nil
                cancelMovement()
                positionNearCursor()
            }
        }
        let target = guidance.presentation
        if allowsMotion, activeGuidance == nil, !returningToPointer,
           let target, target != retiredGuidance, target.reference.requestID == owner,
           guidance.isCurrent(target), Self.guidanceFrame(target: target.target, visible: target.visibleFrame) != nil {
            showIfNeeded()
            beginGuidance(target)
        }
        if isPointing || returningToPointer {
            dismissal?.cancel()
            dismissal = nil
            reconcileTracking()
            return
        }
        if environment.presenceState == .idle {
            guard panel?.isVisible == true, environment.presentedResponse != nil else { dismiss(); return }
            scheduleDismissal(owner: owner)
            reconcileTracking()
            return
        }
        dismissal?.cancel()
        dismissal = nil
        showIfNeeded()
        reconcileTracking()
        guidance.setCompanionPresent(isPointing)
    }

    func endGuidance(_ ended: MacGuidanceOverlay.Presentation, reason: MacGuidanceOverlay.EndReason) {
        if returningToPointer, retiredGuidance == ended, reason == .invalidated {
            retiredRequestID = ended.reference.requestID
            dismiss()
            return
        }
        guard activeGuidance == ended else {
            guidance.finishReturn(ended)
            return
        }
        activeGuidance = nil
        retiredGuidance = ended
        cancelMovement()
        guard reason == .completed, requestID == ended.reference.requestID,
              environment.currentInteractionID == requestID,
              environment.invocation.cursorCompanionEnabled,
              environment.screenConsentRequestID == nil, environment.presentedAction == nil,
              guidance.isReturnCurrent(ended),
              ended.reference.isValid(for: ended.context, requestID: ended.reference.requestID),
              panel?.isVisible == true, let destination = pointerFrame() else {
            retiredRequestID = ended.reference.requestID
            dismiss()
            return
        }
        returningToPointer = true
        let owner = ended.reference.requestID
        move(to: destination) { [weak self] in
            guard let self else { return }
            guard self.requestID == owner, self.environment.currentInteractionID == owner else {
                self.guidance.finishReturn(ended)
                return
            }
            guard self.guidance.isReturnCurrent(ended) else {
                self.retiredRequestID = owner
                self.dismiss()
                return
            }
            self.guidance.finishReturn(ended)
            self.returningToPointer = false
            // The pointer may have moved during the finite return animation.
            self.positionNearCursor()
            self.reconcileTracking()
            if self.environment.presenceState == .idle { self.scheduleDismissal(owner: owner) }
        }
    }

    func dismiss() {
        if let activeGuidance { retiredGuidance = activeGuidance }
        if let retiredGuidance { guidance.finishReturn(retiredGuidance) }
        activeGuidance = nil
        cancelMovement()
        dismissal?.cancel()
        dismissal = nil
        panel?.orderOut(nil)
        // Remove the hosting subtree so hidden companions stop their motion.
        panel?.contentView = nil
        removeTracking()
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
        motionObserver = nil
        requestID = nil
    }

    isolated deinit {
        movement?.delegate = nil
        movement?.stop()
        dismissal?.cancel()
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
        panel?.close()
    }

    nonisolated func animationDidEnd(_ animation: NSAnimation) {
        let identifier = ObjectIdentifier(animation)
        // Nonblocking NSViewAnimation is started on the main run loop.
        MainActor.assumeIsolated {
            guard let movement, ObjectIdentifier(movement) == identifier else { return }
            self.movement = nil
            let completion = movementCompletion
            movementCompletion = nil
            completion?()
        }
    }

    static func frame(pointer: CGPoint, visible: CGRect) -> CGRect {
        let width = min(SuzzmeTheme.Layout.menuBarWidth, visible.width)
        let height = min(180, visible.height)
        let offset = SuzzmeTheme.Spacing.large
        let x = pointer.x + offset + width <= visible.maxX ? pointer.x + offset : pointer.x - width - offset
        return CGRect(x: max(visible.minX, min(x, visible.maxX - width)),
                      y: max(visible.minY, min(pointer.y - height - offset, visible.maxY - height)),
                      width: width, height: height)
    }

    /// Keep the verified ring/label unobscured. Small displays can retain the
    /// ordinary static companion instead of forcing an overlapping placement.
    static func guidanceFrame(target: CGPoint, visible: CGRect) -> CGRect? {
        guard [target.x, target.y, visible.minX, visible.minY, visible.width, visible.height].allSatisfy(\.isFinite),
              visible.width > 0, visible.height > 0 else { return nil }
        let size = frame(pointer: target, visible: visible).size
        let markerSize = CGSize(width: min(260, visible.width), height: min(100, visible.height))
        let marker = CGRect(x: max(visible.minX, min(target.x - markerSize.width / 2, visible.maxX - markerSize.width)),
                            y: max(visible.minY, min(target.y - markerSize.height / 2, visible.maxY - markerSize.height)),
                            width: markerSize.width, height: markerSize.height)
        let gap = SuzzmeTheme.Spacing.medium
        let origins = [CGPoint(x: marker.maxX + gap, y: target.y - size.height / 2),
                       CGPoint(x: marker.minX - gap - size.width, y: target.y - size.height / 2),
                       CGPoint(x: target.x - size.width / 2, y: marker.minY - gap - size.height),
                       CGPoint(x: target.x - size.width / 2, y: marker.maxY + gap)]
        return origins.map { point in
            CGRect(x: max(visible.minX, min(point.x, visible.maxX - size.width)),
                   y: max(visible.minY, min(point.y, visible.maxY - size.height)),
                   width: size.width, height: size.height)
        }.first { !$0.intersects(marker.insetBy(dx: -gap, dy: -gap)) }
    }

    private func showIfNeeded() {
        if panel == nil { createPanel() }
        guard panel?.isVisible != true else { return }
        if panel?.contentView == nil {
            panel?.contentView = NSHostingView(rootView: MacCursorResponseView().environment(environment))
        }
        positionNearCursor()
        panel?.orderFrontRegardless()
        if motionObserver == nil {
            motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.update()
                    self.guidance.setCompanionPresent(self.isPointing)
                }
            }
        }
    }

    private func beginGuidance(_ target: MacGuidanceOverlay.Presentation) {
        guard guidance.isCurrent(target), let destination = Self.guidanceFrame(target: target.target, visible: target.visibleFrame)
        else { return }
        removeTracking()
        activeGuidance = target
        guidance.setCompanionPresent(true)
        move(to: destination) { [weak self] in
            guard let self, self.activeGuidance == target else { return }
            guard self.guidance.isCurrent(target) else {
                self.guidance.dismiss()
                self.endGuidance(target, reason: .invalidated)
                return
            }
        }
    }

    private func move(to frame: CGRect, completion: @escaping () -> Void) {
        cancelMovement(clearsReturn: false)
        guard let panel else { return }
        // Crossing displays or changing size resolves instantly; a flight never
        // passes through another display's unrelated content.
        let sameDisplay = NSScreen.screens.contains { $0.visibleFrame.contains(panel.frame) && $0.visibleFrame.contains(frame) }
        guard allowsMotion, pointerFrame() != nil, sameDisplay, panel.frame.size == frame.size, panel.frame != frame else {
            panel.setFrame(frame, display: true)
            completion()
            return
        }
        let token = movementToken
        let animation = NSViewAnimation(viewAnimations: [[.target: panel,
            .startFrame: NSValue(rect: panel.frame), .endFrame: NSValue(rect: frame)]])
        animation.duration = SuzzmeTheme.Motion.standard
        animation.animationCurve = .easeInOut
        animation.animationBlockingMode = .nonblocking
        animation.delegate = self
        movement = animation
        movementCompletion = { [weak self] in
            guard let self, self.movementToken == token else { return }
            completion()
        }
        animation.start()
    }

    private func cancelMovement(clearsReturn: Bool = true) {
        movementToken = UUID()
        let previous = movement
        movement = nil
        movementCompletion = nil
        previous?.delegate = nil
        previous?.stop()
        if clearsReturn { returningToPointer = false }
    }

    private func scheduleDismissal(owner: UUID) {
        guard dismissal == nil else { return }
        dismissal = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self, self.requestID == owner, self.activeGuidance == nil, !self.returningToPointer else { return }
            self.retiredRequestID = owner
            self.dismiss()
        }
    }

    private func createPanel() {
        let panel = SuzzmeCursorResponsePanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Suzzme cursor companion"
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: MacCursorResponseView().environment(environment))
        self.panel = panel
    }

    private func pointerFrame() -> CGRect? {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return nil }
        return Self.frame(pointer: point, visible: screen.visibleFrame)
    }

    private func positionNearCursor() {
        guard activeGuidance == nil, !returningToPointer, let frame = pointerFrame() else { return }
        panel?.setFrame(frame, display: true)
    }

    private func reconcileTracking() {
        // Event driven, not a permanent 60 Hz timer. Both monitors are removed
        // during guidance, when hidden, and for Minimal or Reduce Motion.
        guard panel?.isVisible == true, allowsMotion, activeGuidance == nil, !returningToPointer else {
            removeTracking()
            return
        }
        guard globalMouseMonitor == nil, localMouseMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.positionNearCursor() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.positionNearCursor() }
            return event
        }
    }

    private func removeTracking() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
    }
}

private struct MacCursorResponseView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.small) {
            SuzzmeMascot(state: environment.presenceState,
                size: SuzzmeTheme.Layout.touchTarget,
                animation: environment.invocation.presenceAnimation,
                audioLevel: environment.voice.isListening ? environment.voice.audioLevel : 0,
                speechProgress: environment.voice.isSpeaking ? environment.voice.speechProgress : 0)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                Text(environment.presenceState == .idle ? "Suzzme" :
                    SuzzmeAssistantPresentation.make(for: environment.presenceState).title).font(.headline)
                Text(displayText).font(.subheadline).lineLimit(5)
                    .foregroundStyle(.secondary)
                if environment.voice.isSpeaking {
                    ProgressView(value: environment.voice.speechProgress).accessibilityLabel("Spoken answer progress")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(SuzzmeTheme.Spacing.medium).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .suzzmeGlassControlSurface(cornerRadius: SuzzmeTheme.Radius.card,
                                   tint: SuzzmeTheme.intelligencePrimary.opacity(0.12))
        .accessibilityElement(children: .combine)
    }

    private var displayText: String {
        if environment.voice.isListening {
            return environment.voice.partialTranscript.isEmpty ? "Go ahead. I’m listening." : environment.voice.partialTranscript
        }
        return environment.presentedResponse ?? environment.presenceState.activityDescription ?? "Ready when you are"
    }
}
#endif
