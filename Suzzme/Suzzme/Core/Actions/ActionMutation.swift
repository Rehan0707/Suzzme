import Foundation

/// A value snapshot used only inside the action boundary, never as model instructions.
struct SuzzmeActionRecord: Sendable, Equatable {
    let identifier: String
    let calendarIdentifier: String
    let title: String
    let dueDate: Date?
    let startDate: Date?
    let endDate: Date?
    let completed: Bool
    let fingerprint: String
    let writable: Bool
    let recurring: Bool
    let externalParticipants: Bool
    let allDay: Bool
}

/// Instances live entirely on the coordinator's executor. No EventKit object crosses actors.
protocol SuzzmeActionStore {
    func availability(for capability: SuzzmeCapabilityID) -> SuzzmeCapabilityAvailability
    func record(for capability: SuzzmeCapabilityID, identifier: String) -> SuzzmeActionRecord?
    func write(_ plan: SuzzmeActionPlan) throws -> String
    func completedReminderIDs() -> Set<String>
    func refresh()
}

enum SuzzmeActionMutation {
    static func execute(_ plan: SuzzmeActionPlan, store: any SuzzmeActionStore,
                        authorization: isolated SuzzmeActionExecutionCoordinator) throws -> SuzzmeCapabilityResult {
        try SuzzmeActionPolicy.validate(plan)
        if case let .completedReminders(items) = plan.payload {
            guard !items.isEmpty else { throw SuzzmeCapabilityError.targetMissing }
            let identifiers = Set(items.compactMap(\.targetIdentifier))
            guard store.completedReminderIDs() == identifiers else { throw SuzzmeCapabilityError.targetChanged }
            store.refresh()
            for item in items {
                guard let id = item.targetIdentifier, let current = store.record(for: .reminders, identifier: id) else { throw SuzzmeCapabilityError.targetMissing }
                guard current.completed, current.fingerprint == item.expectedFingerprint,
                      current.calendarIdentifier == item.calendarIdentifier else { throw SuzzmeCapabilityError.targetChanged }
                guard current.writable, !current.recurring else { throw SuzzmeCapabilityError.unsupported }
            }
            guard store.availability(for: .reminders) == .available else { throw SuzzmeCapabilityError.authorizationDenied }
            try authorization.authorizeCommit(plan)
            _ = try store.write(plan)
            store.refresh()
            guard store.availability(for: .reminders) == .available,
                  identifiers.allSatisfy({ store.record(for: .reminders, identifier: $0) == nil }) else { throw SuzzmeCapabilityError.verificationFailed }
            return .init(actionID: plan.id, status: .success, message: "Deleted \(items.count) completed reminders.", evidence: .init(actionID: plan.id, requestID: plan.requestID, capability: .reminders, operation: .delete, targetIdentifier: nil, timestamp: .now, verification: .verified))
        }
        let identifier: String?
        let fingerprint: String?
        let calendarID: String?
        switch plan.payload {
        case .completedReminders: throw SuzzmeCapabilityError.malformedPlan
        case let .reminder(value): identifier = value.targetIdentifier; fingerprint = value.expectedFingerprint; calendarID = value.calendarIdentifier
        case let .calendar(value): identifier = value.targetIdentifier; fingerprint = value.expectedFingerprint; calendarID = value.calendarIdentifier
        }
        guard let calendarID, !calendarID.isEmpty else { throw SuzzmeCapabilityError.malformedPlan }
        store.refresh()
        var original: SuzzmeActionRecord?
        if plan.operation != .create {
            guard let identifier, let current = store.record(for: plan.capability, identifier: identifier) else { throw SuzzmeCapabilityError.targetMissing }
            original = current
            guard let fingerprint, fingerprint == current.fingerprint, calendarID == current.calendarIdentifier else { throw SuzzmeCapabilityError.targetChanged }
            guard current.writable, !current.recurring, !current.externalParticipants, !current.allDay else { throw SuzzmeCapabilityError.unsupported }
        }
        switch store.availability(for: plan.capability) {
        case .available: break
        case .writeOnly: throw SuzzmeCapabilityError.fullAccessRequired
        case .authorizationRequired: throw SuzzmeCapabilityError.authorizationRequired
        case .denied, .restricted: throw SuzzmeCapabilityError.authorizationDenied
        case .unavailable: throw SuzzmeCapabilityError.unsupported
        }
        // There is no suspension between authorization, mutation and readback.
        try authorization.authorizeCommit(plan)
        let writtenID = try store.write(plan)
        guard plan.operation == .create || writtenID == identifier else { throw SuzzmeCapabilityError.verificationFailed }
        store.refresh()
        guard store.availability(for: plan.capability) == .available else { throw SuzzmeCapabilityError.verificationFailed }
        let restored = store.record(for: plan.capability, identifier: writtenID)
        if plan.operation == .delete {
            guard restored == nil, writtenID == identifier else { throw SuzzmeCapabilityError.verificationFailed }
        } else {
            guard let restored, restored.identifier == writtenID, restored.calendarIdentifier == calendarID,
                  restored.title == plan.payload.title else { throw SuzzmeCapabilityError.verificationFailed }
            switch plan.payload {
            case .completedReminders: throw SuzzmeCapabilityError.malformedPlan
            case let .reminder(value):
                if plan.operation == .complete {
                    guard restored.completed, restored.dueDate == original?.dueDate else { throw SuzzmeCapabilityError.verificationFailed }
                } else {
                    guard restored.dueDate == value.dueDate, restored.completed == (original?.completed ?? false) else { throw SuzzmeCapabilityError.verificationFailed }
                }
            case let .calendar(value):
                guard restored.startDate == value.startDate, restored.endDate == value.endDate, !restored.allDay else { throw SuzzmeCapabilityError.verificationFailed }
            }
        }
        return .init(actionID: plan.id, status: .success, message: "Done.", evidence: .init(actionID: plan.id, requestID: plan.requestID, capability: plan.capability, operation: plan.operation, targetIdentifier: writtenID, timestamp: .now, verification: .verified))
    }
}
