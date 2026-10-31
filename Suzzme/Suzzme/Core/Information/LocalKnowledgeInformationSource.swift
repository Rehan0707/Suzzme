import Foundation

/// Lets the user explicitly include today's newly analyzed Local Knowledge
/// excerpts in the Mac Daily Summary. Original documents are never rescanned.
struct LocalKnowledgeInformationSource: InformationSource {
    let id: InformationSourceID = .localKnowledge
    let engine: LocalKnowledgeEngine

    func authorization() async -> InformationHealthState {
        do { _ = try await engine.notes(); return .healthy }
        catch { return .temporarilyUnavailable }
    }

    func fetch(now: Date, checkpoint: Date?) async throws -> InformationBatch {
        try await batch(cutoff: now, calendar: .current)
    }

    func fetchForBriefing(now: Date, checkpoint: Date?, cutoff: Date, calendar: Calendar) async throws -> InformationBatch {
        try await batch(cutoff: cutoff, calendar: calendar)
    }

    private func batch(cutoff: Date, calendar: Calendar) async throws -> InformationBatch {
        let start = calendar.startOfDay(for: cutoff)
        let notes = try await engine.notes()
        var observations: [InformationObservation] = []
        for note in notes where note.analyzedAt >= start && note.analyzedAt <= cutoff {
            try Task.checkCancellation()
            let excerpt = note.excerpts.first ?? ""
            guard !excerpt.isEmpty,
                  PrivacyEngine().classify(note.title + "\n" + excerpt).policy != .neverProcess else { continue }
            let lead = "Local document · \(note.title): "
            let available = max(0, 240 - lead.count)
            let text = String(excerpt.prefix(available))
            let headline = lead + text + (text.count < excerpt.count ? "…" : "")
            observations.append(.init(
                externalID: "knowledge:\(note.id.uuidString.lowercased())",
                title: headline,
                entities: ["localKnowledge"],
                modifiedAt: note.analyzedAt,
                effectiveAt: note.analyzedAt,
                kindHint: .generalUpdate
            ))
        }
        return .init(observations: observations, complete: false,
                     window: .init(start: start, end: cutoff))
    }

    func permits(_ event: InformationEvent, now: Date) async -> Bool {
        let prefix = "knowledge:"
        guard event.externalID.hasPrefix(prefix),
              let id = UUID(uuidString: String(event.externalID.dropFirst(prefix.count))),
              let notes = try? await engine.notes() else { return false }
        return notes.contains { $0.id == id }
    }
}
