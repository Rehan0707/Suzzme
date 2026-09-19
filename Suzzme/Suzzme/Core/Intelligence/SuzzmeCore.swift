import Foundation

struct SuzzmeCoreResponse: Sendable {
    let text: String
    let route: SuzzmeRoute
    let contextCount: Int
    let extractedItems: [SuzzmeItem]
    let action: SuzzmeAction?

    init(text: String, route: SuzzmeRoute, contextCount: Int, extractedItems: [SuzzmeItem], action: SuzzmeAction? = nil) {
        self.text = text; self.route = route; self.contextCount = contextCount; self.extractedItems = extractedItems; self.action = action
    }
}

/// Coordinates narrow engines; it owns no UI and exposes only concise progress.
actor SuzzmeCore {
    private let contextEngine: ContextEngine
    private let router: IntelligenceRouter
    private let memory: SessionMemoryEngine
    private let privacy: PrivacyEngine
    private let longTermMemory: LongTermMemoryEngine
    private let memoryStore: LongTermMemoryStore?
    private var activeRequestID: UUID?
    private var pendingAction: SuzzmeAction?

    init(contextEngine: ContextEngine = ContextEngine(), router: IntelligenceRouter = IntelligenceRouter(), memory: SessionMemoryEngine = SessionMemoryEngine(), privacy: PrivacyEngine = PrivacyEngine(), memoryStore: LongTermMemoryStore? = nil) {
        self.contextEngine = contextEngine; self.router = router; self.memory = memory; self.privacy = privacy; self.longTermMemory = LongTermMemoryEngine(); self.memoryStore = memoryStore
    }

    func respond(to text: String, sources: [any ContextSource], query: SuzzmeContextQuery = .init(), requestID: UUID = UUID(), existingFingerprints: Set<String>, progress: @Sendable (SuzzmeAssistantState) async -> Void) async throws -> SuzzmeCoreResponse {
        activeRequestID = requestID
        if let memoryStore { await memoryStore.authorize(requestID) }
        // Releasing this request's capability makes a late continuation unable
        // to mutate long-term memory after it finishes or is cancelled. A newer
        // request has its own capability, so this cannot revoke its access.
        defer {
            let memoryStore = memoryStore
            Task { await memoryStore?.revoke(requestID) }
        }
        try Task.checkCancellation()
        await progress(.understanding)
        let decision = privacy.classify(text)
        guard decision.policy != .neverProcess else { throw SuzzmeCoreError.restrictedContent }
        if let action = pendingAction {
            let reply = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["yes", "confirm", "confirm deletion"].contains(reply), action.requiresConfirmation {
                pendingAction = nil
                guard let memoryStore, action.contextIDs.count == 1 else { throw SuzzmeCoreError.contextUnavailable }
                try ensureActive(requestID)
                let result = try await memoryStore.commit(.bulkForgetProject(action.contextIDs[0]), requestID: requestID)
                guard activeRequestID == requestID, !Task.isCancelled else { throw CancellationError() }
                if case let .bulkForgotten(count) = result, count > 0 {
                    return .init(text: "I forgot the memory about that project.", route: .localContext, contextCount: 0, extractedItems: [], action: SuzzmeAction(id: action.id, type: action.type, title: action.title, risk: action.risk, status: .completed, contextIDs: action.contextIDs))
                }
                return .init(text: "That project memory was already unavailable.", route: .localContext, contextCount: 0, extractedItems: [])
            }
            if ["no", "cancel", "don't"].contains(reply) {
                pendingAction = nil
                return .init(text: "I kept that memory.", route: .localContext, contextCount: 0, extractedItems: [], action: SuzzmeAction(id: action.id, type: action.type, title: action.title, risk: action.risk, status: .cancelled, contextIDs: action.contextIDs))
            }
        }
        if let memoryStore, await memoryStore.isEnabled() {
            let operation = longTermMemory.command(for: text)
            switch operation {
            case let .remember(type, name, detail):
                let mutation: LongTermMemoryMutation = detail == "Your main project" ? .mainProject(name) : .remember(type: type, name: name, detail: detail)
                try ensureActive(requestID)
                if case let .memory(stored) = try await memoryStore.commit(mutation, requestID: requestID) {
                    return .init(text: "I’ll remember \(stored.name).", route: .localContext, contextCount: 0, extractedItems: [])
                }
            case let .preference(name, slot):
                try ensureActive(requestID)
                if case let .memory(stored) = try await memoryStore.commit(.preference(name: name, slot: slot), requestID: requestID) {
                    return .init(text: "I’ll remember your preference for \(stored.name).", route: .localContext, contextCount: 0, extractedItems: [])
                }
            case let .temporal(place):
                try ensureActive(requestID)
                if case let .memory(stored) = try await memoryStore.commit(.temporalStay(place: place, referenceDate: .now, timeZoneIdentifier: TimeZone.current.identifier), requestID: requestID) {
                    return .init(text: "I’ll remember your stay in \(stored.name) for this weekend.", route: .localContext, contextCount: 0, extractedItems: [])
                }
            case let .relate(person, project):
                if case .ambiguous = try await memoryStore.resolvePerson(person) {
                    return .init(text: "Which \(person) do you mean?", route: .localContext, contextCount: 0, extractedItems: [])
                }
                try ensureActive(requestID)
                if case let .relationship(personRecord, projectRecord) = try await memoryStore.commit(.relationship(person: person, project: project), requestID: requestID) {
                    return .init(text: "I’ll remember that \(personRecord.name) is helping you with \(projectRecord.name).", route: .localContext, contextCount: 0, extractedItems: [])
                }
            case let .forgetRelationship(person, project):
                try ensureActive(requestID)
                if case let .relationshipForgotten(forgotten) = try await memoryStore.commit(.forgetRelationship(person: person, project: project), requestID: requestID), forgotten {
                    return .init(text: "I forgot that \(person) helps with \(project).", route: .localContext, contextCount: 0, extractedItems: [])
                }
            case let .bulkForget(project):
                guard let projectID = try await memoryStore.projectID(named: project) else {
                    return .init(text: "I couldn’t find a saved project named \(project).", route: .localContext, contextCount: 0, extractedItems: [])
                }
                let action = SuzzmeAction(type: .forgetMemory, title: "Delete Suzzme Memory for \(project)", risk: .consequential, status: .awaitingConfirmation, contextIDs: [projectID])
                pendingAction = action
                await progress(.awaitingConfirmation)
                return .init(text: "I found memory about \(project). Delete it and its related memory?", route: .localContext, contextCount: 0, extractedItems: [], action: action)
            case let .retrieve(query):
                let records = try await memoryStore.memories(limit: 80)
                let matches = longTermMemory.relevantMemories(records, query: query)
                let graph = try await memoryStore.related(to: query)
                let result = Array(Set(matches + graph)).prefix(12)
                if !result.isEmpty { return .init(text: result.map { "\($0.name): \($0.detail)" }.joined(separator: "\n"), route: .localContext, contextCount: result.count, extractedItems: []) }
            case .forget, .none:
                break
            }
        }
        await memory.remember(role: .user, text: text)
        await progress(.gatheringContext)
        let priorContext = await memory.snapshot().contextItems
        let gatheredContext = try await contextEngine.collect(from: sources, request: SuzzmeContextRequest(query: query))
        guard activeRequestID == requestID else { throw CancellationError() }
        let context = (priorContext + gatheredContext).reduce(into: [SuzzmeContextItem]()) { result, item in
            if !result.contains(where: { $0.id == item.id }) { result.append(item) }
        }
        await memory.remember(context: gatheredContext)
        await progress(.reasoning)
        let response = try await router.route(text: text, context: context, existingFingerprints: existingFingerprints)
        guard activeRequestID == requestID else { throw CancellationError() }
        await memory.remember(role: .assistant, text: response.text)
        await progress(.success)
        return .init(text: response.text, route: response.route, contextCount: context.count, extractedItems: response.extractedItems)
    }

    func cancel(requestID: UUID) async {
        if activeRequestID == requestID { activeRequestID = nil }
        if let memoryStore { await memoryStore.revoke(requestID) }
    }

    private func ensureActive(_ requestID: UUID) throws {
        try Task.checkCancellation()
        guard activeRequestID == requestID else { throw CancellationError() }
    }

    func clearSession() async { await memory.clear() }
}

enum SuzzmeCoreError: LocalizedError, Sendable { case restrictedContent, contextUnavailable
    var errorDescription: String? { switch self { case .restrictedContent: "Suzzme won’t process secret or authentication information."; case .contextUnavailable: "Your local context is not available right now." } }
}
