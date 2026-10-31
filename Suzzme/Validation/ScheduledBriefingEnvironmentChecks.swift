import Foundation

// Only collaborator shapes are doubled. The Python runner compiles both exact
// production AppEnvironment methods, plus the real schedule/output models.
// All input below is synthetic; no app, source, model, account or TCC is opened.

@MainActor final class ScheduledEnvironmentGate {
    private var entered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func wait() async {
        entered = true
        entryWaiter?.resume()
        entryWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { entryWaiter = $0 } }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

@MainActor final class ScheduledEnvironmentCalls {
    var values: [String] = []
    var suspendedStage: String?
    let gate = ScheduledEnvironmentGate()

    func record(_ stage: String) async {
        values.append(stage)
        if stage == suspendedStage { await gate.wait() }
    }
}

enum ScheduledEnvironmentFailure: Error, Equatable { case source, preparation, permission, health }

struct ScheduledEnvironmentPreferences: Equatable {
    var dailyBriefingEnabled = true
    var briefingHour = 8
    var briefingMinute = 0
}

struct ScheduledEnvironmentSnapshot: Equatable {
    struct Briefing: Equatable { let id: UUID; let items: [Int] }
    struct Entry: Equatable { let source: String }
    struct Context: Equatable { let activeEntries: [Entry]; let sourceLimitations: [String] }
    let generatedAt: Date
    let briefing: Briefing?
    let dailyContext: Context?

    static let prepared = Self(generatedAt: Date(timeIntervalSince1970: 1_792_622_400),
        briefing: .init(id: UUID(), items: [1, 2, 3]),
        dailyContext: .init(activeEntries: [.init(source: "calendar"), .init(source: "calendar"), .init(source: "reminders")],
                            sourceLimitations: ["Permission is limited", "One source is unavailable"]))
    static let previous = Self(generatedAt: .distantPast, briefing: nil, dailyContext: nil)
}

struct ScheduledEnvironmentHealth: Equatable {
    enum State { case healthy, unavailable }
    let enabled: Bool
    let state: State
}

protocol ContextSource { var identifier: String { get } }
struct ScheduledEnvironmentSource: ContextSource { let identifier: String }
struct SuzzmeItemContextSource: ContextSource {
    let items: [Int]
    let identifier = "items"
}

@MainActor final class ScheduledEnvironmentInformation {
    let calls: ScheduledEnvironmentCalls
    var failure: ScheduledEnvironmentFailure?
    var refreshForces: [Bool] = []
    var healthResult: [ScheduledEnvironmentHealth] = [
        .init(enabled: true, state: .healthy),
        .init(enabled: true, state: .unavailable),
        .init(enabled: true, state: .unavailable),
        .init(enabled: true, state: .unavailable),
        .init(enabled: false, state: .unavailable),
    ]

    init(calls: ScheduledEnvironmentCalls) { self.calls = calls }

    func refresh(force: Bool) async throws {
        refreshForces.append(force)
        await calls.record("refresh")
        if failure == .source { throw ScheduledEnvironmentFailure.source }
    }

    func health() async throws -> [ScheduledEnvironmentHealth] {
        await calls.record("health")
        if failure == .health { throw ScheduledEnvironmentFailure.health }
        return healthResult
    }

}

@MainActor final class ScheduledEnvironmentItemStore {
    let calls: ScheduledEnvironmentCalls
    init(calls: ScheduledEnvironmentCalls) { self.calls = calls }
    func allItems() throws -> [Int] { calls.values.append("items"); return [42] }
}

@MainActor final class ScheduledEnvironmentCore {
    let calls: ScheduledEnvironmentCalls
    var preferences = ScheduledEnvironmentPreferences()
    var snapshot = ScheduledEnvironmentSnapshot.prepared
    var failure: ScheduledEnvironmentFailure?
    var preferenceReads = 0
    var preparedSourceIDs: [String] = []
    var preparedProfileName: String?
    var sessionMemoryOptions: [Bool] = []

    init(calls: ScheduledEnvironmentCalls) { self.calls = calls }

