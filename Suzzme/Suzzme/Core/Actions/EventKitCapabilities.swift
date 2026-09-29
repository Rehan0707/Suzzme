import EventKit
import Foundation

protocol SuzzmeCapability: Sendable {
    var id: SuzzmeCapabilityID { get }
    func availability() async -> SuzzmeCapabilityAvailability
    func resolve(_ plan: SuzzmeActionPlan) async throws -> SuzzmeActionPlan
    func execute(_ plan: SuzzmeActionPlan, authorization: isolated SuzzmeActionExecutionCoordinator) async throws -> SuzzmeCapabilityResult
}

struct SuzzmeCapabilityRegistry: Sendable {
    private let capabilities: [SuzzmeCapabilityID: any SuzzmeCapability]

    init(capabilities: [any SuzzmeCapability]) {
        self.capabilities = Dictionary(capabilities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func availability(for id: SuzzmeCapabilityID) async -> SuzzmeCapabilityAvailability {
        guard let capability = capabilities[id] else { return .unavailable }
        return await capability.availability()
    }

    func resolve(_ plan: SuzzmeActionPlan) async throws -> SuzzmeActionPlan {
        guard let capability = capabilities[plan.capability] else { throw SuzzmeCapabilityError.unsupported }
        return try await capability.resolve(plan)
    }

    func execute(_ plan: SuzzmeActionPlan, authorization: isolated SuzzmeActionExecutionCoordinator) async throws -> SuzzmeCapabilityResult {
        guard let capability = capabilities[plan.capability] else { throw SuzzmeCapabilityError.unsupported }
        return try await capability.execute(plan, authorization: authorization)
    }
}

struct EventKitReminderCapability: SuzzmeCapability {
    nonisolated let id: SuzzmeCapabilityID = .reminders

    func availability() -> SuzzmeCapabilityAvailability { Self.availability(for: .reminder) }

    func resolve(_ plan: SuzzmeActionPlan) async throws -> SuzzmeActionPlan {
        if case .completedReminders = plan.payload {
            let values = try await RemindersContextSource().completedActionTargets()
            guard !values.isEmpty else { throw SuzzmeCapabilityError.targetMissing }
            guard values.count <= 20 else { throw SuzzmeCapabilityError.limitExceeded }
            guard values.allSatisfy({ $0.metadata["recurring"] == "false" }) else { throw SuzzmeCapabilityError.unsupported }
            let items = values.map { SuzzmeReminderAction(title: $0.content, targetIdentifier: $0.sourceIdentifier, calendarIdentifier: $0.metadata["calendarID"], expectedFingerprint: $0.metadata["fingerprint"]) }
            return plan.replacingPayload(.completedReminders(items.sorted { ($0.targetIdentifier ?? "") < ($1.targetIdentifier ?? "") }))
        }
        guard case var .reminder(action) = plan.payload else { throw SuzzmeCapabilityError.malformedPlan }
        guard availability() == .available else { throw Self.authorizationError(for: .reminder) }
        if plan.operation == .create {
            action.calendarIdentifier = try reminderCalendar(id: action.calendarIdentifier, store: EKEventStore()).calendarIdentifier
        } else {
            let matches = try await RemindersContextSource().actionTargets(named: action.title)
            guard !matches.isEmpty else { throw SuzzmeCapabilityError.targetMissing }
            guard matches.count == 1, let target = matches.first else { throw SuzzmeCapabilityError.ambiguousTargets(matches.map { $0.content + ($0.metadata["start"].map { " at " + $0 } ?? "") }) }
            guard target.metadata["recurring"] == "false" else { throw SuzzmeCapabilityError.unsupported }
            action.title = target.content
            action.targetIdentifier = target.sourceIdentifier
            action.calendarIdentifier = target.metadata["calendarID"]
            action.expectedFingerprint = target.metadata["fingerprint"]
        }
        return plan.replacingPayload(.reminder(action))
    }

    func execute(_ plan: SuzzmeActionPlan, authorization: isolated SuzzmeActionExecutionCoordinator) async throws -> SuzzmeCapabilityResult {
        var completedIDs: Set<String>?
        if case .completedReminders = plan.payload {
            completedIDs = Set(try await RemindersContextSource().completedActionTargets().map(\.sourceIdentifier))
        }
        return try SuzzmeActionMutation.execute(plan, store: EventKitActionStore(completedIDs: completedIDs), authorization: authorization)
    }

    private func reminderCalendar(id: String?, store: EKEventStore) throws -> EKCalendar {
        if let id {
            guard let calendar = store.calendar(withIdentifier: id), calendar.allowsContentModifications else { throw SuzzmeCapabilityError.targetMissing }
            return calendar
        }
        guard let calendar = store.defaultCalendarForNewReminders() else { throw SuzzmeCapabilityError.unsupported }
        return calendar
    }


}

struct EventKitCalendarCapability: SuzzmeCapability {
    nonisolated let id: SuzzmeCapabilityID = .calendar

    func availability() -> SuzzmeCapabilityAvailability { Self.availability(for: .event) }

    func resolve(_ plan: SuzzmeActionPlan) async throws -> SuzzmeActionPlan {
        guard case var .calendar(action) = plan.payload else { throw SuzzmeCapabilityError.malformedPlan }
        guard availability() == .available else { throw Self.authorizationError(for: .event) }
        if plan.operation == .create {
            action.calendarIdentifier = try eventCalendar(id: action.calendarIdentifier, store: EKEventStore()).calendarIdentifier
        } else {
            let matches = try await CalendarContextSource().actionTargets(named: action.title, on: action.targetDay)
            guard !matches.isEmpty else { throw SuzzmeCapabilityError.targetMissing }
            guard matches.count == 1, let target = matches.first else { throw SuzzmeCapabilityError.ambiguousTargets(matches.map { $0.content + ($0.metadata["start"].map { " at " + $0 } ?? "") }) }
            guard target.metadata["recurring"] == "false", target.metadata["attendees"] == "false", target.metadata["allDay"] == "false" else { throw SuzzmeCapabilityError.unsupported }
            action.title = target.metadata["title"] ?? target.content
            action.targetIdentifier = target.sourceIdentifier
            action.calendarIdentifier = target.metadata["calendarID"]
            action.expectedFingerprint = target.metadata["fingerprint"]
            if plan.operation == .update, let start = action.startDate,
               let oldStart = target.metadata["start"].flatMap({ ISO8601DateFormatter().date(from: $0) }),
               let oldEnd = target.metadata["end"].flatMap({ ISO8601DateFormatter().date(from: $0) }) {
                action.endDate = start.addingTimeInterval(oldEnd.timeIntervalSince(oldStart))
            }
            if plan.operation == .delete {
                action.startDate = target.metadata["start"].flatMap { ISO8601DateFormatter().date(from: $0) }
                action.endDate = target.metadata["end"].flatMap { ISO8601DateFormatter().date(from: $0) }
            }
        }
        return plan.replacingPayload(.calendar(action))
    }

    func execute(_ plan: SuzzmeActionPlan, authorization: isolated SuzzmeActionExecutionCoordinator) async throws -> SuzzmeCapabilityResult {
        try SuzzmeActionMutation.execute(plan, store: EventKitActionStore(), authorization: authorization)
    }

    private func eventCalendar(id: String?, store: EKEventStore) throws -> EKCalendar {
        if let id {
            guard let calendar = store.calendar(withIdentifier: id), calendar.allowsContentModifications else { throw SuzzmeCapabilityError.targetMissing }
            return calendar
        }
        guard let calendar = store.defaultCalendarForNewEvents else { throw SuzzmeCapabilityError.unsupported }
        return calendar
    }
}

private extension EventKitReminderCapability {
    nonisolated static func availability(for entity: EKEntityType) -> SuzzmeCapabilityAvailability {
        switch EKEventStore.authorizationStatus(for: entity) { case .fullAccess: .available; case .notDetermined: .authorizationRequired; case .writeOnly: .writeOnly; case .denied: .denied; case .restricted: .restricted; @unknown default: .unavailable }
    }
    nonisolated static func authorizationError(for entity: EKEntityType) -> SuzzmeCapabilityError { availability(for: entity) == .authorizationRequired ? .authorizationRequired : availability(for: entity) == .writeOnly ? .fullAccessRequired : .authorizationDenied }
}

private extension EventKitCalendarCapability {
    nonisolated static func availability(for entity: EKEntityType) -> SuzzmeCapabilityAvailability {
        switch EKEventStore.authorizationStatus(for: entity) { case .fullAccess: .available; case .notDetermined: .authorizationRequired; case .writeOnly: .writeOnly; case .denied: .denied; case .restricted: .restricted; @unknown default: .unavailable }
    }
    nonisolated static func authorizationError(for entity: EKEntityType) -> SuzzmeCapabilityError { availability(for: entity) == .authorizationRequired ? .authorizationRequired : availability(for: entity) == .writeOnly ? .fullAccessRequired : .authorizationDenied }
}

/// Public EventKit adapter. The shared mutation lifecycle owns policy and verification.
private final class EventKitActionStore: SuzzmeActionStore {
    private let store = EKEventStore()
    private let completedIDs: Set<String>?
    init(completedIDs: Set<String>? = nil) { self.completedIDs = completedIDs }
    func completedReminderIDs() -> Set<String> { completedIDs ?? [] }
    func availability(for capability: SuzzmeCapabilityID) -> SuzzmeCapabilityAvailability {
        switch EKEventStore.authorizationStatus(for: capability == .calendar ? .event : .reminder) {
        case .fullAccess: .available
        case .notDetermined: .authorizationRequired
        case .restricted: .restricted
        case .writeOnly: .writeOnly
        case .denied: .denied
        @unknown default: .unavailable
        }
    }
    func refresh() { store.reset() }
    func record(for capability: SuzzmeCapabilityID, identifier: String) -> SuzzmeActionRecord? {
        if capability == .reminders {
            guard let value = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return nil }
            return .init(identifier: identifier, calendarIdentifier: value.calendar.calendarIdentifier, title: value.title ?? "", dueDate: value.dueDateComponents?.date, startDate: nil, endDate: nil, completed: value.isCompleted, fingerprint: SuzzmeEventKitFingerprint.reminder(value), writable: value.calendar.allowsContentModifications, recurring: value.hasRecurrenceRules, externalParticipants: false, allDay: false)
        }
        guard let value = store.event(withIdentifier: identifier) else { return nil }
        return .init(identifier: identifier, calendarIdentifier: value.calendar.calendarIdentifier, title: value.title ?? "", dueDate: nil, startDate: value.startDate, endDate: value.endDate, completed: false, fingerprint: SuzzmeEventKitFingerprint.event(value), writable: value.calendar.allowsContentModifications, recurring: value.hasRecurrenceRules, externalParticipants: value.hasAttendees, allDay: value.isAllDay)
    }
    func write(_ plan: SuzzmeActionPlan) throws -> String {
        switch plan.payload {
        case let .completedReminders(items):
            // Stage bounded removals, then commit once. A failed commit is never retried.
            do {
                for item in items {
                    guard let identifier = item.targetIdentifier, let value = store.calendarItem(withIdentifier: identifier) as? EKReminder else { throw SuzzmeCapabilityError.targetMissing }
                    guard value.isCompleted, item.expectedFingerprint == SuzzmeEventKitFingerprint.reminder(value), value.calendar.allowsContentModifications else { throw SuzzmeCapabilityError.targetChanged }
                    try store.remove(value, commit: false)
                }
                try store.commit()
                return plan.id.uuidString
            } catch { store.reset(); throw error }
        case let .reminder(action):
            let value: EKReminder
            if plan.operation == .create { value = EKReminder(eventStore: store) }
            else {
                guard let identifier = action.targetIdentifier, let found = store.calendarItem(withIdentifier: identifier) as? EKReminder else { throw SuzzmeCapabilityError.targetMissing }
                guard action.expectedFingerprint == SuzzmeEventKitFingerprint.reminder(found) else { throw SuzzmeCapabilityError.targetChanged }
                value = found
            }
            guard let calendarID = action.calendarIdentifier, let calendar = store.calendar(withIdentifier: calendarID), calendar.allowsContentModifications else { throw SuzzmeCapabilityError.targetMissing }
            let identifier = value.calendarItemIdentifier
            if plan.operation == .delete { try store.remove(value, commit: true); return identifier }
            if plan.operation == .complete { value.isCompleted = true }
            else {
                value.title = action.title; value.calendar = calendar
                value.dueDateComponents = action.dueDate.map { Calendar.current.dateComponents(in: .current, from: $0) }
            }
            try store.save(value, commit: true)
            return value.calendarItemIdentifier
        case let .calendar(action):
            let value: EKEvent
            if plan.operation == .create { value = EKEvent(eventStore: store) }
            else {
                guard let identifier = action.targetIdentifier, let found = store.event(withIdentifier: identifier) else { throw SuzzmeCapabilityError.targetMissing }
                guard action.expectedFingerprint == SuzzmeEventKitFingerprint.event(found) else { throw SuzzmeCapabilityError.targetChanged }
                value = found
            }
            guard let calendarID = action.calendarIdentifier, let calendar = store.calendar(withIdentifier: calendarID), calendar.allowsContentModifications else { throw SuzzmeCapabilityError.targetMissing }
            if plan.operation == .delete {
                guard let identifier = value.eventIdentifier else { throw SuzzmeCapabilityError.targetMissing }
                try store.remove(value, span: .thisEvent, commit: true); return identifier
            }
            guard let start = action.startDate, let end = action.endDate, end > start else { throw SuzzmeCapabilityError.malformedPlan }
            value.title = action.title; value.calendar = calendar; value.startDate = start; value.endDate = end
            try store.save(value, span: .thisEvent, commit: true)
            guard let identifier = value.eventIdentifier else { throw SuzzmeCapabilityError.verificationFailed }
            return identifier
        }
    }
}
