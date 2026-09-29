import Foundation
import EventKit
import Contacts

actor CalendarContextSource: ContextSource {
    let identifier = "calendar"
    private let store = EKEventStore()

    func fetchContext(for request: SuzzmeContextRequest) async throws -> [SuzzmeContextItem] {
        guard Self.status == .authorized else { throw SuzzmeContextError.sourceUnavailable(identifier) }
        try Task.checkCancellation()
        let range = request.query.dateRange ?? DateInterval(start: request.referenceDate, duration: 7 * 24 * 60 * 60)
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(request.limit)
        return events.map(Self.item)
    }

    /// Action resolution is bounded, exact-title matching against the live store.
    /// Returned content is data; callers may not interpret it as instructions.
    func actionTargets(named title: String, on day: Date? = nil, now: Date = .now) throws -> [SuzzmeContextItem] {
        guard Self.status == .authorized else { throw SuzzmeContextError.sourceUnavailable(identifier) }
        store.reset()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-86400), end: now.addingTimeInterval(90 * 86400), calendars: nil)
        return store.events(matching: predicate).filter {
            SuzzmeActionTargetMatcher.matches($0.title ?? "", query: title) && $0.status != .canceled && (day == nil || Calendar.current.isDate($0.startDate, inSameDayAs: day ?? now))
        }.prefix(21).map(Self.item)
    }

    /// Step 9 uses a complete bounded snapshot, without changing live-query semantics.
    func informationSnapshot(window: DateInterval, limit: Int) throws -> (items: [SuzzmeContextItem], complete: Bool) {
        guard Self.status == .authorized else { throw SuzzmeContextError.sourceUnavailable(identifier) }
        try Task.checkCancellation()
        store.reset()
        let events = store.events(matching: store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
        let bounded = events.prefix(max(0, min(limit, 100)))
        let items = bounded.compactMap { event -> SuzzmeContextItem? in
            guard let identifier = event.eventIdentifier else { return nil }
            let occurrence = event.occurrenceDate.map { "@" + String($0.timeIntervalSince1970) } ?? ""
            return .init(sourceIdentifier: identifier + occurrence, content: event.title ?? "", timestamp: event.lastModifiedDate ?? event.creationDate ?? window.start,
                         entities: [], metadata: ["title": event.title ?? "", "notes": event.notes ?? "", "location": event.location ?? "",
                         "start": ISO8601DateFormatter().string(from: event.startDate), "end": ISO8601DateFormatter().string(from: event.endDate),
                         "cancelled": String(event.status == .canceled)])
        }
        return (items, events.count <= limit && items.count == bounded.count)
    }

    static var status: SuzzmePermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .authorized
        case .notDetermined: .notDetermined
        case .writeOnly: .denied
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unavailable
        }
    }

    private static func item(_ event: EKEvent) -> SuzzmeContextItem {
        let names = event.attendees?.compactMap(\.name) ?? []
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendarName = event.calendar.title
        var content = event.title ?? "Untitled event"
        if let location, !location.isEmpty { content += " at \(location)" }
        return SuzzmeContextItem(
            sourceIdentifier: event.eventIdentifier ?? UUID().uuidString,
            content: content,
            timestamp: event.creationDate ?? event.startDate,
            entities: names,
            intent: .event,
            importance: event.availability == .busy ? .important : .normal,
            sensitivity: .personal,
            metadata: [
                "source": "calendar", "calendar": calendarName, "title": event.title ?? "",
                "calendarID": event.calendar.calendarIdentifier, "fingerprint": SuzzmeEventKitFingerprint.event(event),
                "recurring": String(event.hasRecurrenceRules), "attendees": String(event.hasAttendees),
                "start": ISO8601DateFormatter().string(from: event.startDate),
                "end": ISO8601DateFormatter().string(from: event.endDate),
                "allDay": String(event.isAllDay),
                "location": location ?? ""
            ],
            expiration: event.endDate,
            confidence: 1
        )
    }
}

