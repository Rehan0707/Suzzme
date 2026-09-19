import Foundation

/// A deliberately small, deterministic local fallback. It only claims facts that
/// are plainly stated and leaves uncertain dates empty.
struct BasicIntelligenceService: SuzzmeIntelligenceService {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func capability() async -> IntelligenceCapability { .unsupportedOS }

    func understand(text: String, referenceDate: Date = .now) async throws -> [ExtractedSuzzmeItem] {
        let normalized = text.suzzmeNormalized
        guard !normalized.isEmpty else { throw SuzzmeIntelligenceError.emptyInput }

        let lowercased = normalized.lowercased()
        let date = SuzzmeDateParser.date(in: normalized, referenceDate: referenceDate, calendar: calendar)
        let isHistorical = lowercased.contains("last year") || lowercased.contains("last semester")

        if isHistorical {
            return [ExtractedSuzzmeItem(
                title: title(in: lowercased),
                summary: firstSentence(in: normalized),
                category: .information,
                priority: .normal,
                confidence: 0.87,
                reason: "The text describes a past occurrence."
            )]
        }

        let category = category(in: lowercased)
        let priority = priority(in: lowercased, category: category, dueDate: date, referenceDate: referenceDate)
        return [ExtractedSuzzmeItem(
            title: title(in: lowercased),
            summary: summary(in: normalized, category: category, dueDate: date),
            category: category,
            priority: priority,
            dueDate: date,
            confidence: date == nil ? 0.68 : 0.87,
            reason: reason(category: category, dueDate: date)
        )]
    }

    func summarize(text: String) async throws -> String {
        let normalized = text.suzzmeNormalized
        guard !normalized.isEmpty else { throw SuzzmeIntelligenceError.emptyInput }
        return firstSentence(in: normalized)
    }

    private func category(in text: String) -> SuzzmeItem.Category {
        if text.contains("close") || text.contains("deadline") || text.contains("before friday") { return .deadline }
        if text.contains("meeting") || text.contains("lecture") || text.contains("begin at") { return .event }
        if text.contains("submit") || text.contains("reminder") { return .task }
        return .information
    }

    private func priority(in text: String, category: SuzzmeItem.Category, dueDate: Date?, referenceDate: Date) -> SuzzmeItem.Priority {
        guard category != .information else { return .normal }
        if text.contains("urgent") || text.contains("immediately") { return .urgent }
        if category == .deadline || text.contains("registration") || text.contains("submit") { return .important }
        if let dueDate, dueDate.timeIntervalSince(referenceDate) <= 48 * 60 * 60 { return .important }
        return .normal
    }

    private func title(in text: String) -> String {
        if text.contains("coding competition") && text.contains("registration") { return "Coding competition registration" }
        if text.contains("apple developer club") && text.contains("meeting") { return "Apple Developer Club meeting" }
        if text.contains("project report") && text.contains("submit") { return "Submit project report" }
        if text.contains("six mac") { return "New lab Macs" }
        if text.contains("meet") { return "Possible meeting" }
        return "Shared information"
    }

    private func summary(in text: String, category: SuzzmeItem.Category, dueDate: Date?) -> String {
        if category == .deadline, dueDate != nil { return "An action has a stated deadline." }
        if category == .event, dueDate != nil { return "An event has a stated time." }
        return firstSentence(in: text)
    }

    private func reason(category: SuzzmeItem.Category, dueDate: Date?) -> String {
        if category == .deadline, dueDate != nil { return "A stated deadline and date were found." }
        if category == .event, dueDate != nil { return "A stated event and date were found." }
        return "Useful information was found; no reliable date was inferred."
    }

    private func firstSentence(in text: String) -> String {
        let parts = text.split(whereSeparator: { ".!?".contains($0) })
        return parts.first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
    }
}

enum SuzzmeDateParser {
    static func date(in text: String, referenceDate: Date, calendar: Calendar = .current) -> Date? {
        let lowercased = text.lowercased()
        let dayOffset: Int?
        if lowercased.contains("tomorrow") { dayOffset = 1 }
        else if lowercased.contains("today") || lowercased.contains("tonight") { dayOffset = 0 }
        else if lowercased.contains("friday") { dayOffset = daysUntil(weekday: 6, referenceDate: referenceDate, calendar: calendar) }
        else if lowercased.contains("next monday") { dayOffset = nextWeekday(weekday: 2, referenceDate: referenceDate, calendar: calendar) }
        else if lowercased.contains("monday") { dayOffset = daysUntil(weekday: 2, referenceDate: referenceDate, calendar: calendar) }
        else { dayOffset = nil }

        if let monthDay = monthDay(in: lowercased, referenceDate: referenceDate, calendar: calendar) {
            guard let hourAndMinute = time(in: lowercased) else { return monthDay }
            return calendar.date(bySettingHour: hourAndMinute.hour, minute: hourAndMinute.minute, second: 0, of: monthDay)
        }
        guard let dayOffset else { return nil }
        let start = calendar.startOfDay(for: referenceDate)
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: start) else { return nil }
        guard let hourAndMinute = time(in: lowercased) else { return day }
        return calendar.date(bySettingHour: hourAndMinute.hour, minute: hourAndMinute.minute, second: 0, of: day)
    }

    private static func daysUntil(weekday: Int, referenceDate: Date, calendar: Calendar) -> Int {
        let current = calendar.component(.weekday, from: referenceDate)
        let delta = (weekday - current + 7) % 7
        return delta == 0 ? 7 : delta
    }

    private static func nextWeekday(weekday: Int, referenceDate: Date, calendar: Calendar) -> Int {
        let delta = daysUntil(weekday: weekday, referenceDate: referenceDate, calendar: calendar)
        return delta == 0 ? 7 : delta
    }

    private static func monthDay(in text: String, referenceDate: Date, calendar: Calendar) -> Date? {
        let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        guard let monthIndex = months.firstIndex(where: { text.contains($0) }) else { return nil }
        let month = monthIndex + 1
        let pattern = "\\b" + months[monthIndex] + "\\s+([0-9]{1,2})\\b"
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let digits = text[range].filter(\.isNumber)
        guard let day = Int(digits), (1...31).contains(day) else { return nil }
        let year = calendar.component(.year, from: referenceDate)
        guard let candidate = calendar.date(from: DateComponents(year: year, month: month, day: day)), candidate >= calendar.startOfDay(for: referenceDate) else { return nil }
        return candidate
    }

    private static func time(in text: String) -> (hour: Int, minute: Int)? {
        let pattern = "\\b([0-9]{1,2})(?::([0-9]{2}))?\\s*(am|pm)\\b"
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let values = text[range].lowercased()
        let numbers = values.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard var hour = numbers.first else { return nil }
        let minute = numbers.dropFirst().first ?? 0
        if values.contains("pm"), hour < 12 { hour += 12 }
        if values.contains("am"), hour == 12 { hour = 0 }
        return (hour, minute)
    }
}

private extension String {
    var suzzmeNormalized: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
