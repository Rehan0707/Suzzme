// point-return-check.py inserts the exact shipping native owners before this
// fixture. Only source identity, notification delivery, pointer position and
// timer delivery are doubled; native NSPanel resources remain real.

@MainActor private final class PointReturnNotificationCenter {
    final class Registration: NSObject {
        let name: Notification.Name
        let callback: @Sendable (Notification) -> Void
        var removed = false
        init(name: Notification.Name, callback: @escaping @Sendable (Notification) -> Void) {
            self.name = name
            self.callback = callback
        }
    }
    private(set) var registrations: [Registration] = []
    func addObserver(forName name: Notification.Name?, object: Any?, queue: OperationQueue?,
                     using callback: @escaping @Sendable (Notification) -> Void) -> NSObjectProtocol {
        precondition(queue === OperationQueue.main)
        let registration = Registration(name: name ?? .init("missing"), callback: callback)
        registrations.append(registration)
        return registration
    }
    func removeObserver(_ observer: Any) { (observer as? Registration)?.removed = true }
    func post(_ name: Notification.Name) {
        for registration in registrations.filter({ !$0.removed && $0.name == name }) {
            registration.callback(.init(name: name))
        }
    }
    var liveCount: Int { registrations.filter { !$0.removed }.count }
}

@MainActor private enum PointReturnClock {
    struct Wait {
        let id: UUID
        let duration: Duration
        let continuation: CheckedContinuation<Void, Error>
    }
    private(set) static var waits: [Wait] = []

    // Deliberately retains cancelled waits. Releasing one normally tests the
    // production ownership guards even when a late delivery ignores cancellation.
    static func sleep(for duration: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            waits.append(.init(id: UUID(), duration: duration, continuation: continuation))
        }
    }
    static func release(_ id: UUID) {
        guard let index = waits.firstIndex(where: { $0.id == id }) else { return }
        waits.remove(at: index).continuation.resume()
    }
    static func releaseAll() {
        let pending = waits
        waits.removeAll()
        for wait in pending { wait.continuation.resume() }
    }
}

@MainActor private enum PointReturnSystem {
    static let workspaceCenter = PointReturnNotificationCenter()
    static let applicationCenter = PointReturnNotificationCenter()
    static var frontmostPID: Int32? = 123
    static var matchesWindow = true
    static var pointer = CGPoint.zero
    static var reduceMotion = false
}

@MainActor final class MacScreenContextSource {
    static func geometry(for screen: NSScreen) -> ScreenDisplayGeometry? {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
        return .init(displayID: id, x: screen.frame.minX, y: screen.frame.minY,
                     width: screen.frame.width, height: screen.frame.height, scaleFactor: screen.backingScaleFactor)
    }
    static func matchesWindow(_ context: ScreenContextMetadata) -> Bool { PointReturnSystem.matchesWindow }
}

@MainActor @Observable final class AppEnvironment {
    let invocation: InvocationCoordinator
    init(defaults: UserDefaults) { invocation = InvocationCoordinator(defaults: defaults) }
    var currentInteractionID: UUID?
    var screenConsentRequestID: UUID?
    var presentedAction: String?
    var presenceState: SuzzmeAssistantState = .idle
    var presentedResponse: String?
    var presentedScreenGuidance: SpatialReference?
    var presentedScreenMetadata: ScreenContextMetadata?
    var screenPreferences = ScreenPreferenceFixture()
}

struct ScreenPreferenceFixture { var visualGuidance = true }

@MainActor private final class PointReturnController {
    let environment: AppEnvironment
    let guidance: MacGuidanceOverlay
    init(environment: AppEnvironment, guidance: MacGuidanceOverlay) {
        self.environment = environment
        self.guidance = guidance
    }
    func refresh() { updateGuidance() }
    // PRODUCTION_GUIDANCE_GATE
}

private struct MacCursorResponseView: View {
    var body: some View {
        Text("Native response content fixture")
            .frame(width: SuzzmeTheme.Layout.menuBarWidth, height: 180)
    }
}

