import Foundation
import Observation

@MainActor private final class BackgroundTaskTestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@MainActor private final class BackgroundTaskGate {
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

private final class BackgroundTaskObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func mark() { lock.lock(); fired = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return fired }
}

/// Uses the shipping engine and store with controlled time and continuations.
/// Checks the UI authority surface, rather than mirroring its implementation.
@main @MainActor struct BackgroundTasksChecks {
    private static var passed = 0
    private static var failed = 0
    private static let schedule = ScheduledBriefingSchedule(hour: 8, minute: 0, timeZoneIdentifier: "Asia/Kolkata")
    private static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private static func expect(_ value: Bool, _ message: String) {
        print("\(value ? "PASS" : "FAIL") \(message)")
        if value { passed += 1 } else { failed += 1 }
    }
    private static func engine(_ root: URL, _ name: String, _ clock: BackgroundTaskTestClock,
        runner: @escaping @MainActor (ScheduledBriefingSlot) async throws -> ScheduledBriefingOutput) -> ScheduledBriefingEngine {
        .init(store: .init(fileURL: root.appendingPathComponent(name + ".json")), now: { clock.date },
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }, runner: runner)
    }

    private static func readiness(_ root: URL) async {
        let clock = BackgroundTaskTestClock(date("2026-10-23T01:00:00Z"))
        var runs = 0
        let worker = engine(root, "readiness", clock) { _ in
            runs += 1
            return .init(generatedAt: clock.date)
        }
        expect(worker.readiness == .notRunning && !worker.canRunNow && !worker.automaticPreparationEnabled,
            "a view cannot offer preparation before the app-owned scheduler starts")
        expect(worker.currentReceipt == nil && !worker.isStopping, "an idle scheduler has no current receipt or stop transition")
        let startObservation = BackgroundTaskObservation()
        withObservationTracking { _ = worker.readiness } onChange: { startObservation.mark() }
        worker.start(schedule: schedule, dailySummaryEnabled: true)
        expect(startObservation.value && worker.readiness == .ready, "starting invalidates an observed readiness projection")
        expect(worker.canRunNow && !worker.enabled, "explicit preparation stays available while automatic preparation is off")
        let pauseObservation = BackgroundTaskObservation()
        withObservationTracking { _ = worker.readiness; _ = worker.canRunNow } onChange: { pauseObservation.mark() }
        worker.pause()
        expect(pauseObservation.value && worker.readiness == .paused && !worker.canRunNow,
            "pause invalidates the view and blocks its preparation control")
        await worker.runNow()
        expect(runs == 0, "an invocation from a stale control cannot run while paused")
        worker.resume()
        expect(worker.readiness == .ready && worker.canRunNow, "resuming restores the explicit preparation control")
        worker.reconcile(schedule: schedule, dailySummaryEnabled: false)
        expect(worker.readiness == .dailySummaryOff && !worker.canRunNow, "Daily Summary off has its own readiness and blocks preparation")
        worker.reconcile(schedule: schedule, dailySummaryEnabled: true)
        await worker.runNow()
        expect(runs == 1 && worker.receipts.first?.state == .completed && worker.canRunNow,
            "the same engine serves a successful explicit preparation and restores its control")
        worker.stop()
        expect(worker.readiness == .notRunning && !worker.canRunNow, "stopped app ownership is distinct from a sleeping Mac")
    }

    private static func stopping(_ root: URL) async {
        let clock = BackgroundTaskTestClock(date("2026-10-23T01:00:00Z"))
        let gate = BackgroundTaskGate()
        var runs = 0
        let worker = engine(root, "stopping", clock) { _ in
            runs += 1
            await gate.run() // Deliberately ignores cancellation until released.
            return .init(generatedAt: clock.date, itemCount: 9)
        }
        worker.start(schedule: schedule, dailySummaryEnabled: true)
        let manual = Task { @MainActor in await worker.runNow() }
        await gate.waitUntilEntered()
        let owner = worker.currentReceipt?.id
        expect(worker.isRunning && !worker.isStopping && worker.currentReceipt?.state == .running && !worker.canRunNow,
            "a real owned preparation exposes its running receipt and disables duplicate preparation")
        let stoppingObservation = BackgroundTaskObservation()
        withObservationTracking { _ = worker.isStopping; _ = worker.currentReceipt } onChange: { stoppingObservation.mark() }
        worker.cancelCurrentRun()
        expect(stoppingObservation.value && worker.isStopping && worker.isRunning && !worker.canRunNow,
            "Stop immediately publishes a stopping transition while the cancelled runner drains")
        expect(worker.currentReceipt?.id == owner && worker.currentReceipt?.state == .cancelled,
            "the current receipt reflects durable cancellation instead of stale running metadata")
        await worker.runNow()
        expect(runs == 1 && worker.isStopping, "a repeated prepare action cannot overlap a stopping runner")
        gate.release()
        await manual.value
        expect(!worker.isRunning && !worker.isStopping && worker.currentReceipt == nil && worker.canRunNow,
            "the preparation control returns only after the stopped runner actually retires")
        expect(worker.receipts.first?.state == .cancelled && worker.receipts.first?.output == nil,
            "a cancelled runner's late output does not turn task history into a completed summary")
        worker.stop()
    }

    private static func failedDisable(_ root: URL) async {
        let clock = BackgroundTaskTestClock(date("2026-10-23T03:00:00Z"))
        let gate = BackgroundTaskGate()
        var failWrites = false
        var runs = 0
        let file = root.appendingPathComponent("failed-disable.json")
        let store = ScheduledBriefingStore(fileURL: file, write: { data, url in
            if failWrites { throw ScheduledBriefingStorageError.unavailable }
            try RecoverableJSONFile.write(data, to: url)
        })
        let worker = ScheduledBriefingEngine(store: store, now: { clock.date },
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }, runner: { _ in
                runs += 1
                if runs == 1 { await gate.run() }
                return .init(generatedAt: clock.date)
            })
        worker.start(schedule: schedule, dailySummaryEnabled: true)
        worker.setEnabled(true)
        await gate.waitUntilEntered()
        expect(worker.automaticPreparationEnabled && worker.currentReceipt?.state == .running,
            "automatic controls reflect effective authority during an automatic run")
        failWrites = true
        worker.setEnabled(false)
        expect(worker.enabled && !worker.automaticPreparationEnabled,
            "failed saving never makes the toggle claim automatic work remains enabled for this session")
        expect(worker.isStopping && !worker.canRunNow && worker.nextRunAt == nil,
            "failed cancellation persistence still exposes stopping and prevents overlapping preparation")
        expect(worker.errorMessage?.contains("after relaunch") == true,
            "failed-disable feedback explains that the durable setting may remain on after relaunch")
        gate.release()
        await worker.waitForCurrentRun()
        failWrites = false
        worker.refresh()
        expect(!worker.automaticPreparationEnabled && worker.nextRunAt == nil,
            "refresh cannot reinstate automatic scheduling after a failed disable save")
        await worker.runNow()
        expect(runs == 2 && worker.receipts.first?.slot.manualRequestID != nil && worker.receipts.first?.state == .completed,
            "an explicit preparation can complete while an automatic off preference awaits saving")
        expect(worker.enabled && !worker.automaticPreparationEnabled && worker.nextRunAt == nil
            && worker.errorMessage?.contains("after relaunch") == true
            && worker.errorMessage?.contains("Save Off Setting Again") == true,
            "manual success retains unsaved-off recovery feedback and cannot restore automatic authority")
        worker.setEnabled(false)
        let reloaded = try? ScheduledBriefingStore(fileURL: file).load(now: clock.date)
        expect(!worker.enabled && !worker.automaticPreparationEnabled && reloaded?.enabled == false,
            "retrying the off save directly persists off without re-enabling automatic work")
        expect(runs == 2 && !worker.isRunning && worker.nextRunAt == nil && worker.errorMessage == nil,
            "successful off-save recovery clears its warning and dispatches no additional worker")
        worker.stop()
    }

    private static func retryAuthority(_ root: URL) async {
        let clock = BackgroundTaskTestClock(date("2026-10-23T03:00:00Z"))
        let worker = engine(root, "retry", clock) { _ in throw ScheduledBriefingRunError.busy }
        worker.start(schedule: schedule, dailySummaryEnabled: true)
        worker.setEnabled(true)
        await worker.waitForCurrentRun()
        guard let receipt = worker.receipts.first else { expect(false, "a busy runner must have a durable receipt"); return }
        expect(receipt.state == .deferred && worker.isRetryScheduled(for: receipt),
            "only a genuinely armed current deferred receipt promises a retry")
        var unrelated = receipt
        unrelated.retryAt = receipt.retryAt?.addingTimeInterval(1)
        expect(!worker.isRetryScheduled(for: unrelated), "a receipt with another retry deadline cannot advertise the engine deadline")
        worker.pause()
        expect(!worker.isRetryScheduled(for: receipt), "a historical retry timestamp is not a retry promise while paused")
        worker.resume()
        expect(worker.isRetryScheduled(for: receipt), "resuming exposes the matching armed retry again")
        worker.setEnabled(false)
        expect(!worker.isRetryScheduled(for: receipt), "turning automatic preparation off removes the retry promise")
        worker.setEnabled(true)
        worker.reconcile(schedule: .init(hour: 10, minute: 0, timeZoneIdentifier: "Asia/Kolkata"), dailySummaryEnabled: true)
        expect(!worker.isRetryScheduled(for: receipt), "changing the preferred time does not promise a retry for the old schedule")
        clock.date.addTimeInterval(86_400)
        worker.refresh()
        await worker.waitForCurrentRun()
        expect(!worker.isRetryScheduled(for: receipt), "a prior day's retry metadata cannot masquerade as today's upcoming task")
        worker.stop()
    }

    private static func presentation() {
        let ready: (Bool, Bool, Bool) -> BackgroundPreparationStatus = { automatic, error, deadline in
            .init(readiness: .ready, isRunning: false, isStopping: false,
                automaticPreparationEnabled: automatic, hasError: error, hasNextRun: deadline)
        }
        expect(ready(false, false, false) == .automaticOff && ready(true, false, true) == .scheduled,
            "ready presentation distinguishes automatic off from a real scheduled deadline")
        expect(ready(true, false, false) == .automaticOn && ready(true, true, true) == .needsAttention,
            "automatic authority without a deadline makes no scheduled-time promise and errors stay visible")
        let stopping = BackgroundPreparationStatus(readiness: .paused, isRunning: true, isStopping: true,
            automaticPreparationEnabled: true, hasError: true, hasNextRun: false)
        expect(stopping == .stopping && stopping.showsProgress,
            "stopping takes precedence over paused, running and error presentation during cancellation drain")
        let preparing = BackgroundPreparationStatus(readiness: .ready, isRunning: true, isStopping: false,
            automaticPreparationEnabled: false, hasError: false, hasNextRun: false)
        expect(preparing == .preparing && preparing.showsProgress,
            "manual background work uses preparing progress even with automatic preparation off")
        for (readiness, expected) in [(ScheduledBriefingReadiness.notRunning, BackgroundPreparationStatus.notRunning),
                                     (.paused, .paused), (.dailySummaryOff, .dailySummaryOff)] {
            let value = BackgroundPreparationStatus(readiness: readiness, isRunning: false, isStopping: false,
                automaticPreparationEnabled: true, hasError: false, hasNextRun: true)
            expect(value == expected && !value.showsProgress, "\(readiness) cannot present a ready or scheduled worker")
        }
        let now = date("2026-10-23T03:00:00Z")
        let slot = schedule.slot(on: now)
        var receipt = ScheduledBriefingReceipt(id: UUID(), slot: slot, attempt: 1, startedAt: now,
            finishedAt: now.addingTimeInterval(10), state: .completed,
            output: .init(generatedAt: now.addingTimeInterval(5), itemCount: 0, sourceCount: 0))
        var value = BackgroundPreparationReceiptPresentation(receipt: receipt)
        expect(value.title == "Nothing new to summarize" && value.metadata == "0 items · 0 contributing sources",
            "healthy empty completion is distinct from unavailable sources")
        expect(value.date == receipt.output?.generatedAt && value.dateLabel == "Prepared",
            "completion rows use actual generated time rather than attempt or finish time")
        receipt.output = .init(generatedAt: now, limitationCount: 1)
        value = .init(receipt: receipt)
        expect(value.title == "Sources unavailable" && value.detail?.contains("Some information") == true,
            "limited completion without a briefing does not claim a summary was prepared")
        receipt.output = .init(generatedAt: now, briefingID: UUID(), itemCount: 1, sourceCount: 1)
        value = .init(receipt: receipt)
        expect(value.title == "Summary prepared" && value.metadata == "1 item · 1 contributing source",
            "ordinary completed receipt presents singular counts and a truthful result")
        receipt.output = .init(generatedAt: now, briefingID: UUID(), itemCount: 101, sourceCount: -1, limitationCount: 2)
        value = .init(receipt: receipt)
        expect(value.title == "Summary prepared with limited sources" && value.metadata == "100 items · 0 contributing sources",
            "the row presents bounded counts and calls out omitted information")
        for status in [ScheduledBriefingReceiptState.failed, .deferred, .interrupted, .cancelled] {
            receipt.state = status; receipt.output = nil
            value = .init(receipt: receipt)
            expect(value.metadata == nil && value.date == receipt.finishedAt && value.dateLabel == "Finished"
                && value.detail?.contains("Next attempt") != true,
                "\(status) row exposes attempt metadata without inventing a result or retry promise")
        }
        let manual = ScheduledBriefingReceipt(id: UUID(), slot: .manual(schedule: schedule, now: now), attempt: 1,
            startedAt: now, state: .running)
        value = .init(receipt: manual)
        expect(value.mode == "Requested by you" && value.date == now && value.dateLabel == "Started",
            "manual receipt is identified by origin and running attempt time")
        let visible = [value.title, value.symbol, value.mode, value.dateLabel, value.detail ?? "", value.metadata ?? ""].joined(separator: " ")
        expect(!visible.contains(manual.id.uuidString) && !visible.contains(manual.slot.key)
            && !visible.contains(manual.slot.manualRequestID!.uuidString),
            "visible receipt content never exposes request IDs or storage keys")
        expect(value.title == "Unfinished preparation" && value.detail?.contains("No completed result") == true,
            "a historical running receipt cannot claim preparation is still actively running")
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BackgroundTasksChecks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        await readiness(root)
        await stopping(root)
        await failedDisable(root)
        await retryAuthority(root)
        presentation()
        print("Background Tasks checks: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
