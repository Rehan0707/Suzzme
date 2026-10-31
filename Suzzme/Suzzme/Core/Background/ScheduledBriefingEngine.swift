import Foundation
import Observation

/// App-lifetime, read-only job orchestration. This state describes receipts;
/// the existing assistant and voice lifecycle remain owned by AppEnvironment.
@MainActor @Observable final class ScheduledBriefingEngine {
    private(set) var enabled = false
    private(set) var isRunning = false
    private(set) var isStopping = false
    private(set) var receipts: [ScheduledBriefingReceipt] = []
    private(set) var nextRunAt: Date?
    private var preparationErrorMessage: String?
    @ObservationIgnored private let store: ScheduledBriefingStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: (TimeInterval) async throws -> Void
    @ObservationIgnored private let runner: @MainActor (ScheduledBriefingSlot) async throws -> ScheduledBriefingOutput
    @ObservationIgnored private var schedule: ScheduledBriefingSchedule?
    private var dailySummaryEnabled = false
    private var started = false
    private var paused = false
    private var disableRequested = false
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var activeReceipt: ScheduledBriefingReceipt?

    var readiness: ScheduledBriefingReadiness {
        if !started { return .notRunning }
        if paused { return .paused }
        return dailySummaryEnabled ? .ready : .dailySummaryOff
    }

    /// An unsaved off request still pauses automatic work for this session.
    var automaticPreparationEnabled: Bool { enabled && !disableRequested }

    /// A successful manual preparation cannot clear an unsaved off preference.
    var errorMessage: String? {
        guard enabled && disableRequested else { return preparationErrorMessage }
        let warning = "Automatic preparation is paused for this session. The off setting could not be saved and may remain on after relaunch. Use Save Off Setting Again to retry."
        return preparationErrorMessage.map { $0 + " " + warning } ?? warning
    }

    var canRunNow: Bool { readiness == .ready && schedule != nil && !isRunning }

    var currentReceipt: ScheduledBriefingReceipt? {
        guard isRunning, let activeReceipt else { return nil }
        return receipts.first { $0.id == activeReceipt.id } ?? activeReceipt
    }

    func isRetryScheduled(for receipt: ScheduledBriefingReceipt) -> Bool {
        guard readiness == .ready, automaticPreparationEnabled, !isRunning,
              receipt.slot.manualRequestID == nil,
              [.deferred, .interrupted].contains(receipt.state),
              receipt.attempt < ScheduledBriefingStore.maximumAttempts,
              let retryAt = receipt.retryAt, nextRunAt == retryAt,
              let schedule, schedule.slot(on: now()).key == receipt.slot.key else { return false }
        return true
    }

    /// Presence reads the same live owner and armed retry as Background Tasks.
    /// Old running receipts and old-day failures are history, not live activity.
    func activity(currentSummaryID: UUID?, hasCompletionNotice: Bool) -> ScheduledBriefingActivity? {
        guard readiness == .ready else { return nil }
        if let receipt = currentReceipt {
            return .init(id: receipt.id, state: receipt.state, isRunning: true,
                         isStopping: isStopping, retryAt: nil, summaryID: nil,
                         finishedAt: receipt.finishedAt)
        }
        // A newer manual receipt does not retire an automatic slot's deadline.
        // The armed retry is live work and takes priority over recent results.
        if let receipt = receipts.first(where: { isRetryScheduled(for: $0) }) {
            return .init(id: receipt.id, state: receipt.state, isRunning: false,
                         isStopping: false, retryAt: receipt.retryAt, summaryID: nil,
                         finishedAt: receipt.finishedAt)
        }
        guard let receipt = receipts.first else { return nil }
        let summaryID = receipt.state == .completed && hasCompletionNotice
            && receipt.output?.briefingID == currentSummaryID ? currentSummaryID : nil
        let failedToday = receipt.state == .failed
            && receipt.slot.schedule.calendar.isDate(receipt.finishedAt ?? receipt.startedAt, inSameDayAs: now())
        guard summaryID != nil || failedToday else { return nil }
        return .init(id: receipt.id, state: receipt.state, isRunning: false,
                     isStopping: false, retryAt: nil,
                     summaryID: summaryID, finishedAt: receipt.finishedAt)
    }