    func proactivePreferences() async throws -> ScheduledEnvironmentPreferences {
        preferenceReads += 1
        await calls.record("preferences.\(preferenceReads)")
        return preferences
    }

    func prepareProactiveBriefing(from sources: [any ContextSource], profileName: String?, rememberInSession: Bool = true) async throws -> UUID {
        preparedSourceIDs = sources.map(\.identifier)
        preparedProfileName = profileName
        sessionMemoryOptions.append(rememberInSession)
        await calls.record("prepare")
        if failure == .preparation { throw ScheduledEnvironmentFailure.preparation }
        return UUID()
    }

    func currentProactiveSnapshot() async throws -> ScheduledEnvironmentSnapshot {
        await calls.record("snapshot")
        if failure == .permission { throw ScheduledEnvironmentFailure.permission }
        return snapshot
    }
}

@MainActor final class ScheduledEnvironmentAssistant {
    enum State { case idle, success, error, thinking, listening, confirming }
    var transitions = 0
    var state: State = .idle { didSet { transitions += 1 } }
}

@MainActor final class ScheduledEnvironmentVoice {
    var transitions = 0
    var sessionID = UUID() { didSet { transitions += 1 } }
    var isListening = false { didSet { transitions += 1 } }
    var isFinalizing = false { didSet { transitions += 1 } }
    var isSpeaking = false { didSet { transitions += 1 } }
    var isPreparingSpeech = false { didSet { transitions += 1 } }
}

@MainActor final class ScheduledBriefingEnvironmentHarness {
    let calls = ScheduledEnvironmentCalls()
    var information: ScheduledEnvironmentInformation?
    var proactive: Bool? = true
    var itemStore: ScheduledEnvironmentItemStore?
    let core: ScheduledEnvironmentCore
    let assistant = ScheduledEnvironmentAssistant()
    let voice = ScheduledEnvironmentVoice()
    var isRefreshingInformation = false
    var isPreparingBriefing = false
    var isLoading = false
    var activeAssistantRequestID: UUID?
    var pendingConfirmation: UUID?
    var pendingScreenQuestion: UUID?
    var transientStartOwner: UUID?
    var globalPushToTalkToken: UUID?
    var activityItems: [Int] = []
    let calendarSource = ScheduledEnvironmentSource(identifier: "calendar")
    let remindersSource = ScheduledEnvironmentSource(identifier: "reminders")
    let profileName: String? = "Synthetic profile"
    var proactiveSnapshot: ScheduledEnvironmentSnapshot? = .previous
    var proactivePreferences = ScheduledEnvironmentPreferences()
    var informationHealth: [ScheduledEnvironmentHealth] = []
    var informationEvents: [String] = ["previous-event"]
    var proactiveError: String? = "previous-error"
    var scheduledBriefingNoticeID: UUID?

    init() {
        core = ScheduledEnvironmentCore(calls: calls)
        information = ScheduledEnvironmentInformation(calls: calls)
        itemStore = ScheduledEnvironmentItemStore(calls: calls)
    }
}

@main @MainActor struct ScheduledBriefingEnvironmentChecks {
    static var passed = 0
    static var failed = 0
    static let schedule = ScheduledBriefingSchedule(hour: 8, minute: 0, timeZoneIdentifier: "Asia/Kolkata")
    static let stages = ["preferences.1", "refresh", "prepare", "health", "preferences.2", "snapshot"]

    static func expect(_ condition: Bool, _ message: String) {
        print("\(condition ? "PASS" : "FAIL") \(message)")
        if condition { passed += 1 } else { failed += 1 }
    }

    static func run(_ environment: ScheduledBriefingEnvironmentHarness) async -> Result<ScheduledBriefingOutput, any Error> {
        do { return .success(try await environment.runScheduledBriefing(schedule.slot(on: .now))) }
        catch { return .failure(error) }
    }

    static func isError(_ result: Result<ScheduledBriefingOutput, any Error>, _ expected: ScheduledBriefingRunError) -> Bool {
        if case .failure(let error) = result { return (error as? ScheduledBriefingRunError) == expected }
        return false
    }

