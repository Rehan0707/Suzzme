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

    static var status: SuzzmePermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .authorized
        case .notDetermined: .notDetermined
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
                "source": "calendar", "calendar": calendarName,
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

    static var status: SuzzmePermissionState {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: .authorized
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unavailable
        }
    }

    private func fetchReminders(matching predicate: NSPredicate) async -> [ReminderSnapshot] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let snapshots = (reminders ?? []).map { reminder in
                    ReminderSnapshot(identifier: reminder.calendarItemIdentifier, title: reminder.title ?? "Untitled reminder", createdAt: reminder.creationDate ?? .now, dueDate: reminder.dueDateComponents?.date, isCompleted: reminder.isCompleted, priority: reminder.priority, list: reminder.calendar.title)
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
            metadata: ["source": "reminders", "list": reminder.list, "completed": String(reminder.isCompleted), "priority": String(reminder.priority), "due": reminder.dueDate.map { ISO8601DateFormatter().string(from: $0) } ?? ""],
            expiration: nil, confidence: 1
        )
    }

    private struct ReminderSnapshot: Sendable {
        let identifier: String; let title: String; let createdAt: Date; let dueDate: Date?; let isCompleted: Bool; let priority: Int; let list: String
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
        case .authorized: .authorized; case .notDetermined: .notDetermined
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
