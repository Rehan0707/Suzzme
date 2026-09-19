import Foundation

actor ContextEngine {
    private let privacyEngine: PrivacyEngine
    init(privacyEngine: PrivacyEngine = PrivacyEngine()) { self.privacyEngine = privacyEngine }

    func collect(from sources: [any ContextSource], request: SuzzmeContextRequest = .init()) async throws -> [SuzzmeContextItem] {
        let gathered = await withTaskGroup(of: [SuzzmeContextItem].self, returning: [SuzzmeContextItem].self) { group in
            for source in sources {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        return try await source.fetchContext(for: request)
                    } catch is CancellationError {
                        return []
                    } catch {
                        // One unavailable future connector should not hide all local context.
                        return []
                    }
                }
            }
            var result: [SuzzmeContextItem] = []
            for await items in group { result.append(contentsOf: items) }
            return result
        }
        try Task.checkCancellation()
        return Array(normalize(gathered).filter { !$0.isExpired }.prefix(request.limit))
    }

    func normalize(_ items: [SuzzmeContextItem]) -> [SuzzmeContextItem] {
        var normalized: [SuzzmeContextItem] = []
        for item in items {
            let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            let decision = privacyEngine.classify(content)
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
