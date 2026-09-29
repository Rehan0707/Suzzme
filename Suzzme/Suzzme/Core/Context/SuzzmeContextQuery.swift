import Foundation

enum SuzzmeContextSourceKind: String, Sendable, CaseIterable, Identifiable {
    case calendar, reminders, contacts
    var id: String { rawValue }
}

enum SuzzmeContactDetail: Sendable { case identity, email, phone }

struct SuzzmeContextQuery: Sendable {
    let sources: Set<SuzzmeContextSourceKind>
    let dateRange: DateInterval?
    let entities: [String]
    let contactDetail: SuzzmeContactDetail
    let limit: Int

    init(sources: Set<SuzzmeContextSourceKind> = Set(SuzzmeContextSourceKind.allCases), dateRange: DateInterval? = nil, entities: [String] = [], contactDetail: SuzzmeContactDetail = .identity, limit: Int = 12) {
        self.sources = sources
        self.dateRange = dateRange
        self.entities = entities
        self.contactDetail = contactDetail
        self.limit = limit
    }

    static func infer(from text: String, now: Date = .now, calendar: Calendar = .current) -> Self {
        let lower = text.lowercased()
        let range: DateInterval?
        func dayRange(for date: Date) -> DateInterval {
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        }
        if lower.contains("overdue") {
            range = DateInterval(start: .distantPast, end: now)
        } else if lower.contains("tomorrow") {
            range = dayRange(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        } else if lower.contains("next week") {
            let weekday = calendar.component(.weekday, from: now)
            let untilMonday = (9 - weekday) % 7
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: untilMonday == 0 ? 7 : untilMonday, to: now) ?? now)
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
            range = DateInterval(start: start, end: end)
        } else if lower.contains("this week") {
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
            range = DateInterval(start: start, end: end)
        } else if lower.contains("today") || lower.contains("tonight") || lower.contains("this morning") || lower.contains("this afternoon") || lower.contains("this evening") {
            range = dayRange(for: now)
        } else {
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: now) ?? now
            range = DateInterval(start: now, end: end)
        }
        let words = text.split(whereSeparator: { !$0.isLetter }).map(String.init)
        let questionWords: Set<String> = ["What", "When", "Who", "Do", "Does", "Is", "My", "I", "The", "Can", "Have"]
        let names = words.filter { $0.first?.isUppercase == true && !questionWords.contains($0) }
        // Ask only the source that the query actually needs. Starting with every
        // source made unrelated conversation depend on Contacts permission and
        // caused harmless phrases to fail before the assistant could answer.
        var sources: Set<SuzzmeContextSourceKind> = []
        if lower.contains("email") || lower.contains("number") || lower.contains("phone") || lower.contains("contact") {
            sources.insert(.contacts)
        }
        if lower.contains("reminder") || lower.contains("finish") || lower.contains("need to do") || lower.contains("assignment") || lower.contains("task") || lower.contains("deadline") || lower.contains("due") {
            sources.insert(.reminders)
        }
        if lower.contains("meeting") || lower.contains("calendar") || lower.contains("schedule") || lower.contains("event") || lower.contains("class") || lower.contains("who is attending") || lower.contains("who’s attending") || lower.contains("who is going") {
            sources.insert(.calendar)
        }
        // A day overview is broader than a calendar lookup. Tasks due today and
        // unfinished reminders are part of the same grounded answer.
        if lower.contains("what do i have") || lower.contains("what matters") || lower.contains("daily summary") || lower.contains("summarize my day") {
            sources = [.calendar, .reminders]
        }
        if lower.contains("before my meeting") { sources = [.calendar, .reminders] }
        let detail: SuzzmeContactDetail = lower.contains("email") ? .email : (lower.contains("number") || lower.contains("phone") ? .phone : .identity)
        return .init(sources: sources, dateRange: range, entities: names, contactDetail: detail, limit: 12)
    }
}
