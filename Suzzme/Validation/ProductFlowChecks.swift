import Foundation
import SwiftData

private struct ProductContextSource: ContextSource {
    let identifier: String
    let items: [SuzzmeContextItem]
    func fetchContext(for request: SuzzmeContextRequest) async throws -> [SuzzmeContextItem] {
        try Task.checkCancellation()
        return items
    }
}

private struct ProductInformationSource: InformationSource {
    let id: InformationSourceID = .calendar
    func authorization() async -> InformationHealthState { .healthy }
    func fetch(now: Date, checkpoint: Date?) async throws -> InformationBatch {
        .init(observations: [], complete: false, window: DateInterval(start: now, duration: 86400))
    }
}

@main @MainActor
struct ProductFlowChecks {
    private static var passed = 0
    private static var failed = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() { passed += 1; print("PASS \(name)") }
        else { failed += 1; print("FAIL \(name)") }
    }

    static func main() async throws {
        let help = try await IntelligenceRouter().route(text: "What can you help me with?", context: [], existingFingerprints: [])
        expect(help.route == .deterministic && help.intent == .question, "capability question receives local conversational answer")
        expect(help.extractedItems.isEmpty && help.text.contains("confirmation"), "help does not become a saved item or promise autonomous actions")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmeProductFlow-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date.now
        let eventTime = now.addingTimeInterval(3_600)
        let dueTime = now.addingTimeInterval(7_200)
        let calendarItem = SuzzmeContextItem(
            sourceIdentifier: "event-1", content: "Operating Systems lecture", timestamp: now,
            intent: .event, importance: .important,
            metadata: ["source": "calendar", "title": "Operating Systems lecture", "start": ISO8601DateFormatter().string(from: eventTime), "end": ISO8601DateFormatter().string(from: eventTime.addingTimeInterval(3_600))],
            expiration: eventTime.addingTimeInterval(3_600)
        )
        let reminderItem = SuzzmeContextItem(
            sourceIdentifier: "reminder-1", content: "Submit the project report", timestamp: now,
            intent: .reminder, importance: .important,
            metadata: ["source": "reminders", "title": "Submit the project report", "due": ISO8601DateFormatter().string(from: dueTime), "completed": "false"]
        )
        let calendar = ProductContextSource(identifier: "calendar", items: [calendarItem])
        let reminders = ProductContextSource(identifier: "reminders", items: [reminderItem])
        let store = ProactiveIntelligenceStore(fileURL: root.appendingPathComponent("proactive.json"))
        let proactive = ProactiveIntelligenceEngine(store: store)
        let actionStore = ActionStoreDouble()
        let actionCoordinator = SuzzmeActionExecutionCoordinator(
            registry: .init(capabilities: [StoreBackedCapability(id: .reminders, store: actionStore)])
        )
        let core = SuzzmeCore(actionCoordinator: actionCoordinator, proactive: proactive)

        let dailyQuery = SuzzmeContextQuery.infer(from: "What do I have today?", now: now)
        expect(dailyQuery.sources == [.calendar, .reminders], "day question requests calendar and reminders")
        expect(SuzzmeContextQuery.infer(from: "Volunteer", now: now).sources.isEmpty, "unrelated text does not request Apple sources")
        expect(SuzzmeContextQuery.infer(from: "What assignment is due?", now: now).sources == [.reminders], "assignment question requests reminders only")
        let daily = try await core.respond(
            to: "What do I have today?", sources: [calendar, reminders], query: dailyQuery,
            existingFingerprints: [], profileName: "Rehan", progress: { _ in }
        )
        expect(daily.text.contains("Rehan"), "daily answer is personal")
        expect(daily.text.contains("Operating Systems"), "daily answer includes calendar")
        expect(daily.text.contains("project report"), "daily answer includes reminders")
        expect(daily.contextCount == 2, "daily answer reports grounded context")
        let ambiguous = try await core.respond(
            to: "What time is it?", sources: [calendar, reminders],
            query: SuzzmeContextQuery.infer(from: "What time is it?", now: now),
            existingFingerprints: [], progress: { _ in }
        )
        expect(ambiguous.text.contains("Which event or reminder"), "ambiguous follow-up asks for clarification")

        let locatedEvent = SuzzmeContextItem(sourceIdentifier: "event-1", content: "Operating Systems lecture", timestamp: now,
            intent: .event, importance: .important,
            metadata: ["source": "calendar", "title": "Operating Systems lecture", "location": "Lab 2",
                       "start": ISO8601DateFormatter().string(from: eventTime)])
        let locationFollowUp = try await core.respond(to: "Where is the Operating Systems lecture?",
            sources: [ProductContextSource(identifier: "calendar", items: [locatedEvent])],
            query: SuzzmeContextQuery.infer(from: "Where is the Operating Systems lecture?", now: now),
            existingFingerprints: [], progress: { _ in })
        expect(locationFollowUp.text.contains("Lab 2"), "fresh source location replaces the same event's summary projection")
        expect(!locationFollowUp.text.contains("Which event"), "same source object does not become an ambiguous duplicate")



        let tomorrowTime = Calendar.current.date(byAdding: .day, value: 1, to: eventTime)!
        let tomorrowEvent = SuzzmeContextItem(
            sourceIdentifier: "event-tomorrow", content: "AI and DS class moved to 11 AM", timestamp: now,
            intent: .event, importance: .important,
            metadata: ["source": "calendar", "title": "AI and DS class", "start": ISO8601DateFormatter().string(from: tomorrowTime)]
        )
        let tomorrowReminder = SuzzmeContextItem(
            sourceIdentifier: "reminder-tomorrow", content: "AI Hackathon registration", timestamp: now,
            intent: .deadline, importance: .important,
            metadata: ["source": "reminders", "title": "AI Hackathon registration", "due": ISO8601DateFormatter().string(from: tomorrowTime), "completed": "false"]
        )
        let tomorrowAssignment = SuzzmeContextItem(
            sourceIdentifier: "assignment-tomorrow", content: "Submit the AI assignment", timestamp: now,
            intent: .task, importance: .important,
            metadata: ["source": "reminders", "title": "Submit the AI assignment", "due": ISO8601DateFormatter().string(from: tomorrowTime.addingTimeInterval(3_600)), "completed": "false"]
        )
        let tomorrowQuery = SuzzmeContextQuery.infer(from: "What matters tomorrow?", now: now)
        expect(tomorrowQuery.sources == [.calendar, .reminders], "tomorrow overview requests calendar and reminders")
        await core.clearSession()
        let tomorrow = try await core.respond(
            to: "What matters tomorrow?",
            sources: [ProductContextSource(identifier: "tomorrow", items: [tomorrowEvent, tomorrowReminder, tomorrowAssignment])],
            query: tomorrowQuery, existingFingerprints: [], progress: { _ in }
        )
        expect(tomorrow.text.contains("what matters tomorrow"), "tomorrow overview has correct temporal framing")
        expect(tomorrow.text.contains("AI and DS") && tomorrow.text.contains("Hackathon"), "tomorrow overview combines events and deadlines")

        let assignmentFollowUp = try await core.respond(
            to: "What assignment is due?", sources: [],
            query: SuzzmeContextQuery.infer(from: "What assignment is due?", now: now),
            existingFingerprints: [], progress: { _ in }
        )
        expect(assignmentFollowUp.text.contains("AI assignment"), "summary follow-up resolves due assignment")

        let changedFollowUp = try await core.respond(
            to: "What changed with my class?", sources: [],
            query: SuzzmeContextQuery.infer(from: "What changed with my class?", now: now),
            existingFingerprints: [], progress: { _ in }
        )
        expect(changedFollowUp.text.contains("moved to 11 AM"), "summary follow-up resolves a meaningful change")

        let registrationFollowUp = try await core.respond(
            to: "What was that registration?", sources: [],
            query: SuzzmeContextQuery.infer(from: "What was that registration?", now: now),
            existingFingerprints: [], progress: { _ in }
        )
        expect(registrationFollowUp.text.contains("Hackathon"), "summary follow-up resolves referenced registration")

        let reminderRequestID = UUID()
        let reminderPlan = try await core.respond(
            to: "Remind me tomorrow.", sources: [], query: .init(), requestID: reminderRequestID,
            existingFingerprints: [], progress: { _ in }
        )
        expect(reminderPlan.action?.status == .awaitingConfirmation && reminderPlan.text.contains("Hackathon"), "referential reminder enters central confirmation pipeline")
        if let actionID = reminderPlan.action?.id {
            let cancelled = try await core.respond(
                to: "cancel", sources: [], query: .init(), requestID: reminderRequestID,
                confirmationActionID: actionID, existingFingerprints: [], progress: { _ in }
            )
            expect(cancelled.action?.status == .cancelled, "referential reminder keeps central cancellation ownership")
        } else {
            expect(false, "referential reminder keeps central cancellation ownership")
        }

        let namedFollowUp = try await core.respond(
            to: "When is the Operating Systems lecture?", sources: [calendar, reminders],
            query: SuzzmeContextQuery.infer(from: "When is the Operating Systems lecture?", now: now),
            existingFingerprints: [], progress: { _ in }
        )
        expect(namedFollowUp.text.contains("Operating Systems"), "named summary follow-up resolves grounded item")

        await core.clearSession()
        _ = try await core.respond(
            to: "What is my schedule today?", sources: [calendar],
            query: SuzzmeContextQuery.infer(from: "What is my schedule today?", now: now),
            existingFingerprints: [], progress: { _ in }
        )
        let followUp = try await core.respond(
            to: "What time is it?", sources: [calendar],
            query: SuzzmeContextQuery.infer(from: "What time is it?", now: now),
            existingFingerprints: [], progress: { _ in }
        )
        expect(followUp.text.contains("Operating Systems"), "follow-up resolves active event")
        expect(!followUp.text.contains("couldn’t find anything relevant"), "follow-up stays grounded")

        let session = SessionMemoryEngine()
        await session.remember(context: [calendarItem])
        let changed = SuzzmeContextItem(
            sourceIdentifier: "event-1", content: "Operating Systems lecture moved", timestamp: now.addingTimeInterval(1),
            intent: .event, importance: .important,
            metadata: ["source": "calendar", "title": "Operating Systems lecture moved", "start": ISO8601DateFormatter().string(from: eventTime.addingTimeInterval(1_800))]
        )
        await session.remember(context: [changed])
        let current = await session.snapshot().contextItems
        expect(current.count == 1 && current.first?.content == changed.content, "authoritative source update replaces stale session fact")

        let overdue = SuzzmeContextItem(
            sourceIdentifier: "overdue-1", content: "Finish DSA assignment", timestamp: now.addingTimeInterval(-86_400),
            intent: .reminder, importance: .important,
            metadata: ["source": "reminders", "title": "Finish DSA assignment", "due": ISO8601DateFormatter().string(from: now.addingTimeInterval(-3_600)), "completed": "false"]
        )
        let overdueSnapshot = try await proactive.prepare(from: [ProductContextSource(identifier: "overdue", items: [overdue])], now: now)
        expect(overdueSnapshot.briefing?.items.contains(where: { $0.summary.contains("DSA") }) == true, "unfinished overdue reminder remains useful")

        let duplicateSnapshot = try await proactive.prepare(from: [ProductContextSource(identifier: "duplicate", items: [calendarItem, calendarItem])], now: now)
        expect(duplicateSnapshot.dailyContext?.entries.filter { $0.sourceReference == "event-1" }.count == 1, "duplicate source objects consolidate")

        var preferences = try await proactive.preferences()
        preferences.briefingHour = 17; preferences.briefingMinute = 35
        try await proactive.updatePreferences(preferences)
        let reopened = ProactiveIntelligenceEngine(store: ProactiveIntelligenceStore(fileURL: root.appendingPathComponent("proactive.json")))
        let restored = try await reopened.preferences()
        expect(restored.briefingHour == 17 && restored.briefingMinute == 35, "daily summary time survives restart")

        let futureDay = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: now)) ?? now
        let allDay = SuzzmeContextItem(
            sourceIdentifier: "all-day-acceptance", content: "Acceptance all-day event", timestamp: now,
            intent: .event, importance: .normal,
            metadata: ["source": "calendar", "title": "Acceptance all-day event", "allDay": "true",
                       "start": ISO8601DateFormatter().string(from: futureDay),
                       "end": ISO8601DateFormatter().string(from: futureDay.addingTimeInterval(86_400))],
            expiration: futureDay.addingTimeInterval(86_400)
        )
        let allDaySnapshot = try await core.prepareProactiveBriefing(from: [ProductContextSource(identifier: "calendar", items: [allDay])])
        expect(allDaySnapshot.briefing?.items.first?.isAllDay == true, "live Calendar all-day flag survives summary conversion")
        expect(allDaySnapshot.dailyContext?.activeEntries.first?.isAllDay == true, "Today context preserves all-day semantics")
        let dateFormatter = DateFormatter(); dateFormatter.dateStyle = .medium; dateFormatter.timeStyle = .none
        expect(allDaySnapshot.briefing?.narration.contains(dateFormatter.string(from: futureDay)) == true,
               "future summary narration includes the actual date")
        expect(allDaySnapshot.briefing?.narration.contains("all-day event") == true,
               "all-day narration does not claim a midnight appointment")
        expect(allDaySnapshot.briefing?.sections.contains(where: { $0.kind == .today }) == false,
               "future Calendar event is not placed in Today section")
        if let item = allDaySnapshot.briefing?.items.first {
            var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any] ?? [:]
            legacy.removeValue(forKey: "isAllDay")
            let decoded = try JSONDecoder().decode(ProactiveBriefingItem.self, from: JSONSerialization.data(withJSONObject: legacy))
            expect(decoded.isAllDay == nil, "pre-existing summary JSON still decodes without all-day field")
        } else { expect(false, "pre-existing summary JSON still decodes without all-day field") }

        let observed = InformationObservation(externalID: "all-day-information", title: "All-day information event", modifiedAt: now,
                                              effectiveAt: futureDay, effectiveUntil: futureDay.addingTimeInterval(86_400), isAllDay: true)
        if let normalized = InformationNormalizer.normalize(observed, source: .calendar, now: now) {
            expect(StoredInformationEvent(normalized).value?.isAllDay == true, "information persistence conversion retains authoritative all-day flag")
            var timed = observed; timed.isAllDay = false
            let timedValue = InformationNormalizer.normalize(timed, source: .calendar, now: now)
            expect(timedValue?.fingerprint != normalized.fingerprint, "all-day change invalidates semantic fingerprint")
            expect(timedValue?.isAllDay == false, "midnight timed event is not inferred to be all-day")
            let database = root.appendingPathComponent("all-day.sqlite")
            let configuration = ModelConfiguration("AllDayAcceptance", url: database, cloudKitDatabase: .none)
            do {
                let container = try ModelContainer(for: StoredInformationEvent.self, StoredInformationSource.self, configurations: configuration)
                let context = ModelContext(container)
                context.insert(StoredInformationEvent(normalized)); try context.save()
            }
            let reopenedDatabase = try ModelContainer(for: StoredInformationEvent.self, StoredInformationSource.self, configurations: configuration)
            let reopenedRows = try ModelContext(reopenedDatabase).fetch(FetchDescriptor<StoredInformationEvent>())
            expect(reopenedRows.first?.value?.isAllDay == true, "all-day flag survives disk store reopen")
            let intakeStore = InformationStore(modelContainer: reopenedDatabase)
            try await intakeStore.setEnabled(.calendar, enabled: true)
            let cycle = try await intakeStore.begin(.calendar, now: now)
            try await intakeStore.commit(.init(observations: [observed], complete: false,
                                               window: DateInterval(start: now, duration: 14 * 86400)), cycle: cycle, now: now)
            let information = InformationEngine(registry: .init([ProductInformationSource()]), store: intakeStore)
            let informationProactive = ProactiveIntelligenceEngine(
                store: ProactiveIntelligenceStore(fileURL: root.appendingPathComponent("information-proactive.json")), information: information)
            let informationSummary = try await informationProactive.prepare(from: [], now: now)
            expect(informationSummary.briefing?.items.first?.isAllDay == true, "persisted information reaches summary with all-day semantics")
            expect(informationSummary.briefing?.narration.contains("all-day event") == true,
                   "information-backed summary does not narrate midnight")


        } else { expect(false, "all-day information normalization succeeds") }

        print("Product flow checks passed: \(passed)")
        print("Product flow checks failed: \(failed)")
        if failed != 0 { exit(1) }
    }
}
