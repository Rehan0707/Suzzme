import Foundation

@main
struct Step4Checks {
    static func main() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 9))!
        let tomorrow = SuzzmeContextQuery.infer(from: "What do I have tomorrow?", now: now, calendar: calendar)
        precondition(calendar.isDate(tomorrow.dateRange!.start, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now)!))
        let nextWeek = SuzzmeContextQuery.infer(from: "My meetings next week", now: now, calendar: calendar)
        precondition(nextWeek.dateRange?.duration == 7 * 24 * 60 * 60)
        let contactQuery = SuzzmeContextQuery.infer(from: "Do I have Aryan's email?", now: now, calendar: calendar)
        precondition(contactQuery.contactDetail == .email && contactQuery.entities == ["Aryan"])
        var dstCalendar = Calendar(identifier: .gregorian); dstCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let dstDate = dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 10))!
        let dstRange = SuzzmeContextQuery.infer(from: "tomorrow", now: dstDate, calendar: dstCalendar).dateRange!
        precondition(dstRange.end == dstCalendar.date(byAdding: .day, value: 1, to: dstRange.start))

        let formatter = ISO8601DateFormatter()
        let meetingDate = calendar.date(byAdding: .day, value: 1, to: now)!
        let reminderDate = calendar.date(byAdding: .hour, value: -2, to: meetingDate)!
        let event = SuzzmeContextItem(sourceIdentifier: "event-1", content: "Project Review", timestamp: now, entities: ["Aryan"], intent: .event, importance: .important, metadata: ["source": "calendar", "start": formatter.string(from: meetingDate), "allDay": "false"])
        let allDay = SuzzmeContextItem(sourceIdentifier: "event-2", content: "Campus holiday", timestamp: now, intent: .event, metadata: ["source": "calendar", "start": formatter.string(from: meetingDate), "allDay": "true"])
        let reminder = SuzzmeContextItem(sourceIdentifier: "reminder-1", content: "Finish project slides", timestamp: now, intent: .reminder, importance: .important, metadata: ["source": "reminders", "completed": "false", "due": formatter.string(from: reminderDate)])
        let contact = SuzzmeContextItem(sourceIdentifier: "contact-1", content: "Aryan Sharma", timestamp: now, entities: ["Aryan Sharma"], intent: .information, sensitivity: .sensitive, metadata: ["source": "contacts", "email": "aryan@example.com", "phone": ""])
        let engine = ContextEngine()
        let normalized = await engine.normalize([event, allDay, reminder, contact])
        precondition(normalized.count == 4 && normalized.allSatisfy { $0.sensitivity != .restricted })
        let fallback = BasicIntelligenceService(calendar: calendar)
        let router = IntelligenceRouter(pipeline: SuzzmeUnderstandingPipeline(primary: fallback, fallback: fallback))
        let schedule = try await router.route(text: "What do I have tomorrow?", context: normalized, existingFingerprints: [])
        precondition(schedule.route == .localContext && schedule.text.contains("Project Review"))
        let tasks = try await router.route(text: "What do I need to finish before my meeting tomorrow?", context: normalized, existingFingerprints: [])
        precondition(tasks.text.contains("Finish project slides"))
        let email = try await router.route(text: "Do I have Aryan's email?", context: normalized, existingFingerprints: [])
        precondition(email.text.contains("aryan@example.com"))
        let missing = try await router.route(text: "When is my meeting with Rahul?", context: normalized, existingFingerprints: [])
        precondition(missing.text.contains("couldn’t find"))
        let secondAryan = SuzzmeContextItem(sourceIdentifier: "contact-2", content: "Aryan Patel", timestamp: now, intent: .information, sensitivity: .sensitive, metadata: ["source": "contacts", "email": "aryan.p@example.com"])
        let ambiguous = try await router.route(text: "What is Aryan's email?", context: [contact, secondAryan], existingFingerprints: [])
        precondition(ambiguous.text.contains("more than one"))
        print("PASS: Step 4 query windows, grounded calendar/reminder/contact context, timezone-safe dates, and cross-source reasoning")
    }
}
