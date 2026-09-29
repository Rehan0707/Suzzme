import Foundation

enum SuzzmeRoute: Sendable, Equatable { case deterministic, onDeviceIntelligence, localContext }

struct SuzzmeRoutedResponse: Sendable {
    let text: String
    let route: SuzzmeRoute
    let intent: SuzzmeContextIntent
    let extractedItems: [SuzzmeItem]
}

actor IntelligenceRouter {
    private let pipeline: SuzzmeUnderstandingPipeline
    init(pipeline: SuzzmeUnderstandingPipeline = SuzzmeUnderstandingPipeline()) { self.pipeline = pipeline }

    func route(text: String, context: [SuzzmeContextItem], conversation: [SuzzmeSessionTurn] = [], existingFingerprints: Set<String>) async throws -> SuzzmeRoutedResponse {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw SuzzmeIntelligenceError.emptyInput }
        let conversationalQuery = query.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if ["help", "what can you do", "what can you help me with", "how can you help me"].contains(conversationalQuery) {
            return .init(
                text: "I can help you understand your day, summarize authorized calendar events and reminders, and answer follow-up questions. You can type or talk to me. I can also propose supported changes to your calendar and reminders, which need your confirmation. Choose what I may access in Sources.",
                route: .deterministic, intent: .question, extractedItems: []
            )
        }
        if let followUp = groundedFollowUp(query, context: context, conversation: conversation) {
            return followUp
        }
        if asksForDailyOverview(query) {
            return groundedDay(context, request: query)
        }
        if asksForTodayFocus(query), !context.isEmpty {
            return groundedDay(context, request: query)
        }
        if let name = namedMeeting(in: query) {
            let events = context.filter { $0.metadata["source"] == "calendar" && ($0.content.localizedCaseInsensitiveContains(name) || $0.entities.contains { $0.localizedCaseInsensitiveContains(name) }) }
            return groundedEvents(events, empty: "I couldn’t find a meeting with \(name).")
        }
        if asksForTodaySchedule(query) {
            let events = context.filter { $0.metadata["source"] == "calendar" }
            return groundedEvents(events, empty: "I couldn’t find anything on your calendar for that time.")
        }
        if asksBeforeMeeting(query) {
            let events = context.filter { $0.metadata["source"] == "calendar" }.sorted { startDate($0) < startDate($1) }
            guard let event = events.first else { return .init(text: "I couldn’t find a meeting to plan around.", route: .localContext, intent: .question, extractedItems: []) }
            let reminders = context.filter { $0.metadata["source"] == "reminders" && $0.metadata["completed"] != "true" && dueDate($0).map { $0 <= startDate(event) } == true }
            let reminderText = reminders.isEmpty ? "I couldn’t find an incomplete reminder due before it." : reminders.prefix(3).map(reminderDescription).joined(separator: " ")
            return .init(text: "\(eventDescription(event)) \(reminderText)", route: .localContext, intent: .question, extractedItems: [])
        }
        if asksForReminders(query) {
            let reminders = context.filter { $0.metadata["source"] == "reminders" && $0.metadata["completed"] != "true" }
            let text = reminders.isEmpty ? "I couldn’t find any incomplete reminders for that time." : reminders.prefix(3).map { reminderDescription($0) }.joined(separator: " ")
            return .init(text: text, route: .localContext, intent: .question, extractedItems: [])
        }
        if asksForContactDetail(query) {
            let contacts = context.filter { $0.metadata["source"] == "contacts" }
            if contacts.count > 1 { return .init(text: "I found more than one matching contact. Please use a full name.", route: .localContext, intent: .question, extractedItems: []) }
            if let contact = contacts.first {
                let value = query.lowercased().contains("email") ? contact.metadata["email"] : contact.metadata["phone"]
                let text = value?.isEmpty == false ? "\(contact.content): \(value!)." : "I found \(contact.content), but that detail isn’t available in the contact card."
                return .init(text: text, route: .localContext, intent: .question, extractedItems: [])
            }
            return .init(text: "I couldn’t find a matching contact.", route: .localContext, intent: .question, extractedItems: [])
        }
        if asksAboutAttendance(query), let relevant = context.first(where: { $0.intent == .event }) {
            let attendees = relevant.entities
            let text = attendees.isEmpty ? "I know about \(relevant.content), but I don’t have attendee information in your available context." : "\(relevant.content). Attending: \(attendees.joined(separator: ", "))."
            return .init(text: text, route: .localContext, intent: .question, extractedItems: [])
        }
        let result = try await pipeline.process(query, existingFingerprints: existingFingerprints)
        let phrase = result.items.first.map { "I noticed \($0.title). \($0.summary)" } ?? "I couldn’t find anything relevant in your available context."
        return .init(text: phrase, route: result.capability.usesFoundationModels ? .onDeviceIntelligence : .deterministic, intent: .information, extractedItems: result.items)
    }

    private func groundedEvents(_ events: [SuzzmeContextItem], empty: String) -> SuzzmeRoutedResponse {
        guard !events.isEmpty else { return .init(text: empty, route: .localContext, intent: .question, extractedItems: []) }
        return .init(text: events.prefix(3).map(eventDescription).joined(separator: " "), route: .localContext, intent: .question, extractedItems: [])
    }

    private func eventDescription(_ item: SuzzmeContextItem) -> String {
        guard let rawDate = item.metadata["start"], let date = ISO8601DateFormatter().date(from: rawDate) else { return item.content }
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = item.metadata["allDay"] == "true" ? .none : .short
        return "\(item.content) — \(formatter.string(from: date))."
    }

    private func reminderDescription(_ item: SuzzmeContextItem) -> String { "\(item.content)." }
    private func startDate(_ item: SuzzmeContextItem) -> Date { ISO8601DateFormatter().date(from: item.metadata["start"] ?? "") ?? .distantFuture }
    private func dueDate(_ item: SuzzmeContextItem) -> Date? { ISO8601DateFormatter().date(from: item.metadata["due"] ?? "") }
    private func asksBeforeMeeting(_ text: String) -> Bool { text.lowercased().contains("before") && text.lowercased().contains("meeting") }
    private func asksForTodaySchedule(_ text: String) -> Bool { let lower = text.lowercased(); return (lower.contains("what do i have") || lower.contains("next meeting") || lower.contains("schedule")) && (lower.contains("today") || lower.contains("meeting") || lower.contains("tomorrow")) }
    private func asksForReminders(_ text: String) -> Bool { let lower = text.lowercased(); return lower.contains("need to do") || lower.contains("reminder") || lower.contains("finish") || lower.contains("overdue") }
    private func asksForContactDetail(_ text: String) -> Bool { let lower = text.lowercased(); return lower.contains("email") || lower.contains("number") || lower.contains("phone") }
    private func namedMeeting(in text: String) -> String? { guard text.lowercased().contains("meeting with") else { return nil }; return text.components(separatedBy: "with").last?.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }

    private func asksForTodayFocus(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("focus") && (lower.contains("today") || lower.contains("need"))
    }

    private func asksForDailyOverview(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("what do i have today")
            || lower.contains("what do i have tomorrow")
            || lower.contains("what matters today")
            || lower.contains("what matters tomorrow")
            || lower.contains("daily summary")
            || lower.contains("summarize my day")
            || lower.contains("tell me about my day")
    }

    private func groundedDay(_ context: [SuzzmeContextItem], request: String) -> SuzzmeRoutedResponse {
        var seen = Set<String>()
        let useful = context.filter {
            $0.intent == .event || $0.intent == .reminder || $0.intent == .task || $0.intent == .deadline
                || $0.metadata["source"] == "proactive-briefing"
        }.filter { item in
            let key = item.metadata["fingerprint"] ?? "\(item.sourceIdentifier)|\(item.content.lowercased())"
            return seen.insert(key).inserted
        }.sorted { lhs, rhs in
            let left = effectiveDate(lhs) ?? .distantFuture
            let right = effectiveDate(rhs) ?? .distantFuture
            if left != right { return left < right }
            return lhs.content < rhs.content
        }
        guard !useful.isEmpty else {
            let period = request.lowercased().contains("tomorrow") ? "tomorrow" : "for today"
            return .init(text: "I couldn’t find an event, deadline, or unfinished reminder \(period) in the context available to me.", route: .localContext, intent: .question, extractedItems: [])
        }
        let details = useful.prefix(5).map(dayDescription).joined(separator: " ")
        let opening = request.lowercased().contains("tomorrow") ? "Here’s what matters tomorrow." : "Here’s your day."
        return .init(text: "\(opening) \(details)", route: .localContext, intent: .question, extractedItems: [])
    }

    private func groundedFollowUp(_ text: String, context: [SuzzmeContextItem], conversation: [SuzzmeSessionTurn]) -> SuzzmeRoutedResponse? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let asksWhen = lower == "when" || lower == "what time" || lower.hasPrefix("when is ") || lower.hasPrefix("what time is ")
        let asksWhere = lower == "where" || lower.hasPrefix("where is ")
        let asksMore = lower == "tell me more" || lower.hasPrefix("tell me more about ") || lower.hasPrefix("what about ")
        let asksChanged = lower.hasPrefix("what changed")
        let asksDueItem = lower.contains("what") && lower.contains("due")
            && ["assignment", "task", "deadline", "reminder"].contains(where: lower.contains)
        let asksReferencedItem = lower.hasPrefix("what was ") || lower.hasPrefix("what is that ")
        guard asksWhen || asksWhere || asksMore || asksChanged || asksDueItem || asksReferencedItem else { return nil }
        let reference = lower
            .replacingOccurrences(of: "what time is ", with: "")
            .replacingOccurrences(of: "when is ", with: "")
            .replacingOccurrences(of: "where is ", with: "")
            .replacingOccurrences(of: "tell me more about ", with: "")
            .replacingOccurrences(of: "what about ", with: "")
            .replacingOccurrences(of: "what changed with ", with: "")
            .replacingOccurrences(of: "what changed about ", with: "")
            .replacingOccurrences(of: "what was ", with: "")
            .replacingOccurrences(of: "what is that ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let pronouns: Set<String> = ["", "it", "that", "this", "the event", "the reminder"]
        var matches: [SuzzmeContextItem]
        if !pronouns.contains(reference) {
            let ignored: Set<String> = ["what", "when", "where", "which", "was", "that", "this", "the", "with", "about", "from", "your", "my", "has", "have", "is", "are", "due", "changed"]
            let terms = Set(reference.split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count > 2 && !ignored.contains($0) })
            matches = context.filter { item in
                let value = "\(item.metadata["title"] ?? "") \(item.content) \(item.entities.joined(separator: " "))".lowercased()
                return !terms.isEmpty && terms.contains(where: value.contains)
            }
            if let lastAnswer = conversation.last(where: { $0.role == .assistant })?.text {
                let mentioned = matches.filter { item in
                    lastAnswer.localizedCaseInsensitiveContains(item.content)
                        || item.metadata["title"].map { lastAnswer.localizedCaseInsensitiveContains($0) } == true
                }
                if !mentioned.isEmpty { matches = mentioned }
            }
        } else if let lastAnswer = conversation.last(where: { $0.role == .assistant })?.text {
            matches = context.filter { item in
                lastAnswer.localizedCaseInsensitiveContains(item.content)
                    || item.metadata["title"].map { lastAnswer.localizedCaseInsensitiveContains($0) } == true
            }
        } else {
            return nil
        }
        if matches.isEmpty, context.count == 1 { matches = context }
        guard !matches.isEmpty else { return nil }
        guard matches.count == 1, let item = matches.first else {
            return .init(text: "Which event or reminder do you mean?", route: .localContext, intent: .question, extractedItems: [])
        }
        if asksWhen {
            guard let date = effectiveDate(item) else {
                return .init(text: "I don’t have a confirmed time for \(item.content).", route: .localContext, intent: .question, extractedItems: [])
            }
            let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
            return .init(text: "\(item.content) is \(formatter.string(from: date)).", route: .localContext, intent: .question, extractedItems: [])
        }
        if asksWhere {
            guard let location = item.metadata["location"], !location.isEmpty else {
                return .init(text: "I don’t have a confirmed location for \(item.content).", route: .localContext, intent: .question, extractedItems: [])
            }
            return .init(text: "\(item.content) is at \(location).", route: .localContext, intent: .question, extractedItems: [])
        }
        return .init(text: dayDescription(item), route: .localContext, intent: .question, extractedItems: [])
    }

    private func dayDescription(_ item: SuzzmeContextItem) -> String {
        if item.intent == .event { return eventDescription(item) }
        if let date = effectiveDate(item) {
            let formatter = DateFormatter(); formatter.dateStyle = .none; formatter.timeStyle = .short
            return "\(item.content) is due at \(formatter.string(from: date))."
        }
        return "\(item.content)."
    }

    private func effectiveDate(_ item: SuzzmeContextItem) -> Date? {
        let raw = item.metadata["start"] ?? item.metadata["due"] ?? item.metadata["effectiveAt"]
        return raw.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    private func asksAboutAttendance(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("who is attending") || lower.contains("who’s attending") || lower.contains("who is going")
    }
}
