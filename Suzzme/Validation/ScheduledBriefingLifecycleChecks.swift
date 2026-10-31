import AppKit
import Foundation
import Observation

// These two stand-ins expose only the actual controller's environment seam.
// Its scheduler, store, clock handling and notification observers are production code.
struct ProactivePreferences {
    var dailyBriefingEnabled = true
    var briefingHour = 0
    var briefingMinute = 0
}

@MainActor @Observable final class AppEnvironment {
    var proactivePreferences = ProactivePreferences()
    let scheduledBriefing: ScheduledBriefingEngine
    private(set) var loadReturned = false
    @ObservationIgnored private let load: @MainActor () async -> Void

    init(engine: ScheduledBriefingEngine, load: @escaping @MainActor () async -> Void = {}) {
        scheduledBriefing = engine
        self.load = load
    }

    func loadProactiveState() async {
        await load()
        loadReturned = true
    }
}

@MainActor private final class LifecycleClock {
    var date: Date
    init() {
        date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12))!
    }
}

@MainActor private final class LifecycleLoadGate {
    private var entered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func load() async {
        entered = true
        entryWaiter?.resume(); entryWaiter = nil
        // Intentionally ignores task cancellation to exercise the controller's
        // generation check when an old initialization callback returns late.
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { entryWaiter = $0 } }
    }

    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}

@main @MainActor struct ScheduledBriefingLifecycleChecks {
    static var passed = 0
    static var failed = 0

    static func expect(_ value: Bool, _ message: String) {
        print("\(value ? "PASS" : "FAIL") \(message)")
        if value { passed += 1 } else { failed += 1 }
    }

    /// Yield only to process already-queued actor/Observation callbacks. No
    /// expected result depends on an elapsed timer or real notification delivery.
    static func settle(until condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }

    static func drainCallbacks() async {
        for _ in 0..<32 { await Task.yield() }
    }

    static func workspace(_ name: Notification.Name) {
        NSWorkspace.shared.notificationCenter.post(name: name, object: nil)
    }

