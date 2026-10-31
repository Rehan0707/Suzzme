import Foundation
import SwiftData
import UserNotifications

actor P0NotificationCenter: ProactiveNotificationCenter {
    var authorized = true
    var values: [String: PublicProactiveNotification] = [:]
    var delay = false
    var failNext = false
    func requestAuthorization() async throws -> Bool { authorized }
    func isAuthorized() async -> Bool { authorized }
    func pendingIdentifiers() async -> [String] { Array(values.keys) }
    func add(_ value: PublicProactiveNotification) async throws {
        if delay { try await Task.sleep(for: .milliseconds(60)) }
        if failNext { failNext = false; throw CocoaError(.fileWriteUnknown) }
        values[value.identifier] = value
    }
    func remove(_ ids: [String]) async { for id in ids { values.removeValue(forKey: id) } }
    func value() -> PublicProactiveNotification? { values[ProactiveNotificationDelivery.summaryIdentifier] }
    func configure(authorized: Bool = true, delay: Bool = false, fail: Bool = false) { self.authorized = authorized; self.delay = delay; failNext = fail }
}
actor P0ExtractionSpy: SuzzmeIntelligenceService {
    var calls = 0
    func capability() async -> IntelligenceCapability { .available }
    func understand(text: String, referenceDate: Date) async throws -> [ExtractedSuzzmeItem] { calls += 1; return [] }
    func summarize(text: String) async throws -> String { text }
}
struct P0OpenSource: ContextSource {
    let identifier = "reminders"
    let items: [SuzzmeContextItem]
    func fetchContext(for request: SuzzmeContextRequest) async throws -> [SuzzmeContextItem] {
        items.filter { SuzzmeReminderSelection.includes(dueDate: $0.metadata["due"].flatMap { ISO8601DateFormatter().date(from: $0) }, completed: $0.metadata["completed"] == "true", range: request.query.dateRange, now: request.referenceDate) }
    }
}
struct P0UnavailableReminders: ContextSource {
    let identifier = "reminders"
    func fetchContext(for request: SuzzmeContextRequest) async throws -> [SuzzmeContextItem] {
        throw SuzzmeContextError.sourceUnavailable(identifier)
    }
}
@main @MainActor struct P0BlockerChecks {
    static var passed = 0, failed = 0
    static func check(_ value: Bool, _ name: String) { if value { passed += 1; print("PASS \(name)") } else { failed += 1; print("FAIL \(name)") } }
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("P0-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date.now
        let spy = P0ExtractionSpy()
        let router = IntelligenceRouter(pipeline: .init(primary: spy))
        check(RemindersContextSource.importance(forNativePriority: 1) == .important, "native high-priority reminder remains important")
        check(RemindersContextSource.importance(forNativePriority: 5) == .normal, "native medium-priority reminder remains normal")
        check(RemindersContextSource.importance(forNativePriority: 9) == .low, "native low-priority reminder cannot outrank important work")
        let questions = ["What should I focus on?", "What should I work on today?", "What needs my attention?", "What should I prioritize?", "Anything important today?", "What matters most right now?", "What is important today?", "Do I have anything urgent?", "What should I work on?"]
        for q in questions {
            check(SuzzmeContextQuery.infer(from:q).sources == [.calendar,.reminders], "context selected: \(q)")
            let r = try await router.route(text:q,context:[],existingFingerprints:[])
            check(r.extractedItems.isEmpty && r.intent == .question, "question never becomes capture: \(q)")
        }
        check(await spy.calls == 0, "ordinary questions cannot invoke probabilistic extraction")
        for q in ["Remember that my project is Atlas.", "Save this information.", "Keep this in mind: registration closes tomorrow.", "Remember this deadline."] {
            check(SuzzmeQuestionIntent.classify(q) == .capture, "explicit capture boundary: \(q)")
        }
        let container = try ModelContainer(for: StoredSuzzmeMemory.self, StoredSuzzmeMemoryRelationship.self, configurations: ModelConfiguration(isStoredInMemoryOnly:true))
        let memoryStore = LongTermMemoryStore(modelContainer:container)
        let memoryCore = SuzzmeCore(memoryStore:memoryStore)
        for q in ["Remember that my project is Atlas.", "Remember that I prefer morning summaries."] {
            let r = try await memoryCore.respond(to:q,sources:[],existingFingerprints:[],progress:{_ in})
            check(r.text.contains("remember") && r.extractedItems.isEmpty, "explicit memory still reaches admission: \(q)")
        }
        let capture = try await router.route(text:"Save this information.",context:[],existingFingerprints:[])
        check(capture.extractedItems.isEmpty && capture.text.contains("Which information"), "missing capture referent asks clarification")
        let today = Calendar.current.startOfDay(for:now)
        let end = Calendar.current.date(byAdding:.day,value:1,to:today)!
        for days in [0,1,8,30] {
            let due = Calendar.current.date(byAdding:.day,value:-days,to:today)!
            check(SuzzmeReminderSelection.includes(dueDate:due,completed:false,range:.init(start:today,end:end),now:now), "open due \(days) days ago retained")
        }
        for days in [1,30] {
            check(!SuzzmeReminderSelection.includes(dueDate:now.addingTimeInterval(Double(-days)*86400),completed:true,range:nil,now:now), "completed \(days) days ago excluded")
        }
        check(SuzzmeReminderSelection.includes(dueDate:nil,completed:false,range:.init(start:today,end:end),now:now), "unfinished no-date reminder retained")
        check(!SuzzmeReminderSelection.includes(dueDate:nil,completed:false,range:.init(start:end,duration:86400),now:now), "tomorrow scope does not invent date for undated work")
        let old = SuzzmeContextItem(sourceIdentifier:"old-reminder",content:"Project report",timestamp:now,intent:.reminder,importance:.important,metadata:["source":"reminders","title":"Project report","due":ISO8601DateFormatter().string(from:now.addingTimeInterval(-30*86400)),"completed":"false"])
        let proactiveStore = ProactiveIntelligenceStore(fileURL:root.appendingPathComponent("proactive.json"))
        let engine = ProactiveIntelligenceEngine(store:proactiveStore)
        let snapshot = try await engine.prepare(from:[P0OpenSource(items:[old,old])],now:now)
        check(snapshot.dailyContext?.activeEntries.count == 1, "old open work deduplicates in Today")
        check(snapshot.briefing?.items.contains(where: { $0.summary.contains("Project report") }) == true, "30-day overdue commitment reaches summary")
        let empty = try await engine.prepare(from:[P0OpenSource(items:[])],now:now)
        check(empty.dailyContext?.activeEntries.isEmpty == true, "deleted or completed reminder leaves active Today on refresh")
        let again = try await engine.prepare(from:[P0OpenSource(items:[old])],now:now)
        check(again.dailyContext?.activeEntries.count == 1, "repeat refresh does not duplicate open commitment")
        for q in ["Do I have anything unfinished?", "What am I behind on?", "Anything overdue?", "What still needs to be done?", "What did I forget to finish?"] {
            let r = try await router.route(text:q,context:[old],existingFingerprints:[])
            check(r.text.contains("Project report") && r.extractedItems.isEmpty, "unfinished wording grounded: \(q)")
        }
        let questionCore = SuzzmeCore(router:router)
        _ = try await questionCore.respond(to:"Do I have anything unfinished?", sources:[P0OpenSource(items:[old])], existingFingerprints:[],progress:{_ in})
        let afterCompletion = try await questionCore.respond(to:"Do I have anything unfinished?", sources:[P0OpenSource(items:[])], existingFingerprints:[],progress:{_ in})
        check(!afterCompletion.text.contains("Project report"), "completed work cannot be resurrected from conversational context")
        _ = try await questionCore.respond(to:"Do I have anything unfinished?", sources:[P0OpenSource(items:[old])], existingFingerprints:[],progress:{_ in})
        let unavailable = try await questionCore.respond(to:"Do I have anything unfinished?", sources:[P0UnavailableReminders()], existingFingerprints:[],progress:{_ in})
        check(unavailable.text.contains("couldn’t check Reminders") && !unavailable.text.contains("Project report"),
              "failed reminder read cannot present cached commitments as live authority")
        let updatedDue = now.addingTimeInterval(86400)
        let moved = SuzzmeContextItem(sourceIdentifier:old.sourceIdentifier,content:old.content,timestamp:now,intent:.reminder,importance:.important,metadata:["source":"reminders","title":"Project report","due":ISO8601DateFormatter().string(from:updatedDue),"completed":"false"])
        let movedSummary = try await engine.prepare(from:[P0OpenSource(items:[moved])],now:now)
        check(movedSummary.dailyContext?.activeEntries.count == 1 && movedSummary.dailyContext?.activeEntries.first?.effectiveAt?.timeIntervalSince(updatedDue).magnitude ?? 1 < 1, "updated due date supersedes old commitment")
        let rolled = try await engine.prepare(from:[P0OpenSource(items:[old])],now:now.addingTimeInterval(86400))
        check(rolled.dailyContext?.activeEntries.contains { $0.title == "Project report" } == true, "unresolved overdue work survives day rollover")
        let undated = SuzzmeContextItem(sourceIdentifier:"undated",content:"Plan project outline",timestamp:now,intent:.reminder,importance:.important,metadata:["source":"reminders","title":"Plan project outline","completed":"false"])
        let undatedSummary = try await engine.prepare(from:[P0OpenSource(items:[undated])],now:now)
        check(undatedSummary.dailyContext?.activeEntries.count == 1, "undated open commitment reaches Today without inventing due date")
        let many = (0..<40).map { SuzzmeContextItem(sourceIdentifier:"open-\($0)",content:"Review project \($0)",timestamp:now,intent:.reminder,importance:.normal,metadata:["source":"reminders","completed":"false"]) }
        let busy = try await engine.prepare(from:[P0OpenSource(items:many)],now:now)
        check((busy.briefing?.items.count ?? 0) <= ProactiveLimits.briefingItems && (busy.dailyContext?.entries.count ?? 0) <= ProactiveLimits.dailyContextItems, "large open-work backlog remains bounded rather than dumped")
        let infoContainer = try ModelContainer(for: StoredInformationEvent.self, StoredInformationSource.self, configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let info = InformationStore(modelContainer:infoContainer)
        try await info.setEnabled(.reminders,enabled:true)
        let cycle = try await info.begin(.reminders,now:now)
        let observation = InformationObservation(externalID:"old-open",title:"Old open report",privateNotes:"",location:"",entities:[],modifiedAt:now,effectiveAt:now.addingTimeInterval(-30*86400),effectiveUntil:nil,state:.active,kindHint:.reminderChange)
        try await info.commit(.init(observations:[observation],complete:true,window:.init(start:today,end:end),coversUndated:true,coversOpenReminders:true),cycle:cycle,now:now)
        let next = try await info.begin(.reminders,now:now)
        try await info.commit(.init(observations:[],complete:true,window:.init(start:today,end:end),coversUndated:true,coversOpenReminders:true),cycle:next,now:now)
        check(try await info.retrieve(now:now).allSatisfy { $0.objectState != .active }, "complete open snapshot retires old completed/deleted information")
        let undatedCycle = try await info.begin(.reminders,now:now)
        let undatedObservation = InformationObservation(externalID:"no-date",title:"Plan project outline",privateNotes:"",location:"",entities:[],modifiedAt:now,effectiveAt:nil,effectiveUntil:nil,state:.active,kindHint:.reminderChange)
        try await info.commit(.init(observations:[undatedObservation],complete:true,window:.init(start:today,end:end),coversUndated:true,coversOpenReminders:true),cycle:undatedCycle,now:now)
        let absentCycle = try await info.begin(.reminders,now:now)
        try await info.commit(.init(observations:[],complete:true,window:.init(start:today,end:end),coversUndated:true,coversOpenReminders:true),cycle:absentCycle,now:now)
        check(try await info.retrieve(now:now).allSatisfy { $0.externalID != "no-date" || $0.objectState != .active }, "deleted undated commitment retires only with complete open-work coverage")
        let center = P0NotificationCenter()
        let delivery = ProactiveNotificationDelivery(center:center)
        var prefs = ProactivePreferences()
        try await delivery.reconcileSummary(prefs)
        let first = await center.value()
        check(first?.summaryTime?.hour == 8 && first?.summaryTime?.minute == 0, "enabled summary schedules preferred local time")
        check(first?.body.contains("ready") == false, "notification never claims ungenerated summary ready")
        check(first?.summaryTime?.timeZone == nil, "OS calendar trigger follows user-local timezone")
        prefs.briefingHour = 9
        try await delivery.reconcileSummary(prefs)
        let changedTime = await center.value()?.summaryTime?.hour
        let changedCount = await center.pendingIdentifiers().count
        check(changedTime == 9 && changedCount == 1, "time change replaces schedule without duplicate")
        try await delivery.reconcileSummary(prefs)
        check(await center.pendingIdentifiers().count == 1, "repeated reconcile is idempotent")
        let restarted = ProactiveNotificationDelivery(center:center)
        try await restarted.reconcileSummary(prefs)
        check(await center.pendingIdentifiers().count == 1, "restart reconciles one OS schedule")
        try await restarted.reconcileSummary(prefs,timeZone:TimeZone(identifier:"America/New_York")!)
        check(await center.value()?.summaryTime?.timeZone == nil, "timezone change retains 9 AM local-time semantics")
        prefs.dailyBriefingEnabled = false
        try await delivery.reconcileSummary(prefs)
        check(await center.pendingIdentifiers().isEmpty, "disable cancels summary schedule")
        await center.configure(authorized:false)
        prefs.dailyBriefingEnabled = true
        try await delivery.reconcileSummary(prefs)
        check(await center.pendingIdentifiers().isEmpty, "permission denial leaves no schedule")
        await center.configure()
        try await delivery.reconcileSummary(prefs)
        await center.configure(authorized:false)
        try await delivery.reconcileSummary(prefs)
        check(await center.pendingIdentifiers().isEmpty, "permission revocation retires schedule")
        await center.configure(delay:true)
        let enablingPreferences = prefs
        let enable = Task { try await delivery.reconcileSummary(enablingPreferences) }
        try await Task.sleep(for:.milliseconds(15))
        prefs.dailyBriefingEnabled = false
        try await delivery.reconcileSummary(prefs)
        try await enable.value
        check(await center.pendingIdentifiers().isEmpty, "disable during OS add cannot leave stale schedule")
        await center.configure(fail:true)
        prefs.dailyBriefingEnabled = true
        do { try await delivery.reconcileSummary(prefs); check(false,"scheduling failure surfaced") }
        catch { check(true,"scheduling failure surfaced") }
        try await proactiveStore.updatePreferences(prefs)
        let reopened = ProactiveIntelligenceStore(fileURL:root.appendingPathComponent("proactive.json"))
        check(try await reopened.preferences().briefingHour == 9, "preferred time persists across store reopen")
        var matching = DateComponents()
        matching.hour = 9; matching.minute = 0
        let nativeTrigger = UNCalendarNotificationTrigger(dateMatching: matching, repeats: true)
        check(nativeTrigger.repeats && nativeTrigger.dateComponents.timeZone == nil && nativeTrigger.nextTriggerDate() != nil,
              "native Apple trigger has a next local daily delivery")
        if let nextDate = nativeTrigger.nextTriggerDate() {
            check(Calendar.current.component(.hour, from: nextDate) == 9 && Calendar.current.component(.minute, from: nextDate) == 0,
                  "native trigger resolves preferred wall-clock time on next day")
        } else { check(false, "native trigger resolves preferred wall-clock time on next day") }
        UserDefaults.standard.set(true, forKey: "suzzme.dailySummary.notificationPending")
        check(SummaryNotificationNavigation.consumeOpen(), "notification open survives until navigation consumes it")
        check(!SummaryNotificationNavigation.consumeOpen(), "notification open cannot navigate twice")
        print("P0 regression checks: \(passed) passed / \(failed) failed")
        if failed > 0 { throw CocoaError(.validationMissingMandatoryProperty) }
    }
}
