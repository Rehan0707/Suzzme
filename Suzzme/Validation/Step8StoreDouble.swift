import Foundation
import Synchronization

/// Exercises the production mutation driver with isolated, deterministic storage.
final class ActionStoreDouble: SuzzmeActionStore, Sendable {
    enum Fault: Sendable { case none, noWrite, wrongDate, wrongTitle, deniedAfterWrite }
    struct State: Sendable {
        var records: [String: SuzzmeActionRecord] = [:]
        var writes = 0
        var permission: SuzzmeCapabilityAvailability = .available
        var fault: Fault = .none
    }
    let state = Mutex(State())
    func availability(for capability: SuzzmeCapabilityID) -> SuzzmeCapabilityAvailability { state.withLock { $0.permission } }
    func record(for capability: SuzzmeCapabilityID, identifier: String) -> SuzzmeActionRecord? { state.withLock { $0.records[identifier] } }
    func completedReminderIDs() -> Set<String> { state.withLock { Set($0.records.values.filter(\.completed).map(\.identifier)) } }
    func refresh() { }
    func write(_ plan: SuzzmeActionPlan) throws -> String {
        state.withLock { state in
            state.writes += 1
            var identifier: String?
            var calendarID: String?
            var due: Date?
            var start: Date?
            var end: Date?
            switch plan.payload {
            case let .completedReminders(items):
                if state.fault != .noWrite { for item in items { if let id = item.targetIdentifier { state.records.removeValue(forKey: id) } } }
                return plan.id.uuidString
            case let .reminder(value): identifier = value.targetIdentifier; calendarID = value.calendarIdentifier; due = value.dueDate
            case let .calendar(value): identifier = value.targetIdentifier; calendarID = value.calendarIdentifier; start = value.startDate; end = value.endDate
            }
            let key = identifier ?? plan.id.uuidString
            if state.fault == .noWrite { return key }
            if plan.operation == .delete { state.records.removeValue(forKey: key); return key }
            if state.fault == .deniedAfterWrite { state.permission = .denied }
            state.records[key] = .init(identifier: key, calendarIdentifier: calendarID ?? "", title: state.fault == .wrongTitle ? "Wrong title" : plan.payload.title, dueDate: state.fault == .wrongDate ? .distantFuture : due, startDate: state.fault == .wrongDate ? .distantFuture : start, endDate: end, completed: plan.operation == .complete, fingerprint: "version-2", writable: true, recurring: false, externalParticipants: false, allDay: false)
            return key
        }
    }
}

struct StoreBackedCapability: SuzzmeCapability {
    let id: SuzzmeCapabilityID
    let store: ActionStoreDouble
    func availability() -> SuzzmeCapabilityAvailability { store.availability(for: id) }
    func resolve(_ plan: SuzzmeActionPlan) -> SuzzmeActionPlan { plan }
    func execute(_ plan: SuzzmeActionPlan, authorization: isolated SuzzmeActionExecutionCoordinator) async throws -> SuzzmeCapabilityResult {
        try SuzzmeActionMutation.execute(plan, store: store, authorization: authorization)
    }
}