    static func unchangedPublication(_ environment: ScheduledBriefingEnvironmentHarness) -> Bool {
        environment.proactiveSnapshot == .previous && environment.scheduledBriefingNoticeID == nil
            && environment.informationHealth.isEmpty && environment.informationEvents == ["previous-event"]
            && environment.proactiveError == "previous-error"
    }

    static func preflight() async {
        let unavailable: [(String, (ScheduledBriefingEnvironmentHarness) -> Void)] = [
            ("information service", { $0.information = nil }),
            ("proactive service", { $0.proactive = nil }),
            ("item store", { $0.itemStore = nil }),
        ]
        let busy: [(String, (ScheduledBriefingEnvironmentHarness) -> Void)] = [
            ("information refresh", { $0.isRefreshingInformation = true }),
            ("briefing preparation", { $0.isPreparingBriefing = true }),
            ("foreground loading", { $0.isLoading = true }),
            ("assistant work", { $0.assistant.state = .thinking }),
            ("confirmation", { $0.pendingConfirmation = UUID() }),
            ("screen question", { $0.pendingScreenQuestion = UUID() }),
            ("transient start", { $0.transientStartOwner = UUID() }),
            ("push to talk", { $0.globalPushToTalkToken = UUID() }),
            ("listening", { $0.voice.isListening = true }),
            ("voice finalization", { $0.voice.isFinalizing = true }),
            ("speaking", { $0.voice.isSpeaking = true }),
            ("speech preparation", { $0.voice.isPreparingSpeech = true }),
        ]
        for (name, configure) in unavailable + busy {
            let environment = ScheduledBriefingEnvironmentHarness()
            configure(environment)
            let result = await run(environment)
            let expected: ScheduledBriefingRunError = unavailable.contains { $0.0 == name } ? .unavailable : .busy
            expect(isError(result, expected) && environment.calls.values.isEmpty && unchangedPublication(environment),
                   "\(name) blocks scheduled work before any read or publication")
        }
        let disabled = ScheduledBriefingEnvironmentHarness()
        disabled.core.preferences.dailyBriefingEnabled = false
        let result = await run(disabled)
        expect(isError(result, .disabled) && disabled.calls.values == ["preferences.1"]
            && !disabled.isRefreshingInformation && !disabled.isPreparingBriefing,
               "Daily Summary off prevents source reads and releases busy flags")
    }

    static func successfulPreparation() async {
        let environment = ScheduledBriefingEnvironmentHarness()
        let result = await run(environment)
        guard case .success(let output) = result else { expect(false, "enabled summary prepares successfully"); return }
        expect(environment.calls.values == ["preferences.1", "items", "refresh", "prepare", "health", "preferences.2", "snapshot"],
               "scheduled work refreshes the existing engine and revalidates its snapshot as the final await")
        expect(environment.information?.refreshForces == [true]
            && environment.core.preparedSourceIDs == ["calendar", "reminders", "items"]
            && environment.core.preparedProfileName == environment.profileName
            && environment.core.sessionMemoryOptions == [false],
               "summary uses the supplied source engine and existing permitted context sources")
        expect(output.generatedAt == environment.core.snapshot.generatedAt
            && output.briefingID == environment.core.snapshot.briefing?.id
            && output.itemCount == 3 && output.sourceCount == 2 && output.limitationCount == 3,
               "receipt reports actual briefing metadata, distinct sources and enabled unhealthy sources")
        expect(environment.proactiveSnapshot == environment.core.snapshot && environment.scheduledBriefingNoticeID != nil
            && environment.informationEvents == ["previous-event"] && environment.proactiveError == nil,
               "validated preparation publishes the snapshot and a notice")
        expect(environment.core.sessionMemoryOptions == [false],
               "scheduled preparation never writes to the interactive session memory")
        expect(environment.assistant.transitions == 0 && environment.voice.transitions == 0
            && !environment.isRefreshingInformation && !environment.isPreparingBriefing,
               "background completion leaves assistant and voice presentation unchanged")

        let limited = ScheduledBriefingEnvironmentHarness()
        limited.information?.healthResult = [.init(enabled: false, state: .unavailable)]
        if case .success(let output) = await run(limited) {
            expect(output.limitationCount == 2, "context limitations remain visible when no enabled source is unhealthy")
        } else { expect(false, "limited summary remains a successful preparation") }

        let empty = ScheduledBriefingEnvironmentHarness()
        empty.core.snapshot = .init(generatedAt: .now, briefing: nil, dailyContext: nil)
        empty.information?.healthResult = []
        if case .success(let output) = await run(empty) {
            expect(output.briefingID == nil && output.itemCount == 0 && output.sourceCount == 0
                && output.limitationCount == 0 && empty.scheduledBriefingNoticeID == nil,
                   "an empty validated snapshot produces honest zero metadata without a ready notice")
        } else { expect(false, "empty summary returns metadata") }
    }

