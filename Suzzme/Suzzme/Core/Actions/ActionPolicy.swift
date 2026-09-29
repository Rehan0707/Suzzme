import Foundation

/// All proposals, including decoded model data, pass through this local policy.
enum SuzzmeActionPolicy {
    static func validate(_ plan: SuzzmeActionPlan) throws {
        let title = plan.payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 240, plan.requiresConfirmation,
              plan.risk == (plan.operation == .delete ? .destructive : .consequentialWrite) else {
            throw SuzzmeCapabilityError.malformedPlan
        }
        guard PrivacyEngine().classify(title).policy != .neverProcess else { throw SuzzmeCapabilityError.malformedPlan }
        switch (plan.capability, plan.payload) {
        case (.reminders, let .completedReminders(items)):
            guard plan.operation == .delete, items.count <= 20 else { throw SuzzmeCapabilityError.limitExceeded }
            guard Set(items.compactMap(\.targetIdentifier)).count == items.count else { throw SuzzmeCapabilityError.malformedPlan }
            for item in items {
                guard !item.title.isEmpty, item.title.count <= 240, item.expectedFingerprint != nil,
                      item.calendarIdentifier != nil, PrivacyEngine().classify(item.title).policy != .neverProcess else { throw SuzzmeCapabilityError.malformedPlan }
            }
        case (.reminders, let .reminder(value)):
            if let date = value.dueDate, !date.timeIntervalSince1970.isFinite { throw SuzzmeCapabilityError.malformedPlan }
            if plan.operation == .update, value.dueDate == nil { throw SuzzmeCapabilityError.malformedPlan }
        case (.calendar, let .calendar(value)):
            guard plan.operation != .complete else { throw SuzzmeCapabilityError.unsupported }
            if plan.operation == .create || plan.operation == .update {
                guard let start = value.startDate, start.timeIntervalSince1970.isFinite else { throw SuzzmeCapabilityError.malformedPlan }
                if let end = value.endDate, !end.timeIntervalSince1970.isFinite || end <= start { throw SuzzmeCapabilityError.malformedPlan }
            }
        default: throw SuzzmeCapabilityError.malformedPlan
        }
    }
}