    private static func makeEngine(_ root: URL, _ name: String, clock: LifecycleClock,
                           runner: @escaping @MainActor (ScheduledBriefingSlot) async throws -> ScheduledBriefingOutput) throws -> ScheduledBriefingEngine {
        let store = ScheduledBriefingStore(fileURL: root.appendingPathComponent(name + ".json"))
        _ = try store.setEnabled(true, now: clock.date)
        return ScheduledBriefingEngine(store: store, now: { clock.date },
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }, runner: runner)
    }

    static func wakeBeforeSession(_ root: URL) async throws {
        let clock = LifecycleClock()
        let gate = LifecycleLoadGate()
        var runs = 0
        let engine = try makeEngine(root, "wake-before-session", clock: clock) { _ in
            runs += 1
            return .init(generatedAt: clock.date)
        }
        let environment = AppEnvironment(engine: engine, load: { await gate.load() })
        let controller = MacScheduledBriefingController(environment: environment)
        await gate.waitUntilEntered()
        workspace(NSWorkspace.sessionDidResignActiveNotification)
        workspace(NSWorkspace.willSleepNotification)
        workspace(NSWorkspace.didWakeNotification)
        gate.release()
        expect(await settle { engine.enabled }, "controller finishes loading while the session remains inactive")
        await engine.waitForCurrentRun()
        expect(runs == 0 && !engine.isRunning && engine.nextRunAt == nil,
               "wake cannot resume source reads before the user session becomes active")
        NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
        await drainCallbacks()
        expect(runs == 0 && engine.nextRunAt == nil, "a clock event cannot unpause an inactive session")
        clock.date.addTimeInterval(61)
        workspace(NSWorkspace.sessionDidBecomeActiveNotification)
        await engine.waitForCurrentRun()
        expect(runs == 1 && engine.receipts.first?.state == .completed,
               "the missed summary runs after wake and session activation both complete")
        await controller.retire()
    }

    static func sessionBeforeWake(_ root: URL) async throws {
        let clock = LifecycleClock()
        let gate = LifecycleLoadGate()
        var runs = 0
        let engine = try makeEngine(root, "session-before-wake", clock: clock) { _ in
            runs += 1
            return .init(generatedAt: clock.date)
        }
        let environment = AppEnvironment(engine: engine, load: { await gate.load() })
        let controller = MacScheduledBriefingController(environment: environment)
        await gate.waitUntilEntered()
        workspace(NSWorkspace.willSleepNotification)
        workspace(NSWorkspace.sessionDidResignActiveNotification)
        workspace(NSWorkspace.sessionDidBecomeActiveNotification)
        gate.release()
        expect(await settle { engine.enabled }, "controller handles session activation arriving before wake")
        await engine.waitForCurrentRun()
        expect(runs == 0 && engine.nextRunAt == nil, "session activation alone cannot resume a sleeping worker")
        clock.date.addTimeInterval(61)
        workspace(NSWorkspace.didWakeNotification)
        await engine.waitForCurrentRun()
        expect(runs == 1 && engine.receipts.first?.state == .completed,
               "reverse lifecycle notification order resumes exactly one run")
        workspace(NSWorkspace.didWakeNotification)
        workspace(NSWorkspace.sessionDidBecomeActiveNotification)
        await engine.waitForCurrentRun()
        expect(runs == 1, "duplicate wake and activation events preserve the completed-day claim")
        await controller.retire()
    }

    static func stoppedCallbacks(_ root: URL) async throws {
        let clock = LifecycleClock()
        let gate = LifecycleLoadGate()
        var runs = 0
        let engine = try makeEngine(root, "stopped-initialization", clock: clock) { _ in
            runs += 1
            return .init(generatedAt: clock.date)
        }
        let environment = AppEnvironment(engine: engine, load: { await gate.load() })
        let controller = MacScheduledBriefingController(environment: environment)
        await gate.waitUntilEntered()
        controller.stop()
        gate.release()
        expect(await settle { environment.loadReturned }, "an uncooperative initialization callback returns after stop")
        await drainCallbacks()
        expect(!engine.enabled && runs == 0 && engine.receipts.isEmpty && engine.nextRunAt == nil,
               "a stopped controller rejects late initialization instead of starting the worker")
        environment.proactivePreferences.briefingHour = 1
        workspace(NSWorkspace.didWakeNotification)
        workspace(NSWorkspace.sessionDidBecomeActiveNotification)
        NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
        await drainCallbacks()
        expect(runs == 0 && engine.nextRunAt == nil, "stopped observers cannot revive work from later notifications")
        await controller.retire()
    }

    static func noWindowAndClockChecks(_ root: URL) async throws {
        let clock = LifecycleClock()
        var runs = 0
        let engine = try makeEngine(root, "windowless", clock: clock) { _ in
            runs += 1
            return .init(generatedAt: clock.date)
        }
        let environment = AppEnvironment(engine: engine)
        let controller = MacScheduledBriefingController(environment: environment)
        expect(await settle { engine.enabled }, "the app-lifetime adapter starts without a window scene")
        await engine.waitForCurrentRun()
        expect((NSApp?.windows.isEmpty ?? true) && runs == 1,
               "scheduled work completes with no Home or other app windows")
        clock.date = Calendar.current.date(byAdding: .day, value: 1, to: clock.date)!
        NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
        await engine.waitForCurrentRun()
        expect(runs == 2, "a clock-change notification rechecks today's missed slot")
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await engine.waitForCurrentRun()
        expect(runs == 2, "timezone reconciliation cannot repeat the already-completed current slot")

        environment.proactivePreferences.briefingHour = 13
        let schedule = ScheduledBriefingSchedule(hour: 13, minute: 0)
        let expectedDeadline = schedule.slot(on: clock.date).scheduledAt
        expect(await settle { engine.nextRunAt == expectedDeadline },
               "an observed Preferred Time change updates the existing worker's deadline")
        environment.proactivePreferences.briefingHour = 14
        controller.stop() // The preference observer has queued, but cannot run yet.
        await drainCallbacks()
        expect(engine.nextRunAt == nil && runs == 2,
               "a queued preference callback cannot arm a deadline after controller stop")
        await controller.retire()
    }

    static func main() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("suzzme-scheduled-lifecycle-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try await wakeBeforeSession(root)
            try await sessionBeforeWake(root)
            try await stoppedCallbacks(root)
            try await noWindowAndClockChecks(root)
        } catch {
            expect(false, "fixture setup failed: \(error)")
        }
        print("Scheduled briefing lifecycle: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
