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
    private let information: InformationEngine?
    private let proactive: ProactiveIntelligenceEngine?
    private let contextEngine: ContextEngine
    private let router: IntelligenceRouter
    private let memory: SessionMemoryEngine
    private let privacy: PrivacyEngine
    private let longTermMemory: LongTermMemoryEngine
    private let memoryStore: LongTermMemoryStore?
    private let actionPlanner: SuzzmeActionPlanner
    private let actionCoordinator: SuzzmeActionExecutionCoordinator
    private let settingsPlanner: SuzzmeSettingsPlanner
    private let settingsCoordinator: SuzzmeSettingsCapabilityCoordinator?
    private var activeRequestID: UUID?
    private var pendingAction: SuzzmeAction?
    // One verified setting, for the immediately following utterance only.
    // No raw transcript, durable memory, or action authorization is retained.
    private var settingsFollowUp: (capability: SuzzmeSettingsCapabilityID, expiresAt: Date)?

    init(contextEngine: ContextEngine = ContextEngine(), router: IntelligenceRouter = IntelligenceRouter(), memory: SessionMemoryEngine = SessionMemoryEngine(), privacy: PrivacyEngine = PrivacyEngine(), memoryStore: LongTermMemoryStore? = nil, actionCoordinator: SuzzmeActionExecutionCoordinator? = nil, settingsCoordinator: SuzzmeSettingsCapabilityCoordinator? = nil, information: InformationEngine? = nil, proactive: ProactiveIntelligenceEngine? = nil) {
        self.contextEngine = contextEngine; self.router = router; self.memory = memory; self.privacy = privacy; self.longTermMemory = LongTermMemoryEngine(); self.memoryStore = memoryStore
        self.information = information
        self.proactive = proactive
        self.actionPlanner = SuzzmeActionPlanner()
        self.actionCoordinator = actionCoordinator ?? SuzzmeActionExecutionCoordinator(registry: SuzzmeCapabilityRegistry(capabilities: [EventKitReminderCapability(), EventKitCalendarCapability()]))
        self.settingsPlanner = SuzzmeSettingsPlanner()
        self.settingsCoordinator = settingsCoordinator
    }

    func respond(to text: String, sources: [any ContextSource], query: SuzzmeContextQuery = .init(), requestID: UUID = UUID(), confirmationActionID: UUID? = nil, existingFingerprints: Set<String>, contextUnavailableMessage: String? = nil, profileName: String? = nil, progress: @Sendable (SuzzmeAssistantState) async -> Void) async throws -> SuzzmeCoreResponse {
        let previousSetting = settingsFollowUp.flatMap { $0.expiresAt > .now ? $0.capability : nil }
        settingsFollowUp = nil
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
        try ensureActive(requestID)
        await actionCoordinator.begin(requestID: requestID)
        await settingsCoordinator?.begin(requestID: requestID)
        if let plan = await actionCoordinator.pendingPlan() {
            guard plan.requestID == requestID else { throw SuzzmeCapabilityError.staleRequest }
            if SuzzmeActionConfirmation.isAffirmative(text) {
                guard confirmationActionID == plan.id else { throw SuzzmeCapabilityError.staleRequest }
                await progress(.acting)
                do {
                    let result = try await actionCoordinator.confirm(actionID: plan.id, requestID: requestID)
                    guard activeRequestID == requestID, !Task.isCancelled else { throw CancellationError() }
                    if result.status == .success {
                        await progress(.success)
                        return .init(text: result.message, route: .localContext, contextCount: 0, extractedItems: [], action: action(from: plan, status: .completed))
                    }
                    await progress(.error)
                    return .init(text: result.message, route: .localContext, contextCount: 0, extractedItems: [], action: action(from: plan, status: .failed))
                } catch {
                    await progress(.error)
                    throw error
                }
            }
            if SuzzmeActionConfirmation.isCancellation(text) {
                guard confirmationActionID == plan.id else { throw SuzzmeCapabilityError.staleRequest }
                _ = await actionCoordinator.cancelPending()
                await actionCoordinator.cancel(requestID: plan.requestID)
                await progress(.success)
                return .init(text: "I cancelled \(plan.confirmationText.dropLast()).", route: .localContext, contextCount: 0, extractedItems: [], action: action(from: plan, status: .cancelled))
            }
            await progress(.awaitingConfirmation)
            return .init(text: "I’m waiting for your confirmation: \(plan.confirmationText)", route: .localContext, contextCount: 0, extractedItems: [], action: action(from: plan, status: .awaitingConfirmation))
        }
        let actionText: String
        if Self.isReferentialReminderRequest(text) {
            let session = await memory.snapshot()
            let referenced = Self.referencedContext(in: session)
            guard referenced.count == 1, let item = referenced.first else {
                await progress(.success)
                return .init(
                    text: referenced.isEmpty
                        ? "What would you like me to remind you about?"
                        : "Which item should I remind you about?",
                    route: .localContext,
                    contextCount: referenced.count,
                    extractedItems: []
                )
            }
            let title = (item.metadata["title"] ?? item.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            actionText = "Remind me to \(String(title.prefix(160))) tomorrow"
        } else {
            actionText = text
        }
        if let plan = try actionPlanner.plan(for: actionText, requestID: requestID) {
            pendingAction = nil
            await progress(.planning)
            let resolvedPlan = try await actionCoordinator.propose(plan)
            await progress(.awaitingConfirmation)
            return .init(text: resolvedPlan.confirmationText, route: .localContext, contextCount: 0, extractedItems: [], action: action(from: resolvedPlan, status: .awaitingConfirmation))
        }
        if let plan = try settingsPlanner.plan(for: text, requestID: requestID, previousCapability: previousSetting) {
            guard let settingsCoordinator else { throw SuzzmeCoreError.contextUnavailable }
            await progress(.planning)
            try ensureActive(requestID)
            await progress(.acting)
            let result = try await settingsCoordinator.execute(plan, requestID: requestID)
            try ensureActive(requestID)
            guard result.verified else { throw SuzzmeSettingsCapabilityError.verificationFailed }
            settingsFollowUp = (plan.capability, Date.now.addingTimeInterval(120))
            await progress(.success)
            return .init(text: result.message, route: .localContext, contextCount: 0, extractedItems: [])
        }
        if let confirmationActionID, pendingAction?.id != confirmationActionID { throw SuzzmeCapabilityError.staleRequest }
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
        if let informationQuery = InformationRequest.query(for: text), let information {
            await progress(.gatheringContext)
            // Recheck live snapshots. History never substitutes for a failed source.
            try await information.refresh(force: true)
            try ensureActive(requestID)
            let events = try await information.retrieve(informationQuery)
            let health = try await information.health()
            try ensureActive(requestID)
            await progress(.success)
            // Source text is quoted data, never sent to an action planner, model,
            // or memory admission. No model is needed for this bounded response.
            return .init(text: InformationRequest.response(events: events, health: health, query: informationQuery),
                         route: .localContext, contextCount: events.count, extractedItems: [])
        }
        if let contextUnavailableMessage, !isDailyOverviewRequest(text) {
            return .init(text: contextUnavailableMessage, route: .localContext, contextCount: 0, extractedItems: [])
        }
        await memory.remember(role: .user, text: text)
        await progress(.gatheringContext)
        if isDailyOverviewRequest(text), proactive != nil {
            // The explicit day question uses the same bounded relevance and
            // source-health pipeline as the Daily Summary screen.
            try? await information?.refresh(force: true)
            try ensureActive(requestID)
            do {
                let snapshot = try await prepareProactiveBriefing(from: sources, now: .now, profileName: profileName)
                if let briefing = snapshot.briefing,
                   !briefing.items.isEmpty || !briefing.healthLimitations.isEmpty {
                    await memory.remember(role: .assistant, text: briefing.narration)
                    await progress(.success)
                    return .init(text: briefing.narration, route: .localContext, contextCount: briefing.items.count, extractedItems: [])
                }
            } catch ProactiveError.disabled {
                // Turning scheduled summaries off must not disable direct,
                // user-initiated questions about the day.
            }
        }
        let session = await memory.snapshot()
        let priorContext = session.contextItems
        let gatheredContext = try await contextEngine.collect(from: sources, request: SuzzmeContextRequest(query: query))
        guard activeRequestID == requestID else { throw CancellationError() }
        let context = (priorContext + gatheredContext).reduce(into: [SuzzmeContextItem]()) { result, item in
            if !result.contains(where: { $0.id == item.id }) { result.append(item) }
        }
        await memory.remember(context: gatheredContext)
        await progress(.reasoning)
        let response = try await router.route(text: text, context: context, conversation: session.turns, existingFingerprints: existingFingerprints)
        guard activeRequestID == requestID else { throw CancellationError() }
        await memory.remember(role: .assistant, text: response.text)
        await progress(.success)
        return .init(text: response.text, route: response.route, contextCount: context.count, extractedItems: response.extractedItems)
    }

    func cancel(requestID: UUID) async {
        if activeRequestID == requestID { activeRequestID = nil; settingsFollowUp = nil; pendingAction = nil }
        await actionCoordinator.cancel(requestID: requestID)
        await settingsCoordinator?.cancel(requestID: requestID)
        if let memoryStore { await memoryStore.revoke(requestID) }
    }

    private func ensureActive(_ requestID: UUID) throws {
        try Task.checkCancellation()
        guard activeRequestID == requestID else { throw CancellationError() }
    }

    private func action(from plan: SuzzmeActionPlan, status: SuzzmeActionStatus) -> SuzzmeAction {
        let type: SuzzmeActionType = switch (plan.capability, plan.operation) {
        case (.reminders, .create): .createReminder
        case (.calendar, .create): .createCalendarEvent
        case (.reminders, .update): .updateReminder
        case (.reminders, .complete): .completeReminder
        case (.reminders, .delete): .deleteReminder
        case (.calendar, .update): .updateCalendarEvent
        case (.calendar, .delete): .deleteCalendarEvent
        case (.calendar, .complete): .updateCalendarEvent
        }
        let risk: SuzzmeActionRisk = .consequential
        return .init(id: plan.id, type: type, title: plan.confirmationText, risk: risk, status: status)
    }

    func clearSession() async { settingsFollowUp = nil; await memory.clear() }

    func proactivePreferences() async throws -> ProactivePreferences {
        guard let proactive else { throw ProactiveError.invalidState }
        return try await proactive.preferences()
    }

    func updateProactivePreferences(_ preferences: ProactivePreferences) async throws {
        guard let proactive else { throw ProactiveError.invalidState }
        try await proactive.updatePreferences(preferences)
    }

    func prepareProactiveBriefing(from sources: [any ContextSource], now: Date = .now, profileName: String? = nil) async throws -> ProactiveSnapshot {
        guard let proactive else { throw ProactiveError.invalidState }
        let snapshot = try await proactive.prepare(from: sources, now: now, profileName: profileName)
        if let briefing = snapshot.briefing {
            let context = briefing.items.prefix(ProactiveLimits.briefingItems).map { item in
                SuzzmeContextItem(
                    sourceIdentifier: "proactive:\(item.candidateID)",
                    content: item.summary,
                    timestamp: briefing.createdAt,
                    entities: item.relatedEntities,
                    intent: item.kind == .schedule || item.kind == .scheduleChange ? .event : item.kind == .reminder || item.kind == .deadline ? .reminder : .information,
                    importance: item.delivery == .timeCritical ? .urgent : .important,
                    sensitivity: item.sensitivity,
                    metadata: [
                        "candidateID": item.candidateID,
                        "source": "proactive-briefing",
                        "title": item.summary,
                        "kind": item.kind.rawValue,
                        "effectiveAt": item.effectiveTime.map { ISO8601DateFormatter().string(from: $0) } ?? ""
                    ],
                    expiration: briefing.coverageWindow.end,
                    confidence: item.confidence
                )
            }
            await memory.remember(context: context)
        }
        return snapshot
    }

    private func isDailyOverviewRequest(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("what do i have today")
            || lower.contains("what matters today")
            || lower.contains("daily summary")
            || lower.contains("summarize my day")
            || lower.contains("tell me about my day")
    }

    private static func isReferentialReminderRequest(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return lower == "remind me tomorrow"
            || lower == "remind me about that tomorrow"
            || lower == "remind me about it tomorrow"
    }

    private static func referencedContext(in session: SuzzmeSessionSnapshot) -> [SuzzmeContextItem] {
        guard let answer = session.turns.last(where: { $0.role == .assistant })?.text else { return [] }
        return session.contextItems.filter { item in
            answer.localizedCaseInsensitiveContains(item.content)
                || item.metadata["title"].map { answer.localizedCaseInsensitiveContains($0) } == true
        }
    }

    func currentProactiveSnapshot(now: Date = .now) async throws -> ProactiveSnapshot {
        guard let proactive else { throw ProactiveError.invalidState }
        return try await proactive.current(now: now)
    }

    func dismissOpportunity(id: UUID) async throws {
        guard let proactive else { throw ProactiveError.invalidState }
        try await proactive.dismissOpportunity(id: id)
    }

    func markProactiveDelivered(candidateID: String, at date: Date = .now) async throws {
        guard let proactive else { throw ProactiveError.invalidState }
        try await proactive.markDelivered(candidateID: candidateID, at: date)
    }

    func markBriefingDelivered(id: UUID, partial: Bool) async throws {
        guard let proactive else { throw ProactiveError.invalidState }
        try await proactive.markBriefingDelivered(id: id, partial: partial)
    }

    func resetProactiveData() async throws {
        guard let proactive else { throw ProactiveError.invalidState }
        try await proactive.reset()
        settingsFollowUp = nil
        await memory.clear()
    }

    func clearProactiveContent() async throws {
        guard let proactive else { throw ProactiveError.invalidState }
        try await proactive.clearProactiveContent()
        settingsFollowUp = nil
        await memory.clear()
    }

    func cancelProactivePreparation() async {
        await proactive?.cancel()
    }
}

enum SuzzmeCoreError: LocalizedError, Sendable { case restrictedContent, contextUnavailable
    var errorDescription: String? { switch self { case .restrictedContent: "Suzzme won’t process secret or authentication information."; case .contextUnavailable: "Your local context is not available right now." } }
}