actor RemindersContextSource: ContextSource {
    let identifier = "reminders"
    private let store = EKEventStore()

    func fetchContext(for request: SuzzmeContextRequest) async throws -> [SuzzmeContextItem] {
        guard Self.status == .authorized else { throw SuzzmeContextError.sourceUnavailable(identifier) }
        try Task.checkCancellation()
        let range = request.query.dateRange ?? DateInterval(start: request.referenceDate, duration: 7 * 24 * 60 * 60)
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: range.start, ending: range.end, calendars: nil)
        let reminders = await fetchReminders(matching: predicate)
            .filter { !$0.isCompleted }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(request.limit)
        return reminders.map(Self.item)
    }

    func completedActionTargets() async throws -> [SuzzmeContextItem] {
        guard Self.status == .authorized else { throw SuzzmeContextError.sourceUnavailable(identifier) }
        store.reset()
        let values = await fetchReminders(matching: store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: nil))
        try Task.checkCancellation()
        return values.filter(\.isCompleted).prefix(21).map(Self.item)
    }

    func actionTargets(named title: String) async throws -> [SuzzmeContextItem] {
        guard Self.status == .authorized else { throw SuzzmeContextError.sourceUnavailable(identifier) }
        store.reset()
        let values = await fetchReminders(matching: store.predicateForReminders(in: nil))
        try Task.checkCancellation()
        return values.filter { SuzzmeActionTargetMatcher.matches($0.title, query: title) }.prefix(21).map(Self.item)
    }

    func informationSnapshot(window: DateInterval, limit: Int) async throws -> (items: [SuzzmeContextItem], complete: Bool) {
        guard Self.status == .authorized else { throw SuzzmeContextError.sourceUnavailable(identifier) }
        try Task.checkCancellation()
        store.reset()
        var items: [SuzzmeContextItem] = []
        var complete = true
        // Public EventKit predicates bound the date range. EventKit has no fetch
        // limit; at most limit + 1 value snapshots leave each callback.
        for completed in [false, true] {
            let predicate = completed
                ? store.predicateForCompletedReminders(withCompletionDateStarting: window.start, ending: window.end, calendars: nil)
                : store.predicateForIncompleteReminders(withDueDateStarting: window.start, ending: window.end, calendars: nil)
            let result: (items: [SuzzmeContextItem], complete: Bool) = try await withCheckedThrowingContinuation { continuation in
                store.fetchReminders(matching: predicate) { values in
                    guard let values else { continuation.resume(throwing: SuzzmeContextError.sourceUnavailable("reminders")); return }
                    let snapshots = values.prefix(max(0, min(limit, 100)) + 1).map { reminder in
                        SuzzmeContextItem(sourceIdentifier: reminder.calendarItemIdentifier, content: reminder.title ?? "",
                                          timestamp: reminder.lastModifiedDate ?? reminder.creationDate ?? window.start,
                                          metadata: ["title": reminder.title ?? "", "notes": reminder.notes ?? "", "completed": String(reminder.isCompleted),
                                          "due": reminder.dueDateComponents?.date.map { ISO8601DateFormatter().string(from: $0) } ?? ""])
                    }
                    continuation.resume(returning: (snapshots, values.count <= limit))
                }
            }
            try Task.checkCancellation()
            items.append(contentsOf: result.items)
            complete = complete && result.complete
        }
        return (Array(items.prefix(max(0, min(limit, 100)))), complete && items.count <= limit)
    }

    static var status: SuzzmePermissionState {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: .authorized
        case .notDetermined: .notDetermined
        case .writeOnly: .denied
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unavailable
        }
    }

    private func fetchReminders(matching predicate: NSPredicate) async -> [ReminderSnapshot] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let snapshots = (reminders ?? []).map { reminder in
                    ReminderSnapshot(identifier: reminder.calendarItemIdentifier, title: reminder.title ?? "Untitled reminder", createdAt: reminder.creationDate ?? .now, dueDate: reminder.dueDateComponents?.date, isCompleted: reminder.isCompleted, priority: reminder.priority, list: reminder.calendar.title, calendarID: reminder.calendar.calendarIdentifier, fingerprint: SuzzmeEventKitFingerprint.reminder(reminder), recurring: reminder.hasRecurrenceRules)
                }
                continuation.resume(returning: snapshots)
            }
        }
    }

    private static func item(_ reminder: ReminderSnapshot) -> SuzzmeContextItem {
        let priority: SuzzmeItem.Priority = reminder.priority >= 5 ? .important : reminder.priority > 0 ? .normal : .low
        return SuzzmeContextItem(
            sourceIdentifier: reminder.identifier, content: reminder.title, timestamp: reminder.createdAt,
            entities: [], intent: .reminder, importance: priority, sensitivity: .personal,
            metadata: ["calendarID": reminder.calendarID, "fingerprint": reminder.fingerprint, "recurring": String(reminder.recurring), "source": "reminders", "list": reminder.list, "completed": String(reminder.isCompleted), "priority": String(reminder.priority), "due": reminder.dueDate.map { ISO8601DateFormatter().string(from: $0) } ?? ""],
            expiration: nil, confidence: 1
        )
    }

    private struct ReminderSnapshot: Sendable {
        let identifier: String; let title: String; let createdAt: Date; let dueDate: Date?; let isCompleted: Bool; let priority: Int; let list: String; let calendarID: String; let fingerprint: String; let recurring: Bool
    }
}