    static func failures() async {
        for failure in [ScheduledEnvironmentFailure.source, .preparation, .permission, .health] {
            let environment = ScheduledBriefingEnvironmentHarness()
            environment.information?.failure = failure
            environment.core.failure = failure
            let result = await run(environment)
            if case .failure(let error) = result {
                expect((error as? ScheduledEnvironmentFailure) == failure && unchangedPublication(environment)
                    && !environment.isRefreshingInformation && !environment.isPreparingBriefing,
                       "\(failure) failure propagates without a success projection or notice")
            } else { expect(false, "\(failure) must not become success") }
            if failure == .source {
                expect(!environment.calls.values.contains("prepare"), "failed source refresh never starts briefing preparation")
            }
            if failure == .permission {
                expect(environment.calls.values.contains("prepare") && environment.calls.values.last == "snapshot",
                       "final permission revalidation after preparation blocks publication")
            }
        }
    }

    static func suspensionOwnership() async {
        for stage in stages {
            for cancel in [false, true] {
                let environment = ScheduledBriefingEnvironmentHarness()
                environment.calls.suspendedStage = stage
                let task = Task { await run(environment) }
                await environment.calls.gate.waitUntilEntered()
                if cancel { task.cancel() } else { environment.activeAssistantRequestID = UUID() }
                environment.calls.gate.release()
                let result = await task.value
                let rejected: Bool
                if case .failure(let error) = result {
                    rejected = cancel ? error is CancellationError : (error as? ScheduledBriefingRunError) == .busy
                } else { rejected = false }
                expect(rejected && unchangedPublication(environment)
                    && !environment.isRefreshingInformation && !environment.isPreparingBriefing,
                       "\(cancel ? "cancellation" : "new foreground request") during \(stage) cannot publish stale success")
            }
        }
        let voice = ScheduledBriefingEnvironmentHarness()
        voice.calls.suspendedStage = "prepare"
        let voiceTask = Task { await run(voice) }
        await voice.calls.gate.waitUntilEntered()
        voice.voice.sessionID = UUID()
        voice.calls.gate.release()
        expect(isError(await voiceTask.value, .busy) && unchangedPublication(voice),
               "a new voice session owns presentation even before it starts speaking")
    }

    static func preferenceChanges() async {
        for disable in [false, true] {
            let environment = ScheduledBriefingEnvironmentHarness()
            environment.calls.suspendedStage = "prepare"
            let task = Task { await run(environment) }
            await environment.calls.gate.waitUntilEntered()
            if disable { environment.core.preferences.dailyBriefingEnabled = false }
            else { environment.core.preferences.briefingHour = 9 }
            environment.calls.gate.release()
            let result = await task.value
            let rejected: Bool
            if case .failure(let error) = result {
                rejected = disable ? (error as? ScheduledBriefingRunError) == .disabled : error is CancellationError
            } else { rejected = false }
            expect(rejected && unchangedPublication(environment),
                   "\(disable ? "disabling summary" : "changing schedule") while preparing rejects the old slot's publication")
        }
    }

    static func main() async {
        await preflight()
        await successfulPreparation()
        await failures()
        await suspensionOwnership()
        await preferenceChanges()
        print("Scheduled briefing environment checks: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
