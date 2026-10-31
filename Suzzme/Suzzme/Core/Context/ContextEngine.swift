import Foundation

struct SuzzmeContextCollection: Sendable {
    var items: [SuzzmeContextItem]
    var unavailableSources: [String]
}

actor ContextEngine {
    private let privacyEngine: PrivacyEngine
    init(privacyEngine: PrivacyEngine = PrivacyEngine()) { self.privacyEngine = privacyEngine }

    func collectResource(from source: any SuzzmeResourceContextProviding, question: String, requestID: UUID,
                         summaryReference: SuzzmeSummaryResourceReference? = nil) async throws -> SuzzmeResourceContext? {
        let result: SuzzmeResourceContext?
        if let summaryReference { result = try await source.readSummaryReference(summaryReference, requestID: requestID) }
        else { result = try await source.readContext(for: question, requestID: requestID) }
        guard let context = result else { return nil }
        try Task.checkCancellation()
        let age = Date.now.timeIntervalSince(context.capturedAt)
        guard age >= 0, age <= 30, context.content.utf8.count <= 32_768,
              context.provenance.utf8.count <= 512,
              privacyEngine.classify(context.content).policy != .neverProcess,
              await source.validate(context, requestID: requestID) else { throw SuzzmeResourceContextFailure(recovery: "This resource is stale, restricted, or too large. Share the current resource and try again.") }
        return context
    }

    /// Ephemeral sources never pass through normalize/SessionMemory. Images
    /// stay in this request's stack and cannot become durable context items.
    func collectScreen(from source: any ScreenContextSource, requestID: UUID) async throws -> ScreenContext {
        let screen = try await source.capture(requestID: requestID)
        try Task.checkCancellation()
        guard screen.isCurrent(requestID: requestID), screen.privacyClassification.policy != .neverProcess,
              screen.privacyClassification.sensitivity != .restricted,
              screen.image.count <= 4 * 1_024 * 1_024,
              screen.pixelWidth > 0, screen.pixelHeight > 0,
              screen.pixelWidth <= 1_600, screen.pixelHeight <= 1_600,
              await source.validate(screen) else { throw ScreenContextError.captureUnavailable }
        let structuralText = ([screen.accessibilityText, screen.recognizedText].compactMap { $0 }
            + screen.textRegions.map(\.text)).joined(separator: " ")
        guard privacyEngine.classify(structuralText).policy != .neverProcess else { throw ScreenContextError.sensitiveContent }
        return screen
    }

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
