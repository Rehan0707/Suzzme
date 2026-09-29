import Foundation

struct SuzzmeContextCollection: Sendable {
    var items: [SuzzmeContextItem]
    var unavailableSources: [String]
}

actor ContextEngine {
    private let privacyEngine: PrivacyEngine
    init(privacyEngine: PrivacyEngine = PrivacyEngine()) { self.privacyEngine = privacyEngine }

    func collect(from sources: [any ContextSource], request: SuzzmeContextRequest = .init()) async throws -> [SuzzmeContextItem] {
        try await collectWithHealth(from: sources, request: request).items
    }

    func collectWithHealth(from sources: [any ContextSource], request: SuzzmeContextRequest = .init()) async throws -> SuzzmeContextCollection {
        let gathered = await withTaskGroup(of: SuzzmeContextCollection.self) { group in
            for source in sources {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        return SuzzmeContextCollection(items: try await source.fetchContext(for: request), unavailableSources: [])
                    } catch { return SuzzmeContextCollection(items: [], unavailableSources: [source.identifier]) }
                }
            }
            var result = SuzzmeContextCollection(items: [], unavailableSources: [])
            for await value in group {
                result.items.append(contentsOf: value.items)
                result.unavailableSources.append(contentsOf: value.unavailableSources)
            }
            return result
        }
        try Task.checkCancellation()
        return .init(items: Array(normalize(gathered.items).filter { !$0.isExpired }.prefix(request.limit)),
                     unavailableSources: Array(Set(gathered.unavailableSources)).sorted())
    }

    func normalize(_ items: [SuzzmeContextItem]) -> [SuzzmeContextItem] {
        var normalized: [SuzzmeContextItem] = []
        for item in items {
            let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            let decision = privacyEngine.classify(([content] + item.entities + Array(item.metadata.values)).joined(separator: " "))
            guard decision.policy != .neverProcess else { continue }
            let sensitivity: SuzzmeContextSensitivity = Swift.max(item.sensitivity, decision.sensitivity)
            let normalizedItem = SuzzmeContextItem(
                id: item.id, sourceIdentifier: item.sourceIdentifier, content: content,
                timestamp: item.timestamp, entities: item.entities, intent: item.intent,
                importance: item.importance, sensitivity: sensitivity, metadata: item.metadata,
                expiration: item.expiration, confidence: item.confidence
            )
            let duplicate = normalized.contains {
                $0.sourceIdentifier == normalizedItem.sourceIdentifier &&
                $0.content == normalizedItem.content &&
                $0.timestamp == normalizedItem.timestamp
            }
            if !duplicate { normalized.append(normalizedItem) }
        }
        return normalized.sorted { lhs, rhs in
            if lhs.importance != rhs.importance { return lhs.importance.sortRank > rhs.importance.sortRank }
            return lhs.timestamp > rhs.timestamp
        }
    }

}

private extension SuzzmeItem.Priority {
    var sortRank: Int { switch self { case .urgent: 3; case .important: 2; case .normal: 1; case .low: 0 } }
}
