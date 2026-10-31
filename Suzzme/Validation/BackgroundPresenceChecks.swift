import AppKit
import Foundation
import SwiftUI

@MainActor private final class BackgroundPresenceClock {
    var date = ISO8601DateFormatter().date(from: "2026-10-23T03:00:00Z")!
}

@MainActor private final class BackgroundPresenceGate {
    private var entered = false
    private var entry: CheckedContinuation<Void, Never>?
    private var result: CheckedContinuation<Void, Never>?
    func run() async {
        entered = true; entry?.resume(); entry = nil
        await withCheckedContinuation { result = $0 }
    }
    func wait() async { if !entered { await withCheckedContinuation { entry = $0 } } }
    func release() { result?.resume(); result = nil }
    func reset() { precondition(result == nil); entered = false }
}

private struct BackgroundPresencePreferences { var dailyBriefingEnabled = true }
private struct BackgroundPresenceInvocation { var isActive = false }
private struct BackgroundPresenceVoice {
    var isListening = false, isFinalizing = false, isSpeaking = false, isPreparingSpeech = false
}
private struct BackgroundPresenceBrowserRequest {
    var current = true
    func isCurrent() -> Bool { current }
}
private struct BackgroundPresenceHandoff { var request: BackgroundPresenceBrowserRequest? }
private struct BackgroundPresenceIntegrations { var browserHandoff = BackgroundPresenceHandoff() }
private struct BackgroundPresenceSummary {
    enum Delivery { case ready, hidden }
    let id: UUID
    var deliveryState = Delivery.ready
}
private struct BackgroundPresenceSnapshot { var briefing: BackgroundPresenceSummary? }
@MainActor private final class BackgroundPresenceEnvironment {
    let scheduledBriefing: ScheduledBriefingEngine
    var proactivePreferences = BackgroundPresencePreferences()
    var presenceState = SuzzmeAssistantState.idle
    var currentInteractionID: UUID?, presentedAction: UUID?, screenConsentRequestID: UUID?, scheduledBriefingNoticeID: UUID?
    var presentedResponse: String?
    var invocation = BackgroundPresenceInvocation()
    var proactivePresenceSignal = SuzzmeProactivePresenceSignal.none
    var voice = BackgroundPresenceVoice()
    var integrations = BackgroundPresenceIntegrations()
    var proactiveSnapshot: BackgroundPresenceSnapshot?
    init(_ engine: ScheduledBriefingEngine) { scheduledBriefing = engine }
}
@MainActor private final class BackgroundPresenceOwner {
    let environment: BackgroundPresenceEnvironment
    var running = true
    var openBackgroundDestination: (() -> Void)? = {}
    var heldToken: UUID?
    var startTask: Task<Void, Never>?
    init(_ environment: BackgroundPresenceEnvironment) { self.environment = environment }
    func activity() -> ScheduledBriefingActivity? { backgroundActivityForPresentation() }
    // PRODUCTION_BACKGROUND_GATE
}

// This extension is compiled in the same file as the entire unmodified shipping
// panel owner, so tests inspect ownership without adding production test APIs.
extension MacAssistantPanelController {
    fileprivate var fixturePanel: NSPanel? { panel }
    fileprivate var fixtureActivity: ScheduledBriefingActivity? { visibleBackgroundActivity }
    fileprivate var fixtureHasDeadline: Bool { autoHideTask != nil }
    fileprivate var fixtureSurface: MacAssistantNotchSurface? {
        (panel?.contentView as? MacAssistantHostingView<MacAssistantNotchSurface>)?.rootView
    }
}

