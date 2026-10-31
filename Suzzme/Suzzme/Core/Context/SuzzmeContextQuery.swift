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
        // A definition mentioning "event" or "task" is not permission to query
        // a person's calendar or reminders. Keep explanations read-only.
        if SuzzmeQuestionIntent.isGeneralExplanation(text) || SuzzmeQuestionIntent.isExtractionRequest(text) {
            return .init(sources: [], dateRange: nil)
        }
        let lower = text.lowercased()
        let intent = SuzzmeQuestionIntent.classify(text)
        let range: DateInterval?
        func dayRange(for date: Date) -> DateInterval {
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        }
        if intent == .unfinished {
            range = DateInterval(start: .distantPast, end: lower.contains("overdue") || lower.contains("behind on") ? now : (calendar.date(byAdding: .weekOfYear, value: 1, to: now) ?? now))
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
        } else if intent == .priorities {
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
        if intent == .priorities { sources = [.calendar, .reminders] }
        if intent == .unfinished { sources = [.reminders] }
        if lower.contains("before my meeting") { sources = [.calendar, .reminders] }
        if ["what should i do about this", "how should i plan", "fit this into my day", "when should i work on"].contains(where: lower.contains) {
            sources = [.calendar, .reminders]
        }
        let detail: SuzzmeContactDetail = lower.contains("email") ? .email : (lower.contains("number") || lower.contains("phone") ? .phone : .identity)
        return .init(sources: sources, dateRange: range, entities: names, contactDetail: detail, limit: 12)
    }
}

/// Application routing policy runs before probabilistic extraction. Capture
/// imperatives are distinct from questions even when they contain project/due words.
enum SuzzmeQuestionIntent: Equatable {
    case priorities, unfinished, question, capture, other
    static func classify(_ text: String) -> Self {
        let value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if ["remember ", "save ", "keep this in mind"].contains(where: value.hasPrefix)
            || isExplicitExtraction(value) { return .capture }
        if isGeneralExplanation(text) { return .question }
        if ["explain ", "define ", "compare ", "teach me ", "tell me more"].contains(where: value.hasPrefix) { return .question }
        let interrogative = ["what ", "when ", "where ", "who ", "why ", "how ", "do i ", "can i ", "is there ", "are there ", "anything "].contains(where: value.hasPrefix)
        guard interrogative || text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") else { return .other }
        if ["unfinished", "behind on", "overdue", "still needs to be done", "forget to finish"].contains(where: value.contains) { return .unfinished }
        if ["focus on", "work on", "attention", "important", "urgent", "prioritiz", "matters most"].contains(where: value.contains) { return .priorities }
        return .question
    }

    static func isGeneralExplanation(_ text: String) -> Bool {
        let value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let words = Set(value.split { !$0.isLetter }.map(String.init))
        guard words.isDisjoint(with: ["my", "our", "today", "tomorrow", "this", "that", "it"]) else { return false }
        return ["explain ", "define ", "compare ", "teach me ", "what is a ", "what is an ",
                "what is the difference ", "how does a ", "how does an "]
            .contains(where: value.hasPrefix)
    }

    /// Extraction needs a capture request or an actual commitment, rather than
    /// being the fallback for every phrase the lexical classifier did not know.
    /// Core's existing action and memory planners still run before this policy.
    static func isExtractionRequest(_ text: String) -> Bool {
        if classify(text) == .capture { return true }
        let value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Preserve the existing dated-commitment capture path (e.g. "Submit
        // the report before Friday"). A bare imperative such as "Name a color"
        // or "Add three to that result" supplies no capture authority.
        let commitment = #"^(?:submit|finish|deliver|pay|complete)\s+.+\b(?:by|before|today|tomorrow|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#
        return value.range(of: commitment, options: .regularExpression) != nil
    }

    private static func isExplicitExtraction(_ value: String) -> Bool {
        let directive = #"^(?:please\s+)?(?:extract|capture|organize)\s+(?:(?:the|these|following)\s+)?(?:facts|tasks|events|deadlines|reminders|items|information)\b"#
        return value.range(of: directive, options: .regularExpression) != nil
    }
}

/// Open commitments have no historical lower bound. Future-specific queries
/// retain their date scope; undated work belongs to general/current-day requests.
enum SuzzmeReminderSelection {
    static func includes(dueDate: Date?, completed: Bool, range: DateInterval?, now: Date, calendar: Calendar = .current) -> Bool {
        guard !completed else { return false }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let futureOnly = range.map { $0.start >= tomorrow } ?? false
        guard let dueDate else { return !futureOnly }
        guard let range else { return true }
        return dueDate < range.end && (!futureOnly || dueDate >= range.start)
    }
}
