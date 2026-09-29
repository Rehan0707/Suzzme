import Foundation

/// Deterministic, deliberately narrow fallback planner. Foundation Models may
/// propose an equivalent plan later, but every plan is validated here before it
/// enters the registry.
struct SuzzmeActionPlanner: Sendable {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func plan(for text: String, requestID: UUID, now: Date = .now) throws -> SuzzmeActionPlan? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = normalized.lowercased().replacingOccurrences(of: "in two hours", with: "in 2 hours").replacingOccurrences(of: "in one hour", with: "in 1 hour")
        guard !normalized.isEmpty else { return nil }
        guard normalized.count <= 2000 else { throw SuzzmeCapabilityError.limitExceeded }
        if lowered.trimmingCharacters(in: .punctuationCharacters) == "delete all completed reminders" {
            return .init(requestID: requestID, capability: .reminders, operation: .delete, payload: .completedReminders([]), risk: .destructive)
        }
        if lowered.contains("after class") { throw SuzzmeCapabilityError.malformedPlan }
        // Repetition and broad scopes require a separate explicit scope protocol.
        if lowered.range(of: #"\b(all|every|recurring|weekly|daily|monthly)\b"#, options: .regularExpression) != nil,
           ["remind", "create", "add ", "schedule", "delete", "cancel", "move", "mark"].contains(where: lowered.hasPrefix) {
            throw SuzzmeCapabilityError.limitExceeded
        }

        if ["send ", "email ", "message ", "run shortcut", "open terminal"].contains(where: lowered.hasPrefix) { throw SuzzmeCapabilityError.unsupported }

        if lowered.hasPrefix("remind me") || lowered.hasPrefix("create reminder") {
            let title = reminderTitle(in: normalized)
            guard !title.isEmpty else { throw SuzzmeCapabilityError.malformedPlan }
            let dueDate = try resolveDate(in: lowered, now: now, requiresTime: false)
            return .init(requestID: requestID, capability: .reminders, operation: .create, payload: .reminder(.init(title: title, dueDate: dueDate)), risk: .consequentialWrite)
        }
        if lowered.hasPrefix("mark ") && (lowered.contains(" reminder") || lowered.hasSuffix(" done")) {
            let title = strippedTarget(normalized, prefixes: ["mark "], suffixes: [" reminder done", " done"])
            guard !title.isEmpty else { throw SuzzmeCapabilityError.malformedPlan }
            return .init(requestID: requestID, capability: .reminders, operation: .complete, payload: .reminder(.init(title: title)), risk: .consequentialWrite)
        }
        if lowered.hasPrefix("delete ") && lowered.contains("reminder") {
            let title = strippedTarget(normalized, prefixes: ["delete "], suffixes: [" reminder"])
            guard !title.isEmpty else { throw SuzzmeCapabilityError.malformedPlan }
            return .init(requestID: requestID, capability: .reminders, operation: .delete, payload: .reminder(.init(title: title)), risk: .destructive)
        }
        if lowered.hasPrefix("move ") && lowered.contains("reminder") {
            let title = strippedTarget(normalized, prefixes: ["move "], suffixes: [" reminder to", " to"])
            let dueDate = try resolveDate(in: lowered, now: now, requiresTime: true)
            guard !title.isEmpty, let dueDate else { throw SuzzmeCapabilityError.malformedPlan }
            return .init(requestID: requestID, capability: .reminders, operation: .update, payload: .reminder(.init(title: title, dueDate: dueDate)), risk: .consequentialWrite)
        }
        if lowered.hasPrefix("add ") || lowered.hasPrefix("create event") || lowered.hasPrefix("schedule ") {
            guard lowered.contains("tomorrow") || lowered.contains("today") || lowered.contains(" at ") || lowered.contains(" from ") || lowered.contains(" in ") || lowered.contains("next ") else { return nil }
            let title = eventTitle(in: normalized)
            guard !title.isEmpty else { throw SuzzmeCapabilityError.malformedPlan }
            let start = try resolveDate(in: lowered, now: now, requiresTime: true)
            guard let start else { throw SuzzmeCapabilityError.malformedPlan }
            let end = try endDate(in: lowered, start: start)
            return .init(requestID: requestID, capability: .calendar, operation: .create, payload: .calendar(.init(title: title, startDate: start, endDate: end)), risk: .consequentialWrite)
        }
        if lowered.hasPrefix("cancel ") && (lowered.contains("event") || lowered.contains("meeting") || lowered.contains("gym")) {
            let title = strippedTarget(normalized, prefixes: ["cancel "], suffixes: [" event"])
            guard !title.isEmpty else { throw SuzzmeCapabilityError.malformedPlan }
            return .init(requestID: requestID, capability: .calendar, operation: .delete, payload: .calendar(.init(title: title, targetDay: targetDay(in: lowered, now: now))), risk: .destructive)
        }
        if lowered.hasPrefix("move ") && (lowered.contains("event") || lowered.contains("meeting") || lowered.contains("gym")) {
            let title = strippedTarget(normalized, prefixes: ["move "], suffixes: [" event to", " to"])
            let start = try resolveDate(in: lowered, now: now, requiresTime: true)
            guard !title.isEmpty, let start else { throw SuzzmeCapabilityError.malformedPlan }
            return .init(requestID: requestID, capability: .calendar, operation: .update, payload: .calendar(.init(title: title, startDate: start, targetDay: targetDay(in: lowered, now: now))), risk: .consequentialWrite)
        }
        return nil
    }

