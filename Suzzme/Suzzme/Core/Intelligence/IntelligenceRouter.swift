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

    func route(text: String, context: [SuzzmeContextItem], existingFingerprints: Set<String>) async throws -> SuzzmeRoutedResponse {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw SuzzmeIntelligenceError.emptyInput }
        if asksForTodayFocus(query), !context.isEmpty {
            let relevant = context.prefix(3).map(\.content).joined(separator: " ")
            return .init(text: "Here’s what matters: \(relevant)", route: .localContext, intent: .question, extractedItems: [])
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

    private func asksAboutAttendance(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("who is attending") || lower.contains("who’s attending") || lower.contains("who is going")
    }
}