private struct MacGuidanceMarker: View {
    let label: String
    let target: CGPoint
    var showsFace = true
    var body: some View {
        Text(label).position(target).frame(width: 260, height: 100).allowsHitTesting(false)
    }
}

extension MacCursorCompanion {
    var testedPanel: NSPanel? { panel }
    var testedLocalMonitor: Any? { localMouseMonitor }
    var testedGlobalMonitor: Any? { globalMouseMonitor }
    var testedActiveGuidance: MacGuidanceOverlay.Presentation? { activeGuidance }
    var testedRetiredGuidance: MacGuidanceOverlay.Presentation? { retiredGuidance }
    var testedMotionToken: UUID? { movementToken }
    var testedMovement: NSViewAnimation? { movement }
    var testedReturning: Bool { returningToPointer }
}

extension MacGuidanceOverlay {
    var testedPanel: NSPanel? { panel }
    var testedCompanionPresent: Bool { companionPresent }
}

@main @MainActor private struct PointReturnChecks {
    private static var passed = 0
    private static var failed = 0

    private static func check(_ condition: Bool, _ label: String) {
        print("\(condition ? "PASS" : "FAIL") \(label)")
        if condition { passed += 1 } else { failed += 1 }
    }
    private static func drain() async {
        for _ in 0..<30 { await Task.yield() }
    }
    private static func clearClock() async {
        for _ in 0..<4 {
            PointReturnClock.releaseAll()
            await drain()
        }
    }
    private static func settleMovement() async throws {
        // Real NSViewAnimation remains unmodified. Only the guidance deadline
        // and response timeout use the deterministic clock above.
        pumpNativeAnimations()
        await drain()
    }
    private static func pumpNativeAnimations() {
        RunLoop.main.run(until: .now.addingTimeInterval(0.35))
    }
    private static func sameNativeFrame(_ actual: CGRect?, _ expected: CGRect) -> Bool {
        guard let actual else { return false }
        // AppKit can align animated window frames to the display's pixel grid.
        return zip([actual.minX, actual.minY, actual.width, actual.height],
                   [expected.minX, expected.minY, expected.width, expected.height]).allSatisfy { abs($0 - $1) <= 1 }
    }