    private func reminderTitle(in text: String) -> String {
        let lowered = text.lowercased()
        let prefixes = ["remind me to ", "remind me ", "create reminder to ", "create reminder "]
        guard let prefix = prefixes.first(where: { lowered.hasPrefix($0) }) else { return "" }
        let value = String(text.dropFirst(prefix.count))
        if !prefix.hasSuffix("to "), let range = value.range(of: " to ", options: .caseInsensitive),
           ["tonight", "tomorrow", "today", "in ", "next "].contains(where: { value.lowercased().hasPrefix($0) }) {
            return String(value[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return prefixBeforeTemporalTerm(value, terms: ["today", "tonight", "tomorrow", "at", "next", "in", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"])
    }

    private func eventTitle(in text: String) -> String {
        let lowered = text.lowercased()
        let prefixes = ["add ", "create event ", "schedule "]
        guard let prefix = prefixes.first(where: { lowered.hasPrefix($0) }) else { return "" }
        let value = String(text.dropFirst(prefix.count))
        return prefixBeforeTemporalTerm(value, terms: ["today", "tonight", "tomorrow", "at", "from", "next", "in", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"])
    }

    private func prefixBeforeTemporalTerm(_ value: String, terms: [String]) -> String {
        let lower = value.lowercased()
        let ranges = terms.compactMap { term in lower.range(of: " \(term) ") ?? lower.range(of: " \(term)") }
        guard let range = ranges.min(by: { $0.lowerBound < $1.lowerBound }) else { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        return String(value[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func strippedTarget(_ text: String, prefixes: [String], suffixes: [String]) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let prefix = prefixes.first(where: { value.lowercased().hasPrefix($0) }) { value.removeFirst(prefix.count) }
        if let suffix = suffixes.first(where: { value.lowercased().contains($0) }), let range = value.lowercased().range(of: suffix) { value = String(value[..<range.lowerBound]) }
        for prefix in ["my ", "tomorrow's ", "today's ", "tomorrow’s ", "today’s "] {
            if value.lowercased().hasPrefix(prefix) { value.removeFirst(prefix.count) }
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func targetDay(in text: String, now: Date) -> Date? {
        if text.contains("tomorrow") { return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) }
        if text.contains("today") { return calendar.startOfDay(for: now) }
        return nil
    }

    private func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }

    private func resolveDate(in text: String, now: Date, requiresTime: Bool) throws -> Date? {
        if let relative = captures(#"\bin ([0-9]{1,3}) (hours?|minutes?)\b"#, in: text), let count = Int(relative[1]), count > 0 {
            let date = now.addingTimeInterval(Double(count * (relative[2].hasPrefix("hour") ? 3600 : 60)))
            return calendar.dateInterval(of: .minute, for: date)?.start
        }
        var day = calendar.startOfDay(for: now)
        var hasDay = text.range(of: #"\b(today|tonight|tomorrow)\b"#, options: .regularExpression) != nil
        if text.contains("tomorrow") {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { throw SuzzmeCapabilityError.malformedPlan }
            day = next
        }
        let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        for (index, weekday) in weekdays.enumerated() where text.range(of: "\\b" + weekday + "\\b", options: .regularExpression) != nil {
            var offset = (index + 1 - calendar.component(.weekday, from: day) + 7) % 7
            if offset == 0 { offset = 7 }
            guard let next = calendar.date(byAdding: .day, value: offset, to: day) else { throw SuzzmeCapabilityError.malformedPlan }
            day = next; hasDay = true
        }
        guard let clock = try time(in: text) else {
            if requiresTime { throw SuzzmeCapabilityError.malformedPlan }
            return hasDay ? day : nil
        }
        let result = try exactTime(clock, on: day)
        // A time alone must not silently become tomorrow when it has passed.
        guard hasDay || result > now else { throw SuzzmeCapabilityError.malformedPlan }
        return result
    }

    private func time(in text: String) throws -> (hour: Int, minute: Int)? {
        guard let values = captures(#"\b(?:at|from|to)\s+([0-9]{1,2})(?::([0-9]{2}))?\s*(am|pm)?\b"#, in: text) else { return nil }
        guard var hour = Int(values[1]), let minute = Int(values[2].isEmpty ? "0" : values[2]), (0...59).contains(minute) else { throw SuzzmeCapabilityError.malformedPlan }
        if values[3].isEmpty, values[1].count == 2, !values[2].isEmpty, (0...23).contains(hour) {
            return (hour, minute)
        }
        if values[3].isEmpty {
            guard text.contains("tonight"), (1...11).contains(hour) else { throw SuzzmeCapabilityError.malformedPlan }
            hour += 12
        } else {
            guard (1...12).contains(hour) else { throw SuzzmeCapabilityError.malformedPlan }
            hour = hour % 12 + (values[3] == "pm" ? 12 : 0)
        }
        return (hour, minute)
    }

    private func exactTime(_ clock: (hour: Int, minute: Int), on day: Date) throws -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = clock.hour; components.minute = clock.minute; components.second = 0
        let anchor = day.addingTimeInterval(-1)
        guard let first = calendar.nextDate(after: anchor, matching: components, matchingPolicy: .strict, repeatedTimePolicy: .first),
              let last = calendar.nextDate(after: anchor, matching: components, matchingPolicy: .strict, repeatedTimePolicy: .last),
              first == last, calendar.isDate(first, inSameDayAs: day) else { throw SuzzmeCapabilityError.malformedPlan }
        return first
    }

    private func endDate(in text: String, start: Date) throws -> Date {
        guard let range = text.range(of: " to "), let clock = try time(in: String(text[range.lowerBound...])) else {
            // The fallback offers an explicit one-hour duration in confirmation.
            return start.addingTimeInterval(3600)
        }
        let end = try exactTime(clock, on: calendar.startOfDay(for: start))
        guard end > start else { throw SuzzmeCapabilityError.malformedPlan }
        return end
    }
}
