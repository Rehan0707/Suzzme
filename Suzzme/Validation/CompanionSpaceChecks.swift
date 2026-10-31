// companion-space-check.py inserts the exact production methods in these
// isolated shells. Only OS notifications/capture identity and async source
// cleanup are doubled. The real guidance owner uses real native panels.

@MainActor private final class GuidanceNotificationCenter {
    final class Registration: NSObject {
        let name: Notification.Name
        let callback: @Sendable (Notification) -> Void
        var removed = false
        init(name: Notification.Name, callback: @escaping @Sendable (Notification) -> Void) {
            self.name = name; self.callback = callback
        }
    }
    private(set) var registrations: [Registration] = []
    func addObserver(forName name: Notification.Name?, object: Any?, queue: OperationQueue?,
                     using callback: @escaping @Sendable (Notification) -> Void) -> NSObjectProtocol {
        precondition(queue === OperationQueue.main, "production delivery must use the main queue")
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

@MainActor private enum GuidanceSystemDouble {
    static let workspaceCenter = GuidanceNotificationCenter()
    static let applicationCenter = GuidanceNotificationCenter()
    static var frontmostPID: Int32? = 123
}

@MainActor private final class MacScreenContextSource {
    static func geometry(for screen: NSScreen) -> ScreenDisplayGeometry? {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
        return .init(displayID: id, x: screen.frame.minX, y: screen.frame.minY,
                     width: screen.frame.width, height: screen.frame.height, scaleFactor: screen.backingScaleFactor)
    }
    static func matchesWindow(_ context: ScreenContextMetadata) -> Bool { true }
}

private struct MacGuidanceMarker: View {
    let label: String
    let target: CGPoint
    var showsFace = true
    var body: some View { Text(label).position(target).allowsHitTesting(false) }
}

@MainActor private final class SpaceCleanupGate {
    var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func suspend() async {
        entered = true
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor private final class ScopedScreenSourceDouble {
    var owner: UUID?
    var gate: SpaceCleanupGate?
    private(set) var cancellations: [UUID?] = []
    func cancel(requestID: UUID? = nil) async {
        cancellations.append(requestID)
        if let gate { await gate.suspend() }
        if requestID == nil || owner == requestID { owner = nil }
    }
}

@MainActor private final class AppEnvironment {
    fileprivate var activeAssistantRequestID: UUID?
    var currentInteractionID: UUID? { activeAssistantRequestID }
    var presentedScreenGuidance: SpatialReference?
    var presentedScreenMetadata: ScreenContextMetadata?
    let screenSource = ScopedScreenSourceDouble()
    var voiceSessionID = UUID()
    var pendingActionID = UUID()
    var state = "listening"

    // PRODUCTION_SCOPED_CLEANUP

    func seed(_ owner: UUID, context: ScreenContextMetadata, reference: SpatialReference) {
        activeAssistantRequestID = owner
        presentedScreenMetadata = context
        presentedScreenGuidance = reference
        screenSource.owner = owner
    }
}

@MainActor private final class MacGlobalInvocationController {
    let environment: AppEnvironment
    let guidance = MacGuidanceOverlay()
    var running = true
    var observationGeneration = UUID()
    var workspaceObservers: [NSObjectProtocol] = []
    let center = GuidanceNotificationCenter()
    private(set) var panelUpdates = 0
    init(environment: AppEnvironment) { self.environment = environment; installSpaceObserver() }
    private func updatePanel() { panelUpdates += 1 }

    // PRODUCTION_SPACE_HANDLER

    func installSpaceObserver() {
        let center = self.center
        let generation = observationGeneration
        // PRODUCTION_SPACE_OBSERVER
    }
}

@main @MainActor private struct CompanionSpaceChecks {
    static var passed = 0
    static var failed = 0
    static func check(_ value: Bool, _ label: String) {
        print("\(value ? "PASS" : "FAIL") \(label)")
        if value { passed += 1 } else { failed += 1 }
    }
    static func drain() async {
        for _ in 0..<12 { await Task.yield() }
    }
    static func main() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first, let display = MacScreenContextSource.geometry(for: screen) else {
            print("FAIL native guidance checks require an available Mac display")
            exit(1)
        }
        let prior = Set(NSApp.windows.map(ObjectIdentifier.init))
        func visibleMarkers() -> [NSWindow] {
            NSApp.windows.filter { $0 is NSPanel && !prior.contains(ObjectIdentifier($0)) && $0.isVisible }
        }
        func fixture(_ owner: UUID) -> (ScreenContextMetadata, SpatialReference) {
            (.init(requestID: owner, capturedAt: .now, display: display, pixelWidth: 1_000,
                   pixelHeight: 800, activeApplicationPID: 123),
             .init(requestID: owner, displayID: display.displayID, normalizedX: 0.5,
                   normalizedY: 0.5, label: "Disposable Space check", confidence: 1))
        }

        let marker = MacGuidanceOverlay()
        let first = UUID(), second = UUID()
        let (contextA, pointA) = fixture(first)
        let (contextB, pointB) = fixture(second)
        check(marker.show(reference: pointA, context: contextA, currentRequestID: first)
              && visibleMarkers().count == 1, "real native guidance panel opens for one validated request")
        let oldSpaceCallback = GuidanceSystemDouble.workspaceCenter.registrations.last {
            $0.name == NSWorkspace.activeSpaceDidChangeNotification
        }
        check(oldSpaceCallback != nil, "actual guidance lifecycle registers the public Space-change notification")
        GuidanceSystemDouble.workspaceCenter.post(NSWorkspace.activeSpaceDidChangeNotification)
        check(visibleMarkers().isEmpty && GuidanceSystemDouble.workspaceCenter.liveCount == 0
              && GuidanceSystemDouble.applicationCenter.liveCount == 0,
              "Space change synchronously closes guidance and retires all its observers")
        check(!marker.show(reference: pointA, context: contextA, currentRequestID: first),
              "retired evidence cannot redisplay its guidance after changing Spaces")
        check(marker.show(reference: pointB, context: contextB, currentRequestID: second),
              "a new request can display new guidance after the old Space retires")
        oldSpaceCallback?.callback(.init(name: NSWorkspace.activeSpaceDidChangeNotification))
        check(visibleMarkers().count == 1,
              "late callback registered for an older reference cannot close newer guidance")
        let oldDisplayCallback = GuidanceSystemDouble.applicationCenter.registrations.last
        marker.dismiss()
        let third = UUID()
        // Use one exact owner for both fields and the public call.
        let (currentContext, currentPoint) = fixture(third)
        check(marker.show(reference: currentPoint, context: currentContext, currentRequestID: third),
              "replacement guidance remains usable after an explicit dismissal")
        oldDisplayCallback?.callback(.init(name: NSApplication.didChangeScreenParametersNotification))
        check(visibleMarkers().count == 1, "old display callback cannot dismiss a replacement native marker")
        marker.dismiss()

        let environment = AppEnvironment()
        let controller = MacGlobalInvocationController(environment: environment)
        environment.seed(first, context: contextA, reference: pointA)
        _ = controller.guidance.show(reference: pointA, context: contextA, currentRequestID: first)
        let voice = environment.voiceSessionID, action = environment.pendingActionID
        controller.center.post(NSWorkspace.activeSpaceDidChangeNotification)
        check(visibleMarkers().isEmpty && controller.panelUpdates == 1,
              "controller Space event synchronously retires the marker before asynchronous cleanup")
        await drain()
        check(environment.presentedScreenMetadata == nil && environment.presentedScreenGuidance == nil
              && environment.screenSource.cancellations == [first],
              "owned Space cleanup clears metadata and cancels only its original screen request")
        check(environment.voiceSessionID == voice && environment.pendingActionID == action
              && environment.state == "listening" && environment.currentInteractionID == first,
              "Space invalidation keeps voice, assistant, action and interaction ownership")

        let oldOwner = UUID(), newOwner = UUID()
        let (oldContext, oldPoint) = fixture(oldOwner), (newContext, newPoint) = fixture(newOwner)
        environment.seed(oldOwner, context: oldContext, reference: oldPoint)
        let countBefore = environment.screenSource.cancellations.count
        controller.center.post(NSWorkspace.activeSpaceDidChangeNotification)
        environment.seed(newOwner, context: newContext, reference: newPoint)
        await drain()
        check(environment.presentedScreenMetadata == newContext && environment.presentedScreenGuidance == newPoint
              && environment.screenSource.owner == newOwner && environment.screenSource.cancellations.count == countBefore,
              "queued old Space cleanup cannot erase a superseding request or capture")

        let generationCallback = controller.center.registrations.last
        controller.observationGeneration = UUID()
        _ = controller.guidance.show(reference: newPoint, context: newContext, currentRequestID: newOwner)
        generationCallback?.callback(.init(name: NSWorkspace.activeSpaceDidChangeNotification))
        check(visibleMarkers().count == 1 && environment.presentedScreenMetadata == newContext,
              "queued observer from an old controller generation cannot retire new guidance")
        controller.guidance.dismiss()
        controller.installSpaceObserver()
        let updatesBeforeRestart = controller.panelUpdates
        controller.center.post(NSWorkspace.activeSpaceDidChangeNotification)
        controller.observationGeneration = UUID()
        await drain()
        check(controller.panelUpdates == updatesBeforeRestart + 1
              && environment.presentedScreenMetadata == newContext,
              "generation change between event and cleanup prevents old cleanup and panel refresh")
        controller.installSpaceObserver()

        let gate = SpaceCleanupGate()
        environment.screenSource.gate = gate
        environment.seed(oldOwner, context: oldContext, reference: oldPoint)
        controller.center.post(NSWorkspace.activeSpaceDidChangeNotification)
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !gate.entered && ContinuousClock.now < deadline { await Task.yield() }
        check(gate.entered && environment.presentedScreenMetadata == nil,
              "request metadata retires before a suspended source cancellation")
        environment.seed(newOwner, context: newContext, reference: newPoint)
        let updatesAtReplacement = controller.panelUpdates
        gate.release()
        await drain()
        check(environment.screenSource.owner == newOwner && environment.presentedScreenMetadata == newContext
              && environment.presentedScreenGuidance == newPoint
              && environment.screenSource.cancellations.last == oldOwner,
              "suspended original cancellation cannot destroy the new capture or metadata")
        check(controller.panelUpdates == updatesAtReplacement,
              "late cleanup cannot refresh the new owner's panel after its await")
        environment.screenSource.gate = nil

        let cancellationsBeforeForeign = environment.screenSource.cancellations.count
        await environment.invalidateScreenContext(requestID: UUID())
        check(environment.presentedScreenMetadata == newContext && environment.screenSource.owner == newOwner
              && environment.screenSource.cancellations.count == cancellationsBeforeForeign,
              "scoped production boundary rejects foreign owners before clearing or cancelling")

        environment.activeAssistantRequestID = nil
        controller.center.post(NSWorkspace.activeSpaceDidChangeNotification)
        environment.seed(third, context: currentContext, reference: currentPoint)
        await drain()
        check(environment.presentedScreenMetadata == currentContext && environment.screenSource.owner == third
              && environment.screenSource.cancellations.count == cancellationsBeforeForeign,
              "ownerless Space event cannot later clear a newly started request")
        controller.guidance.dismiss()
        marker.dismiss()
        check(visibleMarkers().isEmpty && GuidanceSystemDouble.workspaceCenter.liveCount == 0
              && GuidanceSystemDouble.applicationCenter.liveCount == 0,
              "all native panels and guidance lifecycle observers finish retired")
        print("Companion Space checks: \(passed) passed / \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