    static func main() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first,
              let display = MacScreenContextSource.geometry(for: screen) else {
            print("FAIL point-and-return native checks require a display-connected Mac")
            exit(1)
        }
        let priorKey = NSApp.keyWindow
        let priorMain = NSApp.mainWindow
        let suite = "dev.suzzme.point-return-checks." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { exit(1) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let environment = AppEnvironment(defaults: defaults)
        environment.invocation.cursorCompanionEnabled = true
        environment.presenceState = .reasoning
        let guidance = MacGuidanceOverlay()
        let cursor = MacCursorCompanion(environment: environment, guidance: guidance)
        let controller = PointReturnController(environment: environment, guidance: guidance)
        var endings: [(MacGuidanceOverlay.Presentation, MacGuidanceOverlay.EndReason)] = []
        guidance.onDismiss = { presentation, reason in
            endings.append((presentation, reason))
            cursor.endGuidance(presentation, reason: reason)
        }

        func fixture(_ owner: UUID, age: TimeInterval = 0,
                     x: Double = 0.5, y: Double = 0.5) -> (ScreenContextMetadata, SpatialReference) {
            (.init(requestID: owner, capturedAt: .now.addingTimeInterval(-age), display: display,
                   pixelWidth: 1_000, pixelHeight: 800, activeApplicationPID: 123),
             .init(requestID: owner, displayID: display.displayID, normalizedX: x,
                   normalizedY: y, label: "Disposable target", confidence: 1))
        }
        func show(_ owner: UUID, age: TimeInterval = 0) -> MacGuidanceOverlay.Presentation? {
            environment.currentInteractionID = owner
            let (context, reference) = fixture(owner, age: age)
            environment.presentedScreenMetadata = context
            environment.presentedScreenGuidance = reference
            guard guidance.show(reference: reference, context: context, currentRequestID: owner) else { return nil }
            return guidance.presentation
        }
        func pointer(_ x: CGFloat, _ y: CGFloat) {
            PointReturnSystem.pointer = .init(x: screen.visibleFrame.minX + x * screen.visibleFrame.width,
                                               y: screen.visibleFrame.minY + y * screen.visibleFrame.height)
        }

        let displays = [CGRect(x: 0, y: 0, width: 1_440, height: 900),
                        CGRect(x: -1_920, y: 120, width: 1_920, height: 1_080),
                        CGRect(x: 0, y: -900, width: 1_280, height: 900)]
        for visible in displays {
            for target in [CGPoint(x: visible.minX, y: visible.minY),
                           CGPoint(x: visible.midX, y: visible.midY),
                           CGPoint(x: visible.maxX, y: visible.maxY)] {
                let frame = MacCursorCompanion.guidanceFrame(target: target, visible: visible)
                check(frame.map(visible.contains) == true, "adjacent placement remains inside a normal or negative-origin display")
                check(frame?.contains(target) == false, "adjacent response leaves the measured target uncovered")
            }
        }
        check(MacCursorCompanion.guidanceFrame(target: .init(x: 120, y: 160),
              visible: .init(x: 0, y: 0, width: 240, height: 320)) == nil,
              "a display too small for the companion and marker declines travel")

        pointer(0.12, 0.18)
        let first = UUID()
        guard let firstPresentation = show(first) else { print("FAIL first native guidance fixture"); exit(1) }
        await drain()
        let firstExpiry = PointReturnClock.waits.first?.id
        cursor.update()
        await drain()
        try await settleMovement()
        check(cursor.isPointing && cursor.testedActiveGuidance == firstPresentation,
              "valid owned guidance starts one companion trip")
        check(cursor.testedPanel?.isVisible == true && guidance.testedPanel?.isVisible == true,
              "the native companion and target marker are both visible")
        check(guidance.testedCompanionPresent, "the target marker suppresses its tiny Face while the full companion points")
        check(cursor.testedPanel?.ignoresMouseEvents == true && cursor.testedPanel?.canBecomeKey == false
              && cursor.testedPanel?.canBecomeMain == false,
              "the traveling panel cannot intercept clicks or become a focus window")
        check(NSApp.keyWindow === priorKey && NSApp.mainWindow === priorMain,
              "showing guidance and companion preserves the app's key and main windows")
        check(cursor.testedLocalMonitor == nil && cursor.testedGlobalMonitor == nil,
              "pointer tracking is suspended while the companion points")
        let firstToken = cursor.testedMotionToken
        let firstWaitCount = PointReturnClock.waits.count
        cursor.update()
        await drain()
        check(cursor.testedMotionToken == firstToken && PointReturnClock.waits.count == firstWaitCount,
              "repeated observation updates do not restart travel or extend the target deadline")
        if let companionFrame = cursor.testedPanel?.frame, let markerFrame = guidance.testedPanel?.frame {
            check(!companionFrame.intersects(markerFrame), "native response panel leaves target ring and label unobstructed")
        } else { check(false, "native response panel leaves target ring and label unobstructed") }

        pointer(0.82, 0.22)
        if let firstExpiry { PointReturnClock.release(firstExpiry) }
        await drain()
        try await settleMovement()
        check(guidance.presentation == nil && !cursor.isPointing,
              "normal target expiry ends pointing and retires the marker")
        check(endings.last?.1 == .completed, "normal expiry reports completion rather than context invalidation")
        let expectedReturn = MacCursorCompanion.frame(pointer: PointReturnSystem.pointer, visible: screen.visibleFrame)
        if !sameNativeFrame(cursor.testedPanel?.frame, expectedReturn) {
            print("RETURN_DIAGNOSTIC expected=\(expectedReturn) actual=\(String(describing: cursor.testedPanel?.frame)) returning=\(cursor.testedReturning) moving=\(cursor.testedMovement != nil)")
        }
        check(sameNativeFrame(cursor.testedPanel?.frame, expectedReturn),
              "normal completion returns the companion to the latest pointer position")
        cursor.update()
        check(!cursor.isPointing, "completed evidence cannot replay its companion trip")
        guidance.dismiss()
        cursor.dismiss()
        await clearClock()

        pointer(0.12, 0.18)
        guard show(UUID()) != nil else { print("FAIL moving preference fixture"); exit(1) }
        cursor.update()
        PointReturnSystem.reduceMotion = true
        PointReturnSystem.workspaceCenter.post(NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
        check(!cursor.isPointing && cursor.testedMovement == nil && !guidance.testedCompanionPresent
              && cursor.testedLocalMonitor == nil && cursor.testedGlobalMonitor == nil,
              "Reduce Motion during outbound travel cancels motion and restores the static marker Face")
        PointReturnSystem.reduceMotion = false
        cursor.update()
        check(!cursor.isPointing, "restoring motion does not replay evidence retired by an accessibility change")
        guidance.dismiss()
        cursor.dismiss()
        await clearClock()

        let invalidatedOwner = UUID()
        guard let invalidated = show(invalidatedOwner) else { print("FAIL invalidation fixture"); exit(1) }
        cursor.update()
        await drain()
        let staleWaits = PointReturnClock.waits.map(\.id)
        PointReturnSystem.workspaceCenter.post(NSWorkspace.activeSpaceDidChangeNotification)
        check(guidance.presentation == nil && cursor.testedPanel?.isVisible == false && !cursor.isPointing,
              "Space invalidation synchronously hides the pointing companion and marker")
        check(endings.last?.0 == invalidated && endings.last?.1 == .invalidated,
              "context invalidation is scoped to the presentation that was visible")
        cursor.update()
        check(cursor.testedPanel?.isVisible == false,
              "a context-invalidated request cannot immediately reopen its cursor response")

        let replacementOwner = UUID()
        guard let replacement = show(replacementOwner) else { print("FAIL replacement fixture"); exit(1) }
        cursor.update()
        await drain()
        try await settleMovement()
        let replacementFrame = cursor.testedPanel?.frame
        let replacementToken = cursor.testedMotionToken
        for wait in staleWaits { PointReturnClock.release(wait) }
        await drain()
        check(guidance.presentation == replacement && cursor.isPointing
              && cursor.testedMotionToken == replacementToken && cursor.testedPanel?.frame == replacementFrame,
              "late cancelled timer delivery cannot return or hide a superseding trip")
        cursor.endGuidance(invalidated, reason: .completed)
        check(cursor.testedActiveGuidance == replacement && cursor.isPointing,
              "a delayed completion for old evidence cannot end a newer trip")
        guidance.dismiss()
        cursor.dismiss()
        await clearClock()

        let workspaceInvalidations = [NSWorkspace.didActivateApplicationNotification,
                                      NSWorkspace.willSleepNotification,
                                      NSWorkspace.screensDidSleepNotification,
                                      NSWorkspace.sessionDidResignActiveNotification]
        for notification in workspaceInvalidations {
            pointer(0.12, 0.18)
            guard show(UUID()) != nil else { print("FAIL lifecycle fixture"); exit(1) }
            cursor.update()
            PointReturnSystem.workspaceCenter.post(notification)
            check(guidance.presentation == nil && !cursor.isPointing && cursor.testedPanel?.isVisible == false,
                  "\(notification.rawValue) synchronously retires marker and companion")
            cursor.dismiss()
            await clearClock()
        }
        guard show(UUID()) != nil else { print("FAIL display fixture"); exit(1) }
        cursor.update()
        PointReturnSystem.applicationCenter.post(NSApplication.didChangeScreenParametersNotification)
        check(guidance.presentation == nil && !cursor.isPointing && cursor.testedPanel?.isVisible == false,
              "display reconfiguration synchronously retires marker and companion")
        cursor.dismiss()
        await clearClock()

        func startReturn(age: TimeInterval = 0) async throws -> MacGuidanceOverlay.Presentation {
            pointer(0.12, 0.18)
            guard let presentation = show(UUID(), age: age) else { print("FAIL return-phase fixture"); exit(1) }
            await drain()
            let expiry = PointReturnClock.waits.first?.id
            cursor.update()
            try await settleMovement()
            pointer(0.82, 0.22)
            if let expiry { PointReturnClock.release(expiry) }
            await drain()
            return presentation
        }
        for reduced in [true, false] {
            let returningPresentation = try await startReturn()
            check(cursor.testedReturning && cursor.testedMovement != nil
                  && guidance.isReturnCurrent(returningPresentation),
                  "the finite return retains its validated lifecycle boundary")
            PointReturnSystem.reduceMotion = reduced
            environment.invocation.presenceAnimation = reduced ? .gentle : .minimal
            if reduced {
                PointReturnSystem.workspaceCenter.post(NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            } else { cursor.update() }
            let expected = MacCursorCompanion.frame(pointer: PointReturnSystem.pointer, visible: screen.visibleFrame)
            check(!cursor.testedReturning && cursor.testedMovement == nil
                  && sameNativeFrame(cursor.testedPanel?.frame, expected),
                  reduced ? "enabling Reduce Motion during return cancels travel and resolves at the current pointer" : "selecting Minimal during return cancels travel and resolves at the current pointer")
            check(!guidance.isReturnCurrent(returningPresentation),
                  "instant return completion retires the retained context boundary")
            guidance.dismiss()
            cursor.dismiss()
            await clearClock()
            PointReturnSystem.reduceMotion = false
            environment.invocation.presenceAnimation = .gentle
        }
        for notification in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification,
                             NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            let returningPresentation = try await startReturn()
            check(cursor.testedReturning && guidance.isReturnCurrent(returningPresentation),
                  "native return is active before a workspace invalidation")
            PointReturnSystem.workspaceCenter.post(notification)
            check(!cursor.testedReturning && cursor.testedMovement == nil && cursor.testedPanel?.isVisible == false
                  && !guidance.isReturnCurrent(returningPresentation),
                  "\(notification.rawValue) synchronously cancels an in-progress return")
            cursor.update()
            check(cursor.testedPanel?.isVisible == false,
                  "a request invalidated during return cannot reopen a cursor response")
            guidance.dismiss()
            cursor.dismiss()
            await clearClock()
        }
        let returningBeforeDisplayChange = try await startReturn()
        PointReturnSystem.applicationCenter.post(NSApplication.didChangeScreenParametersNotification)
        check(!cursor.testedReturning && cursor.testedMovement == nil && cursor.testedPanel?.isVisible == false
              && !guidance.isReturnCurrent(returningBeforeDisplayChange),
              "display reconfiguration synchronously cancels an in-progress return")
        guidance.dismiss()
        cursor.dismiss()
        await clearClock()

        let nearExpiryReturn = try await startReturn(age: 29.4)
        let returnDeadline = PointReturnClock.waits.last
        check(cursor.testedReturning && guidance.isReturnCurrent(nearExpiryReturn)
              && returnDeadline.map({ $0.duration > .zero && $0.duration < .seconds(1) }) == true,
              "a near-expired capture gives the finite return only its remaining freshness")
        if let returnDeadline { PointReturnClock.release(returnDeadline.id) }
        await drain()
        check(!cursor.testedReturning && cursor.testedMovement == nil && cursor.testedPanel?.isVisible == false
              && !guidance.isReturnCurrent(nearExpiryReturn),
              "the freshness watchdog synchronously stops return and hides expired guidance")
        guidance.dismiss()
        cursor.dismiss()
        await clearClock()

        _ = try await startReturn(age: 29.4)
        let oldReturnDeadline = PointReturnClock.waits.last?.id
        guard let newestPresentation = show(UUID()) else { print("FAIL stale return deadline fixture"); exit(1) }
        cursor.update()
        let newestToken = cursor.testedMotionToken
        if let oldReturnDeadline { PointReturnClock.release(oldReturnDeadline) }
        await drain()
        check(guidance.presentation == newestPresentation && cursor.isPointing
              && cursor.testedMotionToken == newestToken,
              "late cancelled return expiry cannot invalidate a superseding trip")
        guidance.dismiss()
        cursor.dismiss()
        await clearClock()

        for reduced in [true, false] {
            PointReturnSystem.reduceMotion = reduced
            environment.invocation.presenceAnimation = reduced ? .gentle : .minimal
            pointer(0.14, 0.2)
            let owner = UUID()
            guard show(owner) != nil else { print("FAIL static motion fixture"); exit(1) }
            cursor.update()
            await drain()
            check(!cursor.isPointing && cursor.testedActiveGuidance == nil,
                  reduced ? "Reduce Motion retains static guidance without companion travel" : "Minimal animation retains static guidance without companion travel")
            check(cursor.testedLocalMonitor == nil && cursor.testedGlobalMonitor == nil,
                  reduced ? "Reduce Motion installs no cursor-follow monitors" : "Minimal animation installs no cursor-follow monitors")
            check(guidance.presentation != nil && guidance.testedPanel?.isVisible == true,
                  "static guidance keeps the target marker available")
            guidance.dismiss()
            cursor.dismiss()
            await clearClock()
        }
        PointReturnSystem.reduceMotion = false
        environment.invocation.presenceAnimation = .gentle

        PointReturnSystem.pointer = .init(x: (NSScreen.screens.map(\.frame.maxX).max() ?? 0) + 100,
                                            y: screen.frame.midY)
        guard show(UUID()) != nil else { print("FAIL unavailable-pointer fixture"); exit(1) }
        cursor.update()
        check(cursor.isPointing && cursor.testedMovement == nil && guidance.presentation != nil,
              "an unavailable pointer display resolves validated guidance instantly without native travel")
        guidance.dismiss()
        cursor.dismiss()
        await clearClock()
        pointer(0.12, 0.18)

        let expiringOwner = UUID()
        guard show(expiringOwner, age: 29.8) != nil else { print("FAIL age-bound fixture"); exit(1) }
        await drain()
        check(PointReturnClock.waits.contains { $0.duration > .zero && $0.duration < .seconds(1) },
              "a near-expiry capture bounds the guidance deadline by remaining freshness")
        guidance.dismiss()
        cursor.dismiss()
        await clearClock()

        for gate in ["disabled", "consent", "action", "owner", "error", "guidance preference"] {
            let owner = UUID()
            environment.currentInteractionID = owner
            environment.presenceState = .reasoning
            environment.invocation.cursorCompanionEnabled = true
            environment.screenConsentRequestID = nil
            environment.presentedAction = nil
            environment.screenPreferences.visualGuidance = true
            guard show(owner) != nil else { print("FAIL gate fixture"); exit(1) }
            cursor.update()
            switch gate {
            case "disabled": environment.invocation.cursorCompanionEnabled = false
            case "consent": environment.screenConsentRequestID = UUID()
            case "action": environment.presentedAction = "Review required"
            case "owner": environment.currentInteractionID = nil
            case "error": environment.presenceState = .error
            default: environment.screenPreferences.visualGuidance = false
            }
            controller.refresh()
            cursor.update()
            check(!cursor.isPointing && cursor.testedActiveGuidance == nil
                  && (gate == "error" || cursor.testedPanel?.isVisible == false),
                  "\(gate) retires an active companion trip")
            guidance.dismiss()
            cursor.dismiss()
            await clearClock()
        }
        environment.screenConsentRequestID = nil
        environment.presentedAction = nil
        environment.currentInteractionID = nil
        cursor.dismiss()
        guidance.dismiss()
        await clearClock()
        check(PointReturnSystem.workspaceCenter.liveCount == 0 && PointReturnSystem.applicationCenter.liveCount == 0
              && cursor.testedLocalMonitor == nil && cursor.testedGlobalMonitor == nil,
              "cleanup removes all guidance observers and cursor monitors")
        print("Point-and-return checks: \(passed) passed / \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
