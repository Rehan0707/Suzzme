import Foundation

enum SuzzmeActionRisk: String, Codable, Sendable { case readOnly, reversible, consequential }
enum SuzzmeActionStatus: String, Codable, Sendable { case proposed, awaitingConfirmation, cancelled, completed, failed }
enum SuzzmeActionType: String, Codable, Sendable { case openApp, openFile, createReminder, createCalendarEvent, draftMessage, sendMessage, runShortcut, forgetMemory }

struct SuzzmeAction: Identifiable, Codable, Sendable {
    let id: UUID
    let type: SuzzmeActionType
    let title: String
    let risk: SuzzmeActionRisk
    var status: SuzzmeActionStatus
    let contextIDs: [UUID]
    init(id: UUID = UUID(), type: SuzzmeActionType, title: String, risk: SuzzmeActionRisk, status: SuzzmeActionStatus = .proposed, contextIDs: [UUID] = []) {
        self.id = id; self.type = type; self.title = title; self.risk = risk; self.status = status; self.contextIDs = contextIDs
    }
    var requiresConfirmation: Bool { risk == .consequential }
}

/// Future action executors must ask this policy before execution. No executor is
/// supplied in Step 3, so intelligence can only propose actions.
enum SuzzmeActionSafety {
    static func mayExecute(_ action: SuzzmeAction, userConfirmed: Bool) -> Bool {
        !action.requiresConfirmation || userConfirmed
    }
}

protocol SuzzmeActionExecutor: Sendable {
    func execute(_ action: SuzzmeAction, userConfirmed: Bool) async throws -> SuzzmeAction
}