actor ContactsContextSource: ContextSource {
    let identifier = "contacts"
    private let store = CNContactStore()

    func fetchContext(for request: SuzzmeContextRequest) async throws -> [SuzzmeContextItem] {
        guard Self.status == .authorized else { throw SuzzmeContextError.sourceUnavailable(identifier) }
        let terms = request.query.entities.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { $0.count >= 3 }
        guard !terms.isEmpty else { return [] }
        let keys: [CNKeyDescriptor] = [CNContactIdentifierKey as CNKeyDescriptor, CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor, CNContactNicknameKey as CNKeyDescriptor, CNContactOrganizationNameKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor]
        let contacts = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: terms.joined(separator: " ")), keysToFetch: keys)
        return contacts.filter { Self.matches($0, terms: terms) }.prefix(request.limit).map { Self.item($0, detail: request.query.contactDetail) }
    }

    static var status: SuzzmePermissionState {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited: .authorized; case .notDetermined: .notDetermined
        case .denied: .denied; case .restricted: .restricted
        @unknown default: .unavailable
        }
    }

    private static func matches(_ contact: CNContact, terms: [String]) -> Bool {
        let values = [contact.givenName, contact.familyName, contact.nickname, contact.organizationName].map { $0.lowercased() }
        return terms.allSatisfy { term in values.contains { $0 == term } || values.contains { $0.split(separator: " ").contains(Substring(term)) } }
    }

    private static func item(_ contact: CNContact, detail: SuzzmeContactDetail) -> SuzzmeContextItem {
        let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        let title = name.isEmpty ? contact.organizationName : name
        let email = detail == .email ? (contact.emailAddresses.first?.value as String? ?? "") : ""
        let phone = detail == .phone ? (contact.phoneNumbers.first?.value.stringValue ?? "") : ""
        return SuzzmeContextItem(
            sourceIdentifier: contact.identifier, content: title, timestamp: .now, entities: [title], intent: .information,
            importance: .normal, sensitivity: .sensitive,
            metadata: ["source": "contacts", "email": email, "phone": phone, "organization": contact.organizationName],
            expiration: Date.now.addingTimeInterval(30 * 60), confidence: 1
        )
    }
}

/// Version evidence includes all fields whose changes would invalidate approval.
enum SuzzmeEventKitFingerprint {
    static func reminder(_ value: EKReminder) -> String {
        "\(value.calendarItemIdentifier)|\(value.calendar.calendarIdentifier)|\(value.title ?? "")|\(String(describing: value.dueDateComponents))|\(value.isCompleted)|\(value.hasRecurrenceRules)|\(String(describing: value.lastModifiedDate))"
    }
    static func event(_ value: EKEvent) -> String {
        "\(value.eventIdentifier ?? "")|\(value.calendar.calendarIdentifier)|\(value.title ?? "")|\(String(describing: value.startDate))|\(String(describing: value.endDate))|\(value.isAllDay)|\(value.hasRecurrenceRules)|\(value.hasAttendees)|\(String(describing: value.lastModifiedDate))"
    }
}

/// Deterministic lexical matching; multiple matches always require clarification.
enum SuzzmeActionTargetMatcher {
    static func matches(_ title: String, query: String) -> Bool {
        let tokens = Set(title.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let queryTokens = Set(query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return !queryTokens.isEmpty && queryTokens.isSubset(of: tokens)
    }
}