    init(store: ScheduledBriefingStore = ScheduledBriefingStore(),
         now: @escaping () -> Date = Date.init,
         sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
         runner: @escaping @MainActor (ScheduledBriefingSlot) async throws -> ScheduledBriefingOutput) {
        self.store = store
        self.now = now
        self.sleep = sleep
        self.runner = runner
    }

    func start(schedule: ScheduledBriefingSchedule, dailySummaryEnabled: Bool) {
        started = true
        paused = false
        reconcile(schedule: schedule, dailySummaryEnabled: dailySummaryEnabled)
    }

    func reconcile(schedule: ScheduledBriefingSchedule, dailySummaryEnabled: Bool) {
        let changed = self.schedule != schedule || self.dailySummaryEnabled != dailySummaryEnabled
        self.schedule = schedule
        self.dailySummaryEnabled = dailySummaryEnabled
        if changed { cancelActive(as: .interrupted) }
        refresh()
    }

    func setEnabled(_ value: Bool) {
        if !value {
            // The user's stop intent takes effect even if saving preferences
            // fails. No late result or later timer may override that intent.
            disableRequested = true
            cancelActive(as: .cancelled)
        }
        do {
            publish(try store.setEnabled(value, now: now()))
            if value { disableRequested = false }
            preparationErrorMessage = nil
            refresh()
        } catch {
            storageFailed()
            if !value && enabled {
                preparationErrorMessage = nil
            }
        }
    }

    /// The Mac adapter pauses on sleep/session lock and resumes on wake.
    func pause() {
        paused = true
        cancelActive(as: .interrupted)
        deadlineTask?.cancel(); deadlineTask = nil
        nextRunAt = nil
    }

    func resume() {
        guard started else { return }
        paused = false
        refresh()
    }

    func stop() {
        started = false
        pause()
    }

    /// Cancelling a scheduled run retires that day's slot. The persisted
    /// schedule remains on; an explicit manual run can still be requested.
    func cancelCurrentRun() {
        cancelActive(as: .cancelled)
        refresh()
    }

    /// A transient surface may outlive the receipt its Stop button displayed.
    func cancelCurrentRun(receiptID: UUID) {
        guard activeReceipt?.id == receiptID, runTask != nil, !isStopping else { return }
        cancelCurrentRun()
    }

    /// Explicit manual work is allowed with scheduling off. Each tap receives
    /// a unique receipt; it does not consume or bypass the scheduled day's slot.
    /// The same runner gate prevents overlap with automatic work.
    func runNow() async {
        guard started, !paused, dailySummaryEnabled, let schedule else {
            preparationErrorMessage = "Enable Daily Summary before preparing it in the background."
            return
        }
        guard runTask == nil else { return }
        deadlineTask?.cancel(); deadlineTask = nil
        nextRunAt = nil
        do {
            let current = now()
            publish(try store.load(now: current))
            let slot = ScheduledBriefingSlot.manual(schedule: schedule, now: current)
            guard let receipt = try store.claim(slot, now: current) else { return }
            publish(try store.load(now: current))
            begin(receipt)
            await waitForCurrentRun()
        } catch { storageFailed() }
    }

    /// Cancellation is cooperative. A retiring adapter may await the owned
    /// runner; the engine keeps its gate closed until that runner has returned.
    func waitForCurrentRun() async { await runTask?.value }