/// Production engine/store and real app-owned NSPanel resources. No source
/// adapter, model, microphone, screen capture, TCC request or user account runs.
@main @MainActor struct BackgroundPresenceChecks {
    private static var passed = 0
    private static var failed = 0
    private static let schedule = ScheduledBriefingSchedule(hour: 8, minute: 0, timeZoneIdentifier: "Asia/Kolkata")
    private static func expect(_ value: Bool, _ label: String) {
        print("\(value ? "PASS" : "FAIL") \(label)")
        if value { passed += 1 } else { failed += 1 }
    }
    private static func worker(_ root: URL, _ name: String, _ clock: BackgroundPresenceClock,
        runner: @escaping @MainActor (ScheduledBriefingSlot) async throws -> ScheduledBriefingOutput) -> ScheduledBriefingEngine {
        .init(store: .init(fileURL: root.appendingPathComponent(name + ".json")), now: { clock.date },
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }, runner: runner)
    }

    private static func running(_ root: URL) async {
        let clock = BackgroundPresenceClock(), gate = BackgroundPresenceGate()
        var runs = 0
        let engine = worker(root, "running", clock) { _ in
            runs += 1; await gate.run()
            return .init(generatedAt: clock.date, briefingID: UUID(), itemCount: 4)
        }
        expect(engine.activity(currentSummaryID: nil, hasCompletionNotice: false) == nil,
            "an unstarted worker cannot invent background activity")
        engine.start(schedule: schedule, dailySummaryEnabled: true)
        expect(engine.activity(currentSummaryID: nil, hasCompletionNotice: false) == nil,
            "an idle off schedule has no background presence")
        let request = Task { @MainActor in await engine.runNow() }
        await gate.wait()
        guard let activity = engine.activity(currentSummaryID: nil, hasCompletionNotice: false) else {
            expect(false, "a real running worker must publish its activity"); gate.release(); await request.value; return
        }
        expect(activity.id == engine.currentReceipt?.id && activity.isRunning && !activity.isStopping && activity.canStop,
            "manual preparation projects the actual current owner even with scheduling off")
        expect(activity.summaryID == nil && !activity.canOpenSummary && activity.retryAt == nil,
            "running metadata cannot manufacture a summary or a future retry")
        engine.cancelCurrentRun(receiptID: UUID())
        expect(!engine.isStopping && engine.currentReceipt?.state == .running,
            "a stale Stop callback cannot cancel the current preparation")
        engine.cancelCurrentRun(receiptID: activity.id)
        let stopping = engine.activity(currentSummaryID: nil, hasCompletionNotice: false)
        expect(stopping?.id == activity.id && stopping?.isStopping == true && stopping?.isRunning == true
            && stopping?.canStop == false, "the exact Stop owner remains visible while cancellation drains")
        await engine.runNow()
        expect(runs == 1 && !engine.canRunNow, "stopping presence never unlocks an overlapping worker")
        gate.release(); await request.value
        expect(engine.currentReceipt == nil && !engine.isRunning && engine.receipts.first?.state == .cancelled
            && engine.receipts.first?.output == nil, "late cancelled output cannot become a completion notice")
        expect(engine.activity(currentSummaryID: nil, hasCompletionNotice: true) == nil,
            "a cancelled receipt cannot claim completion even when an unrelated notice exists")
        gate.reset()
        let nextRequest = Task { @MainActor in await engine.runNow() }; await gate.wait()
        let newID = engine.currentReceipt?.id
        engine.cancelCurrentRun(receiptID: activity.id)
        expect(newID != nil && newID != activity.id && !engine.isStopping && runs == 2,
            "a prior card's Stop callback cannot cancel a later manual preparation")
        engine.cancelCurrentRun(receiptID: newID!)
        expect(engine.isStopping, "the later preparation still accepts its own Stop callback")
        gate.release(); await nextRequest.value
        engine.stop()
    }

    private static func retry(_ root: URL) async {
        let clock = BackgroundPresenceClock()
        let engine = worker(root, "retry", clock) { _ in throw ScheduledBriefingRunError.busy }
        engine.start(schedule: schedule, dailySummaryEnabled: true); engine.setEnabled(true)
        await engine.waitForCurrentRun()
        let value = engine.activity(currentSummaryID: nil, hasCompletionNotice: false)
        expect(value?.state == .deferred && value?.retryAt == engine.nextRunAt && value?.canStop == false,
            "a busy automatic run exposes only its actually armed retry deadline")
        engine.pause()
        expect(engine.activity(currentSummaryID: nil, hasCompletionNotice: false) == nil,
            "sleep/session pause hides historical retry metadata")
        engine.resume()
        expect(engine.activity(currentSummaryID: nil, hasCompletionNotice: false)?.id == value?.id,
            "resuming restores the same receipt only while its retry remains armed")
        engine.setEnabled(false)
        expect(engine.activity(currentSummaryID: nil, hasCompletionNotice: false) == nil,
            "automatic off removes the retry notice immediately")
        engine.setEnabled(true)
        engine.reconcile(schedule: .init(hour: 10, minute: 0, timeZoneIdentifier: "Asia/Kolkata"), dailySummaryEnabled: true)
        expect(engine.activity(currentSummaryID: nil, hasCompletionNotice: false) == nil,
            "changing the schedule cannot advertise a retry for the previous slot")
        engine.stop()
    }

    private static func completion(_ root: URL) async {
        let clock = BackgroundPresenceClock(), summaryID = UUID()
        let engine = worker(root, "completion", clock) { _ in
            .init(generatedAt: clock.date, briefingID: summaryID, itemCount: 2, sourceCount: 1)
        }
        engine.start(schedule: schedule, dailySummaryEnabled: true)
        await engine.runNow()
        expect(engine.activity(currentSummaryID: summaryID, hasCompletionNotice: false) == nil,
            "a stored completed receipt alone cannot create a new completion notice")
        expect(engine.activity(currentSummaryID: UUID(), hasCompletionNotice: true) == nil,
            "a historical receipt cannot open a different current summary")
        let ready = engine.activity(currentSummaryID: summaryID, hasCompletionNotice: true)
        expect(ready?.state == .completed && ready?.summaryID == summaryID && ready?.canOpenSummary == true
            && ready?.isRunning == false && ready?.canStop == false,
            "completion action requires the exact current summary and an existing notice")
        engine.reconcile(schedule: schedule, dailySummaryEnabled: false)
        expect(engine.activity(currentSummaryID: summaryID, hasCompletionNotice: true) == nil,
            "turning Daily Summary off suppresses completion presence")
        engine.stop()
        let empty = worker(root, "empty", clock) { _ in .init(generatedAt: clock.date) }
        empty.start(schedule: schedule, dailySummaryEnabled: true); await empty.runNow()
        expect(empty.activity(currentSummaryID: summaryID, hasCompletionNotice: true) == nil,
            "healthy empty preparation cannot offer an invented summary action")
        empty.stop()
    }

    private static func retryAfterManualResult(_ root: URL) async {
        for manualFails in [false, true] {
            let clock = BackgroundPresenceClock(), summaryID = UUID()
            let result = manualFails ? "failure" : "success"
            let engine = worker(root, "retry-after-manual-" + result, clock) { slot in
                guard slot.manualRequestID != nil else { throw ScheduledBriefingRunError.busy }
                if manualFails { throw ScheduledBriefingRunError.unavailable }
                return .init(generatedAt: clock.date, briefingID: summaryID, itemCount: 2)
            }
            engine.start(schedule: schedule, dailySummaryEnabled: true); engine.setEnabled(true)
            await engine.waitForCurrentRun()
            let automatic = engine.receipts.first
            let deadline = engine.nextRunAt
            clock.date.addTimeInterval(1)
            await engine.runNow()
            expect(engine.receipts.first?.slot.manualRequestID != nil
                && engine.receipts.first?.state == (manualFails ? .failed : .completed),
                "the fixture records a newer manual \(result) after an automatic busy receipt")
            let activity = engine.activity(currentSummaryID: summaryID, hasCompletionNotice: true)
            expect(automatic?.state == .deferred && deadline != nil
                && engine.nextRunAt == deadline && activity?.id == automatic?.id
                && activity?.retryAt == deadline && activity?.state == .deferred
                && activity?.isRunning == false && activity?.summaryID == nil
                && activity?.canOpenSummary == false,
                "a newer manual \(result) cannot hide the still-armed automatic retry")
            engine.stop()
        }
    }

    private static func failure(_ root: URL) async {
        let clock = BackgroundPresenceClock()
        let engine = worker(root, "failure", clock) { _ in throw ScheduledBriefingRunError.unavailable }
        engine.start(schedule: schedule, dailySummaryEnabled: true); await engine.runNow()
        let failure = engine.activity(currentSummaryID: nil, hasCompletionNotice: false)
        expect(failure?.state == .failed && failure?.finishedAt == engine.receipts.first?.finishedAt
            && failure?.retryAt == nil && failure?.canStop == false && failure?.canOpenSummary == false,
            "failed preparation exposes a finished failure with no automatic retry or result")
        clock.date.addTimeInterval(86_400)
        engine.refresh()
        expect(engine.activity(currentSummaryID: nil, hasCompletionNotice: false) == nil,
            "yesterday's failed receipt cannot become today's live activity")
        engine.stop()
    }

    private static func panel(_ root: URL) async {
        let clock = BackgroundPresenceClock(), gate = BackgroundPresenceGate()
        let engine = worker(root, "panel", clock) { _ in await gate.run(); return .init(generatedAt: clock.date) }
        engine.start(schedule: schedule, dailySummaryEnabled: true)
        let request = Task { @MainActor in await engine.runNow() }; await gate.wait()
        guard let activity = engine.activity(currentSummaryID: nil, hasCompletionNotice: false) else {
            expect(false, "panel fixture requires a production-owned activity"); gate.release(); await request.value; return
        }
        let controller = MacAssistantPanelController(observesPointer: false)
        var stoppedID: UUID?, tasksOpened = 0, summariesOpened = 0, invoked = 0
        func update(state: SuzzmeAssistantState = .idle, review: SuzzmePresenceReview? = nil,
                    browser: MacGitHubConnectionRequest? = nil, response: String? = nil, interactionID: UUID? = nil) {
            controller.update(state: state, theme: .suzzmePurple, animation: .minimal, review: review,
                connectionRequest: browser, response: response, interactionID: interactionID,
                backgroundActivity: activity, onBackgroundStop: { stoppedID = $0 },
                onOpenBackgroundTasks: { tasksOpened += 1 }, onOpenDailySummary: { summariesOpened += 1 },
                onCancel: {}, onInvoke: { invoked += 1 })
        }
        update()
        expect(controller.fixtureActivity == activity && controller.fixturePanel?.isVisible == true,
            "the existing app-owned panel hosts a real background preparation")
        expect(controller.fixturePanel?.styleMask.contains(.nonactivatingPanel) == true
            && controller.fixturePanel?.canBecomeMain == false,
            "background activity reuses the public nonactivating presence panel")
        expect(controller.fixtureHasDeadline, "background status has a finite automatic hide deadline")
        expect(MacAssistantPanelController.autoHideDelay(for: .idle, signal: .none, backgroundActivity: activity) == 8,
            "background status retains a bounded eight-second reading interval")
        controller.fixtureSurface?.onBackgroundStop?(activity.id)
        controller.fixtureSurface?.onOpenBackgroundTasks?()
        controller.fixtureSurface?.onOpenDailySummary?()
        expect(stoppedID == activity.id && tasksOpened == 1 && summariesOpened == 1 && invoked == 0,
            "the hosted surface preserves the displayed receipt and its navigation callbacks")
        let displacedSurface = controller.fixtureSurface
        controller.hideCurrentPresentation(); update()
        expect(controller.fixturePanel?.isVisible == false,
            "a normal activity refresh cannot reopen the same dismissed background phase")
        stoppedID = nil
        displacedSurface?.onBackgroundStop?(activity.id)
        displacedSurface?.onOpenBackgroundTasks?()
        displacedSurface?.onOpenDailySummary?()
        expect(stoppedID == nil && tasksOpened == 1 && summariesOpened == 1,
            "mouse-up callbacks from a held-to-hide background card cannot stop work or navigate")
        let review = SuzzmePresenceReview(id: UUID(), title: "Create a reminder?", confirmationLabel: "Create Reminder", isDestructive: false)
        update(state: .awaitingConfirmation, review: review)
        expect(controller.fixtureActivity == nil && !controller.fixtureHasDeadline,
            "confirmation review has priority and remains without an automatic deadline")
        displacedSurface?.onBackgroundStop?(activity.id); displacedSurface?.onOpenBackgroundTasks?()
        expect(stoppedID == nil && tasksOpened == 1,
            "a displaced background card cannot act after a review takes ownership")
        update(browser: .init(service: .github, repository: "fixture/repository"))
        expect(controller.fixtureActivity == nil && !controller.fixtureHasDeadline,
            "browser consent has priority over background controls")
        update(state: .listening, interactionID: UUID())
        expect(controller.fixtureActivity == nil, "live voice cannot be replaced by background activity")
        update(response: "A current answer.", interactionID: UUID())
        expect(controller.fixtureActivity == nil, "a current conversation answer keeps its reading surface")
        update(interactionID: UUID())
        expect(controller.fixtureActivity == nil, "an owned idle interaction still excludes background activity")
        controller.dismiss()
        expect(controller.fixturePanel?.isVisible != true && controller.fixtureActivity == nil,
            "dismiss removes background content and all retained action ownership")
        gate.release(); await request.value; engine.stop()
    }

    private static func metrics() {
        let value = ScheduledBriefingActivity(id: UUID(), state: .running, isRunning: true,
            isStopping: false, retryAt: nil, summaryID: nil, finishedAt: nil)
        let normal = MacAssistantSurfaceMetrics.size(state: .idle, signal: .none, notchWidth: 180,
            review: nil, response: nil, notchHeight: 32, backgroundActivity: value)
        let wide = MacAssistantSurfaceMetrics.size(state: .idle, signal: .none, notchWidth: 480,
            review: nil, response: nil, notchHeight: 48, backgroundActivity: value)
        expect(normal.width >= 328 && normal.height >= 296 + 32,
            "background detail reserves room for native controls below the cutout")
        expect(wide.width >= 480 && wide.height == normal.height + 16,
            "wide cutouts preserve measured width and physical safe-area inset")
        let review = SuzzmePresenceReview(id: UUID(), title: "Create?", confirmationLabel: "Create", isDestructive: false)
        let preferred = MacAssistantSurfaceMetrics.size(state: .awaitingConfirmation, signal: .none, notchWidth: 180,
            review: review, response: nil, notchHeight: 32, backgroundActivity: value)
        let ordinary = MacAssistantSurfaceMetrics.size(state: .awaitingConfirmation, signal: .none, notchWidth: 180,
            review: review, response: nil, notchHeight: 32)
        expect(preferred == ordinary, "background metadata cannot alter a confirmation's geometry")
        for display in [CGRect(x: 0, y: 0, width: 1_440, height: 900), CGRect(x: -1_920, y: -300, width: 1_920, height: 1_080),
                        CGRect(x: 0, y: 0, width: 300, height: 360)] {
            let frame = MacAssistantPanelPlacement.frame(size: normal, screenFrame: display,
                visibleFrame: display, hasNotch: false, notchCenterX: display.midX)
            expect(display.contains(frame), "background fallback remains inside display \(Int(display.width)) × \(Int(display.height))")
        }
        let visible = [value.title, value.message, value.symbol].joined(separator: " ")
        expect(!visible.contains(value.id.uuidString), "background status exposes semantic text without receipt identifiers")
    }

    private static func controllerGate(_ root: URL) async {
        let clock = BackgroundPresenceClock(), gate = BackgroundPresenceGate()
        let engine = worker(root, "controller-gate", clock) { _ in await gate.run(); return .init(generatedAt: clock.date) }
        engine.start(schedule: schedule, dailySummaryEnabled: true)
        let request = Task { @MainActor in await engine.runNow() }; await gate.wait()
        let environment = BackgroundPresenceEnvironment(engine)
        let tested = BackgroundPresenceOwner(environment)
        expect(tested.activity()?.id == engine.currentReceipt?.id, "the production controller gate reads the real owned engine projection")
        tested.running = false; expect(tested.activity() == nil, "a stopped controller cannot reveal background activity"); tested.running = true
        tested.openBackgroundDestination = nil
        expect(tested.activity() == nil, "status waits until the existing navigation bridge can honor its actions")
        tested.openBackgroundDestination = {}
        environment.proactivePreferences.dailyBriefingEnabled = false
        expect(tested.activity() == nil, "Daily Summary preference gates the surface")
        environment.proactivePreferences.dailyBriefingEnabled = true
        for state in SuzzmeAssistantState.allCases where state != .idle {
            environment.presenceState = state
            expect(tested.activity() == nil, "\(state.rawValue) conversation state outranks background metadata")
        }
        environment.presenceState = .idle
        environment.currentInteractionID = UUID(); expect(tested.activity() == nil, "an idle current interaction retains the foreground owner"); environment.currentInteractionID = nil
        environment.presentedResponse = "Current answer"; expect(tested.activity() == nil, "a retained answer takes precedence"); environment.presentedResponse = nil
        environment.presentedAction = UUID(); expect(tested.activity() == nil, "a pending action review takes precedence"); environment.presentedAction = nil
        environment.screenConsentRequestID = UUID(); expect(tested.activity() == nil, "screen consent takes precedence"); environment.screenConsentRequestID = nil
        environment.invocation.isActive = true; expect(tested.activity() == nil, "active invocation transitions take precedence"); environment.invocation.isActive = false
        environment.proactivePresenceSignal = .timeCritical; expect(tested.activity() == nil, "time-critical proactive information keeps the surface"); environment.proactivePresenceSignal = .none
        tested.heldToken = UUID(); expect(tested.activity() == nil, "a held push-to-talk token prevents an idle background reveal"); tested.heldToken = nil
        tested.startTask = Task {}; expect(tested.activity() == nil, "a pending voice start prevents an idle background reveal"); tested.startTask = nil
        environment.voice.isListening = true; expect(tested.activity() == nil, "voice listening gates background metadata"); environment.voice.isListening = false
        environment.voice.isFinalizing = true; expect(tested.activity() == nil, "voice finalization gates background metadata"); environment.voice.isFinalizing = false
        environment.voice.isSpeaking = true; expect(tested.activity() == nil, "voice playback gates background metadata"); environment.voice.isSpeaking = false
        environment.voice.isPreparingSpeech = true; expect(tested.activity() == nil, "speech preparation gates background metadata"); environment.voice.isPreparingSpeech = false
        environment.integrations.browserHandoff.request = .init()
        expect(tested.activity() == nil, "a current browser request retains ownership regardless of its handoff phase")
        environment.integrations.browserHandoff.request?.current = false
        expect(tested.activity()?.id == engine.currentReceipt?.id, "an expired browser request cannot suppress the restored background owner")
        expect(engine.currentReceipt?.id == tested.activity()?.id, "all gates clear back to the same worker rather than constructing another task")
        gate.release(); await request.value; engine.stop()
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited); app.finishLaunching()
        Task { @MainActor in
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("BackgroundPresenceChecks-" + UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                await running(root); await retry(root); await retryAfterManualResult(root); await completion(root); await failure(root); await panel(root); metrics(); await controllerGate(root)
                try? FileManager.default.removeItem(at: root)
                print("Background Presence checks: \(passed) passed, \(failed) failed")
                if failed > 0 { exit(1) }
                app.terminate(nil)
            } catch { print("Background presence fixture failed: \(error)"); exit(1) }
        }
        app.run()
    }
}
