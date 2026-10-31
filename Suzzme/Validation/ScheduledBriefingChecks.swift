import Foundation

@MainActor private final class BriefingTestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@MainActor private final class BriefingRunnerGate {
    private var entered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var resultWaiter: CheckedContinuation<Void, Never>?
    func run() async {
        entered = true
        entryWaiter?.resume(); entryWaiter = nil
        await withCheckedContinuation { resultWaiter = $0 }
    }
    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { entryWaiter = $0 } }
    }
    func release() { resultWaiter?.resume(); resultWaiter = nil }
}

/// Controlled clocks and continuations decide ordering; no elapsed wall-clock
/// timer decides whether a cancelled runner is permitted to publish success.
@main @MainActor struct ScheduledBriefingChecks {
    static var passed = 0
    static var failed = 0
    static let schedule = ScheduledBriefingSchedule(hour: 8, minute: 0, timeZoneIdentifier: "Asia/Kolkata")

    static func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }
    static func expect(_ value: Bool, _ message: String) {
        print("\(value ? "PASS" : "FAIL") \(message)")
        if value { passed += 1 } else { failed += 1 }
    }
    static func store(_ root: URL, _ name: String) -> ScheduledBriefingStore {
        .init(fileURL: root.appendingPathComponent(name + ".json"))
    }
    private static func engine(_ store: ScheduledBriefingStore, _ clock: BriefingTestClock,
                       runner: @escaping @MainActor (ScheduledBriefingSlot) async throws -> ScheduledBriefingOutput) -> ScheduledBriefingEngine {
        .init(store: store, now: { clock.date }, sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }, runner: runner)
    }

    static func calendarChecks() {
        let india = schedule.slot(on: date("2026-10-22T05:00:00Z"))
        expect(india.scheduledAt == date("2026-10-22T02:30:00Z"), "daily slot uses the configured local time")
        let spring = ScheduledBriefingSchedule(hour: 2, minute: 30, timeZoneIdentifier: "America/New_York")
        let springSlot = spring.slot(on: date("2026-03-08T12:00:00Z"))
        expect(springSlot.scheduledAt == date("2026-03-08T07:00:00Z"), "missing DST time advances to the first valid time that day")
        let fall = ScheduledBriefingSchedule(hour: 1, minute: 30, timeZoneIdentifier: "America/New_York")
        expect(fall.slot(on: date("2026-11-01T12:00:00Z")).scheduledAt == date("2026-11-01T05:30:00Z"), "repeated DST time uses its first occurrence")
        expect(spring.nextSlot(after: date("2026-03-07T12:00:00Z")).localDay == springSlot.localDay, "next day follows calendar boundaries across DST")
    }

    static func dailyExecution(_ root: URL) async throws {
        let clock = BriefingTestClock(date("2026-10-22T05:00:00Z"))
        let file = root.appendingPathComponent("daily.json")
        let persistence = ScheduledBriefingStore(fileURL: file)
        var runs = 0
        var durableClaimObserved = false
        let worker = engine(persistence, clock) { slot in
            runs += 1
            let disk = try JSONDecoder().decode(ScheduledBriefingStoredState.self, from: Data(contentsOf: file))
            durableClaimObserved = disk.receipts.contains { $0.slot.key == slot.key && $0.state == .running }
            return .init(generatedAt: clock.date, briefingID: UUID(), itemCount: 2, sourceCount: 1, limitationCount: 1)
        }
        worker.start(schedule: schedule, dailySummaryEnabled: true)
        expect(!worker.enabled && runs == 0 && worker.nextRunAt == nil, "background generation is off by default")
        worker.setEnabled(true)
        await worker.waitForCurrentRun()
        expect(runs == 1 && durableClaimObserved, "today's missed slot runs only after its claim reaches disk")
        expect(worker.receipts.first?.state == .completed && worker.receipts.first?.output?.limitationCount == 1,
               "completed receipt stores bounded result and limitation counts")
        worker.refresh(); worker.refresh()
        await worker.waitForCurrentRun()
        expect(runs == 1, "repeated wake and refresh events do not repeat the completed slot")
        worker.stop()
        let restarted = engine(ScheduledBriefingStore(fileURL: file), clock) { _ in
            runs += 1
            return .init(generatedAt: clock.date)
        }
        restarted.start(schedule: schedule, dailySummaryEnabled: true)
        await restarted.waitForCurrentRun()
        expect(restarted.enabled && runs == 1, "enable preference and completed slot survive process restart")
        clock.date = date("2026-10-25T05:00:00Z")
        restarted.refresh()
        await restarted.waitForCurrentRun()
        expect(runs == 2 && restarted.receipts.first?.slot.localDay == schedule.slot(on: clock.date).localDay,
               "catch-up runs today once instead of replaying missed days")
        restarted.stop()
    }

    static func retries(_ root: URL) async {
        let clock = BriefingTestClock(date("2026-10-22T05:00:00Z"))
        var runs = 0
        let worker = engine(store(root, "busy"), clock) { _ in runs += 1; throw ScheduledBriefingRunError.busy }
        worker.start(schedule: schedule, dailySummaryEnabled: true)
        worker.setEnabled(true)
        await worker.waitForCurrentRun()
        expect(runs == 1 && worker.receipts.first?.state == .deferred, "busy foreground work is deferred")
        for _ in 0..<8 { worker.refresh() }
        expect(runs == 1 && worker.nextRunAt == clock.date.addingTimeInterval(60), "busy retry has a bounded delay instead of a polling loop")
        for _ in 0..<2 {
            clock.date.addTimeInterval(60)
            worker.refresh()
            await worker.waitForCurrentRun()
        }
        clock.date.addTimeInterval(600)
        worker.refresh()
        await worker.waitForCurrentRun()
        expect(runs == 3 && worker.receipts.first?.attempt == 3 && worker.receipts.first?.state == .failed
            && worker.errorMessage?.contains("stopped for today") == true
            && worker.nextRunAt == schedule.nextSlot(after: clock.date).scheduledAt,
               "three busy attempts end with an actionable failure and next-day deadline")
        worker.stop()
    }

    static func cancellation(_ root: URL) async {
        let clock = BriefingTestClock(date("2026-10-22T05:00:00Z"))
        let gate = BriefingRunnerGate()
        var runs = 0
        let worker = engine(store(root, "cancel"), clock) { _ in
            runs += 1
            await gate.run() // Deliberately ignores cancellation.
            return .init(generatedAt: clock.date, itemCount: 9)
        }
        worker.start(schedule: schedule, dailySummaryEnabled: true)
        worker.setEnabled(true)
        await gate.waitUntilEntered()
        worker.setEnabled(false)
        worker.setEnabled(true)
        worker.refresh()
        expect(runs == 1 && worker.isRunning && worker.receipts.first?.state == .cancelled,
               "disable retires receipt while an uncooperative runner keeps the single-run gate")
        gate.release()
        await worker.waitForCurrentRun()
        expect(!worker.isRunning && worker.receipts.first?.output == nil && worker.receipts.first?.state == .cancelled,
               "late success cannot resurrect a disabled job after re-enabling")
        worker.stop()

        let pauseGate = BriefingRunnerGate()
        let paused = engine(store(root, "pause"), clock) { _ in
            await pauseGate.run()
            return .init(generatedAt: clock.date)
        }
        paused.start(schedule: schedule, dailySummaryEnabled: true)
        paused.setEnabled(true)
        await pauseGate.waitUntilEntered()
        paused.pause()
        paused.resume()
        expect(paused.receipts.first?.state == .interrupted, "sleep or session lock records an interrupted run")
        pauseGate.release()
        await paused.waitForCurrentRun()
        expect(paused.receipts.first?.state == .interrupted && paused.nextRunAt == clock.date.addingTimeInterval(60),
               "wake schedules a delayed retry and rejects the pre-sleep result")
        paused.stop()
    }

    static func recoveryAndFailures(_ root: URL) async throws {
        let clock = BriefingTestClock(date("2026-10-22T05:00:00Z"))
        let file = root.appendingPathComponent("interrupted.json")
        let initial = ScheduledBriefingStore(fileURL: file)
        _ = try initial.setEnabled(true, now: clock.date)
        let claimed = try initial.claim(schedule.slot(on: clock.date), now: clock.date)
        let recovered = ScheduledBriefingStore(fileURL: file)
        let restored = try recovered.load(now: clock.date)
        expect(claimed != nil && restored.receipts.first?.state == .interrupted,
               "a durable running receipt becomes interrupted after restart")
        expect(try recovered.claim(schedule.slot(on: clock.date), now: clock.date) == nil,
               "recovered interruption respects retry delay")
        clock.date.addTimeInterval(60)
        expect(try recovered.claim(schedule.slot(on: clock.date), now: clock.date)?.attempt == 2,
               "recovery preserves attempt count when retrying")

        var runs = 0
        let failing = ScheduledBriefingStore(fileURL: root.appendingPathComponent("write-failure.json"),
            write: { _, _ in throw ScheduledBriefingStorageError.unavailable })
        let blocked = engine(failing, clock) { _ in runs += 1; return .init(generatedAt: clock.date) }
        blocked.start(schedule: schedule, dailySummaryEnabled: true)
        blocked.setEnabled(true)
        await blocked.runNow()
        expect(runs == 0 && blocked.errorMessage != nil && blocked.nextRunAt == nil,
               "a failed durable claim cannot dispatch automatic or manual work")
        blocked.stop()

        let futureFile = root.appendingPathComponent("future.json")
        let future = Data("{\"schemaVersion\":2,\"enabled\":true,\"receipts\":[]}".utf8)
        try future.write(to: futureFile)
        let futureWorker = engine(.init(fileURL: futureFile), clock) { _ in runs += 1; return .init(generatedAt: clock.date) }
        futureWorker.start(schedule: schedule, dailySummaryEnabled: true)
        futureWorker.setEnabled(true)
        let preservedFuture = try Data(contentsOf: futureFile)
        expect(runs == 0 && futureWorker.errorMessage != nil && preservedFuture == future,
               "future-version storage fails closed and preserves the original file")
        futureWorker.stop()
    }

    static func explicitCancellationAndFailedDisable(_ root: URL) async {
        let clock = BriefingTestClock(date("2026-10-22T05:00:00Z"))
        let gate = BriefingRunnerGate()
        var runs = 0
        let worker = engine(store(root, "explicit-cancel"), clock) { _ in
            runs += 1
            if runs == 1 { await gate.run() }
            return .init(generatedAt: clock.date)
        }
        worker.start(schedule: schedule, dailySummaryEnabled: true)
        worker.setEnabled(true)
        await gate.waitUntilEntered()
        worker.cancelCurrentRun()
        gate.release()
        await worker.waitForCurrentRun()
        worker.refresh()
        expect(worker.enabled && runs == 1 && worker.receipts.first?.state == .cancelled
            && worker.nextRunAt == schedule.nextSlot(after: clock.date).scheduledAt,
               "explicit cancellation preserves schedule but suppresses today's automatic slot")
        await worker.runNow()
        expect(runs == 2 && worker.receipts.first?.state == .completed
            && worker.receipts.first?.slot.manualRequestID != nil,
               "an explicitly cancelled day still allows a fresh manual request")
        worker.stop()

        let failureGate = BriefingRunnerGate()
        var writesFail = false
        var failureRuns = 0
        let persistence = ScheduledBriefingStore(fileURL: root.appendingPathComponent("failed-disable.json"), write: { data, url in
            if writesFail { throw ScheduledBriefingStorageError.unavailable }
            try RecoverableJSONFile.write(data, to: url)
        })
        let blocked = engine(persistence, clock) { _ in
            failureRuns += 1
            await failureGate.run()
            return .init(generatedAt: clock.date)
        }
        blocked.start(schedule: schedule, dailySummaryEnabled: true)
        blocked.setEnabled(true)
        await failureGate.waitUntilEntered()
        writesFail = true
        blocked.setEnabled(false)
        expect(blocked.errorMessage?.contains("paused for this session") == true
            && blocked.errorMessage?.contains("after relaunch") == true,
               "failed disable saving explains the session-only pause and retry requirement")
        failureGate.release()
        await blocked.waitForCurrentRun()
        writesFail = false
        clock.date.addTimeInterval(120)
        blocked.refresh()
        expect(failureRuns == 1 && blocked.receipts.first?.state != .completed && blocked.nextRunAt == nil,
               "failed preference persistence still honors the immediate disable intent and rejects late success")
        blocked.stop()
    }

    static func manualAndScheduleChanges(_ root: URL) async throws {
        let clock = BriefingTestClock(date("2026-10-22T00:00:00Z")) // Before the local schedule.
        var runs = 0
        let worker = engine(store(root, "manual"), clock) { _ in runs += 1; return .init(generatedAt: clock.date) }
        worker.start(schedule: schedule, dailySummaryEnabled: true)
        await worker.runNow()
        expect(runs == 1 && !worker.enabled && worker.receipts.first?.slot.manualRequestID != nil,
               "explicit manual preparation works while automatic scheduling is off")
        worker.setEnabled(true)
        expect(worker.nextRunAt == date("2026-10-22T02:30:00Z"), "manual preparation does not consume the automatic slot")
        clock.date = date("2026-10-22T05:00:00Z")
        worker.refresh()
        await worker.waitForCurrentRun()
        for _ in 0..<35 { await worker.runNow() }
        worker.refresh()
        await worker.waitForCurrentRun()
        expect(runs == 37 && worker.receipts.count <= ScheduledBriefingStore.maximumReceipts,
               "repeated manual checks retain bounded receipts without evicting today's scheduled completion")
        worker.reconcile(schedule: schedule, dailySummaryEnabled: false)
        await worker.runNow()
        expect(runs == 37 && worker.nextRunAt == nil, "Daily Summary off blocks manual and automatic generation")
        worker.stop()
        let text = String(decoding: try JSONEncoder().encode(worker.receipts), as: UTF8.self)
        expect(!text.contains("title") && !text.contains("summary") && !text.contains("narration"),
               "job history contains metadata and no copied source or response content")
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScheduledBriefingChecks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        calendarChecks()
        try await dailyExecution(root)
        await retries(root)
        await cancellation(root)
        try await recoveryAndFailures(root)
        await explicitCancellationAndFailedDisable(root)
        try await manualAndScheduleChanges(root)
        print("Scheduled briefing checks: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