    /// Recheck with the current clock after a wall-clock or timezone event.
    func refresh() {
        deadlineTask?.cancel(); deadlineTask = nil
        nextRunAt = nil
        do {
            publish(try store.load(now: now()))
            guard started, !paused, !disableRequested, enabled, dailySummaryEnabled, let schedule, runTask == nil else { return }
            let current = now()
            let today = schedule.slot(on: current)
            guard today.scheduledAt <= current else { arm(at: today.scheduledAt); return }
            let previous = receipts.first { $0.slot.key == today.key }
            if let previous {
                if previous.state == .completed || previous.state == .failed || previous.state == .cancelled
                    || previous.attempt >= ScheduledBriefingStore.maximumAttempts {
                    arm(at: schedule.nextSlot(after: current).scheduledAt)
                    return
                }
                if let retryAt = previous.retryAt, retryAt > current { arm(at: retryAt); return }
            }
            guard let receipt = try store.claim(today, now: current) else {
                arm(at: schedule.nextSlot(after: current).scheduledAt)
                return
            }
            publish(try store.load(now: current))
            begin(receipt)
        } catch { storageFailed() }
    }

    private func begin(_ receipt: ScheduledBriefingReceipt) {
        let owner = revision
        activeReceipt = receipt
        isRunning = true
        isStopping = false
        let runner = runner
        runTask = Task { @MainActor [weak self] in
            do {
                try Task.checkCancellation()
                let output = try await runner(receipt.slot)
                guard let self, self.owns(receipt, revision: owner), !Task.isCancelled else {
                    self?.retire(receipt)
                    return
                }
                self.publish(try self.store.finish(id: receipt.id, state: .completed, now: self.now(), output: output))
                self.preparationErrorMessage = nil
                self.retire(receipt)
            } catch {
                guard let self else { return }
                if self.owns(receipt, revision: owner), !Task.isCancelled {
                    let busy = (error as? ScheduledBriefingRunError) == .busy
                    let canRetry = receipt.slot.manualRequestID == nil && receipt.attempt < ScheduledBriefingStore.maximumAttempts
                    let status: ScheduledBriefingReceiptState = error is CancellationError ? .interrupted
                        : busy && canRetry ? .deferred : .failed
                    do {
                        self.publish(try self.store.finish(id: receipt.id, state: status, now: self.now()))
                        self.preparationErrorMessage = status == .failed
                            ? busy ? (receipt.slot.manualRequestID == nil
                                ? "Suzzme stayed busy, so automatic preparation stopped for today. Prepare the summary again when the current request finishes."
                                : "Suzzme is busy. Prepare the summary again when the current request finishes.")
                                : "The background summary could not be prepared. Open Daily Summary to try again."
                            : nil
                    } catch { self.storageFailed() }
                }
                self.retire(receipt)
            }
        }
    }

    private func owns(_ receipt: ScheduledBriefingReceipt, revision owner: Int) -> Bool {
        started && !paused && (enabled || receipt.slot.manualRequestID != nil)
            && dailySummaryEnabled && revision == owner && activeReceipt?.id == receipt.id
    }

    private func retire(_ receipt: ScheduledBriefingReceipt) {
        guard activeReceipt?.id == receipt.id else { return }
        activeReceipt = nil
        isRunning = false
        isStopping = false
        runTask = nil
        refresh()
    }

    private func cancelActive(as status: ScheduledBriefingReceiptState) {
        revision += 1
        if runTask != nil { isStopping = true }
        if let activeReceipt {
            do { publish(try store.finish(id: activeReceipt.id, state: status, now: now())) }
            catch { storageFailed() }
        }
        // Keep the task handle until the runner returns. A provider that ignores
        // cancellation cannot overlap a new run or publish a late success.
        runTask?.cancel()
    }

    private func arm(at date: Date) {
        nextRunAt = date
        let owner = revision
        let sleep = sleep
        let interval = max(1, date.timeIntervalSince(now()))
        deadlineTask = Task { @MainActor [weak self] in
            do { try await sleep(interval) }
            catch { return }
            guard let self, self.revision == owner, !Task.isCancelled else { return }
            self.deadlineTask = nil
            self.refresh()
        }
    }

    private func publish(_ value: ScheduledBriefingStoredState) {
        enabled = value.enabled
        receipts = value.receipts
    }

    private func storageFailed() {
        deadlineTask?.cancel(); deadlineTask = nil
        nextRunAt = nil
        preparationErrorMessage = "Background summary history could not be saved. Your source information has not changed."
    }

    isolated deinit {
        deadlineTask?.cancel()
        runTask?.cancel()
    }
}
