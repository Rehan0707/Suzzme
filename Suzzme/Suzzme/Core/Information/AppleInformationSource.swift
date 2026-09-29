import Foundation

/// Reuses Step 4 actors; no EventKit mutation surface or permission prompting.
struct AppleInformationSource: InformationSource {
    let id: InformationSourceID
    let calendar: CalendarContextSource
    let reminders: RemindersContextSource
    let permissions: AppleContextPermissions

    func authorization() async -> InformationHealthState {
        switch await permissions.status(for: id == .calendar ? .calendar : .reminders) {
        case .authorized: .healthy
        case .notDetermined: .permissionRequired
        case .writeOnly, .denied, .restricted: .permissionDenied
        case .unavailable: .unsupported
        }
    }
    func fetch(now: Date, checkpoint: Date?) async throws -> InformationBatch {
        // EventKit has no public cursor. A bounded rolling snapshot plus durable
        // semantic fingerprints is the checkpoint/recovery strategy.
        let window = DateInterval(start: now.addingTimeInterval(-86400), end: now.addingTimeInterval(14 * 86400))
        let snapshot: (items: [SuzzmeContextItem], complete: Bool)
        if id == .calendar { snapshot = try await calendar.informationSnapshot(window: window, limit: InformationLimits.intake) }
        else { snapshot = try await reminders.informationSnapshot(window: window, limit: InformationLimits.intake) }
        let formatter = ISO8601DateFormatter()
        let observations = snapshot.items.map { item in
            InformationObservation(externalID: item.sourceIdentifier, title: item.metadata["title"] ?? item.content,
                                   privateNotes: item.metadata["notes"] ?? "", location: item.metadata["location"] ?? "", entities: item.entities,
                                   modifiedAt: item.timestamp,
                                   effectiveAt: item.metadata[id == .calendar ? "start" : "due"].flatMap { formatter.date(from: $0) },
                                   effectiveUntil: item.metadata["end"].flatMap { formatter.date(from: $0) },
                                   state: item.metadata["cancelled"] == "true" ? .cancelled : item.metadata["completed"] == "true" ? .completed : .active)
        }
        return .init(observations: observations, complete: snapshot.complete, window: window)
    }
}
