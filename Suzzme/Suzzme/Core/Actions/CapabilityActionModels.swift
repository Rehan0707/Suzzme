import Foundation

/// The only system domains Step 8 may mutate. Future domains must be added
/// deliberately rather than being invented from model output.
enum SuzzmeCapabilityID: String, Codable, CaseIterable, Sendable {
    case reminders
    case calendar
}

enum SuzzmeCapabilityOperation: String, Codable, Sendable {
    case create
    case update
    case complete
    case delete
}

enum SuzzmeCapabilityRisk: String, Codable, Sendable {
    case readOnly
    case lowImpactWrite
    case consequentialWrite
    case destructive
    case externalCommunication
    case privileged
}

enum SuzzmeCapabilityAvailability: String, Codable, Sendable {
    case available
    case authorizationRequired
    case writeOnly
    case denied
    case restricted
    case unavailable
}

enum SuzzmeActionVerification: String, Codable, Sendable {
    case verified
    case uncertain
    case notPerformed
}

enum SuzzmeActionResultStatus: String, Codable, Sendable {
    case success
    case failed
    case cancelled
    case permissionDenied
    case unavailable
    case ambiguous
    case verificationFailed
    case stale
    case duplicate
}

struct SuzzmeReminderAction: Codable, Sendable, Equatable {
    var title: String
    var dueDate: Date?
    var targetIdentifier: String?
    var calendarIdentifier: String?
    var expectedFingerprint: String?

    init(title: String, dueDate: Date? = nil, targetIdentifier: String? = nil, calendarIdentifier: String? = nil, expectedFingerprint: String? = nil) {
        self.title = title
        self.dueDate = dueDate
        self.targetIdentifier = targetIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.expectedFingerprint = expectedFingerprint
    }
}

struct SuzzmeCalendarAction: Codable, Sendable, Equatable {
    var title: String
    var startDate: Date?
    var endDate: Date?
    var targetDay: Date?
    var targetIdentifier: String?
    var calendarIdentifier: String?
    var expectedFingerprint: String?

    init(title: String, startDate: Date? = nil, endDate: Date? = nil, targetDay: Date? = nil, targetIdentifier: String? = nil, calendarIdentifier: String? = nil, expectedFingerprint: String? = nil) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.targetDay = targetDay
        self.targetIdentifier = targetIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.expectedFingerprint = expectedFingerprint
    }
}

enum SuzzmeActionPayload: Codable, Sendable, Equatable {
    case reminder(SuzzmeReminderAction)
    case completedReminders([SuzzmeReminderAction])
    case calendar(SuzzmeCalendarAction)

    var title: String {
        switch self {
        case let .completedReminders(items): "\(items.count) completed reminders"
        case let .reminder(action): action.title
        case let .calendar(action): action.title
        }
    }
}

/// Structured, deterministic input to a capability. This is never raw model
/// prose and cannot name an unregistered capability.
struct SuzzmeActionPlan: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let requestID: UUID
    let capability: SuzzmeCapabilityID
    let operation: SuzzmeCapabilityOperation
    let payload: SuzzmeActionPayload
    let risk: SuzzmeCapabilityRisk
    let requiresConfirmation: Bool
    let createdAt: Date

    init(id: UUID = UUID(), requestID: UUID, capability: SuzzmeCapabilityID, operation: SuzzmeCapabilityOperation, payload: SuzzmeActionPayload, risk: SuzzmeCapabilityRisk, requiresConfirmation: Bool = true, createdAt: Date = .now) {
        self.id = id
        self.requestID = requestID
        self.capability = capability
        self.operation = operation
        self.payload = payload
        self.risk = risk
        self.requiresConfirmation = requiresConfirmation
        self.createdAt = createdAt
    }

    func replacingPayload(_ payload: SuzzmeActionPayload) -> Self {
        .init(id: id, requestID: requestID, capability: capability, operation: operation, payload: payload, risk: risk, requiresConfirmation: requiresConfirmation, createdAt: createdAt)
    }

    var confirmationText: String {
        if case let .completedReminders(items) = payload {
            return "Delete \(items.count) completed reminders: " + items.map(\.title).joined(separator: "; ") + "?"
        }
        let verb: String = switch operation {
        case .create: "Create"
        case .update: "Update"
        case .complete: "Mark complete"
        case .delete: "Delete"
        }
        let dateText: String
        switch payload {
        case .completedReminders: dateText = ""
        case let .reminder(reminder):
            dateText = reminder.dueDate.map { " for \($0.formatted(date: .abbreviated, time: .shortened))" } ?? ""
        case let .calendar(event):
            dateText = (event.startDate.map { " from \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "") + (event.endDate.map { " until \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")
        }
        return "\(verb) ‘\(payload.title)’\(dateText)?"
    }
}

struct SuzzmeActionEvidence: Codable, Sendable, Equatable {
    let actionID: UUID
    let requestID: UUID
    let capability: SuzzmeCapabilityID
    let operation: SuzzmeCapabilityOperation
    let targetIdentifier: String?
    let timestamp: Date
    let verification: SuzzmeActionVerification
}

struct SuzzmeCapabilityResult: Sendable, Equatable {
    let actionID: UUID
    let status: SuzzmeActionResultStatus
    let message: String
    let evidence: SuzzmeActionEvidence?
}

enum SuzzmeCapabilityError: LocalizedError, Sendable {
    case malformedPlan
    case unsupported
    case authorizationRequired
    case authorizationDenied
    case fullAccessRequired
    case staleRequest
    case targetMissing
    case targetChanged
    case ambiguousTarget
    case ambiguousTargets([String])
    case verificationFailed
    case limitExceeded

    var errorDescription: String? {
        switch self {
        case .malformedPlan: "Please clarify the item and date or time, including AM or PM. I haven’t made a change."
        case .unsupported: "Suzzme can’t perform that action yet."
        case .authorizationRequired: "Calendar or Reminders access is needed before Suzzme can make that change."
        case .fullAccessRequired: "Full Calendar access is needed to verify changes. Upgrade access in Intelligence Sources."
        case .authorizationDenied: "Calendar or Reminders access is off. You can enable it in Intelligence Sources."
        case .staleRequest: "That action is no longer active."
        case .targetMissing: "That item is no longer available."
        case .targetChanged: "That item changed before the action was confirmed."
        case let .ambiguousTargets(names): "Which item do you mean? " + names.joined(separator: "; ")
        case .ambiguousTarget: "Suzzme needs you to choose the exact item first."
        case .verificationFailed: "I couldn’t verify that change. Please check Calendar or Reminders before trying again."
        case .limitExceeded: "That action is too broad. Please narrow it down."
        }
    }
}
