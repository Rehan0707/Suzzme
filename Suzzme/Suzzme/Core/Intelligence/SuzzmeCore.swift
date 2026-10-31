import Foundation

struct SuzzmeCoreResponse: Sendable {
    let text: String
    let route: SuzzmeRoute
    let contextCount: Int
    let extractedItems: [SuzzmeItem]
    let action: SuzzmeAction?
    let spatialReference: SpatialReference?
    let screenMetadata: ScreenContextMetadata?

    init(text: String, route: SuzzmeRoute, contextCount: Int, extractedItems: [SuzzmeItem], action: SuzzmeAction? = nil, spatialReference: SpatialReference? = nil, screenMetadata: ScreenContextMetadata? = nil) {
        self.text = text; self.route = route; self.contextCount = contextCount; self.extractedItems = extractedItems; self.action = action
        self.spatialReference = spatialReference; self.screenMetadata = screenMetadata
    }
}

/// Coordinates narrow engines; it owns no UI and exposes only concise progress.
actor SuzzmeCore {
    private let information: InformationEngine?
    private let proactive: ProactiveIntelligenceEngine?
    private let resourceContext: (any SuzzmeResourceContextProviding)?
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

    init(contextEngine: ContextEngine = ContextEngine(), router: IntelligenceRouter = IntelligenceRouter(), memory: SessionMemoryEngine = SessionMemoryEngine(), privacy: PrivacyEngine = PrivacyEngine(), memoryStore: LongTermMemoryStore? = nil, actionCoordinator: SuzzmeActionExecutionCoordinator? = nil, settingsCoordinator: SuzzmeSettingsCapabilityCoordinator? = nil, information: InformationEngine? = nil, proactive: ProactiveIntelligenceEngine? = nil, resourceContext: (any SuzzmeResourceContextProviding)? = nil) {
        self.contextEngine = contextEngine; self.router = router; self.memory = memory; self.privacy = privacy; self.longTermMemory = LongTermMemoryEngine(); self.memoryStore = memoryStore
        self.information = information
        self.proactive = proactive
        self.resourceContext = resourceContext
        self.actionPlanner = SuzzmeActionPlanner()
        self.actionCoordinator = actionCoordinator ?? SuzzmeActionExecutionCoordinator(registry: SuzzmeCapabilityRegistry(capabilities: [EventKitReminderCapability(), EventKitCalendarCapability()]))
        self.settingsPlanner = SuzzmeSettingsPlanner()
        self.settingsCoordinator = settingsCoordinator
    }

    func respond(to text: String, sources: [any ContextSource], query: SuzzmeContextQuery = .init(), requestID: UUID = UUID(), confirmationActionID: UUID? = nil, existingFingerprints: Set<String>, contextUnavailableMessage: String? = nil, profileName: String? = nil, screenSource: (any ScreenContextSource)? = nil, visualGuidance: Bool = false, explicitResource: SuzzmeResourceContext? = nil, conversationID: UUID? = nil, progress: @Sendable (SuzzmeAssistantState) async -> Void) async throws -> SuzzmeCoreResponse {
        let previousSetting = settingsFollowUp.flatMap { $0.expiresAt > .now ? $0.capability : nil }
        settingsFollowUp = nil
        activeRequestID = requestID
        if let explicitResource {
            await memory.beginReadOnlyRequest(requestID, conversationID: conversationID)
            pendingAction = nil
            _ = await actionCoordinator.cancelPending()
            await settingsCoordinator?.begin(requestID: requestID)
            try ensureActive(requestID)
            guard let resourceContext, privacy.classify(text).policy != .neverProcess,
                  await resourceContext.validate(explicitResource, requestID: requestID) else { throw SuzzmeCoreError.restrictedContent }
            try ensureActive(requestID); await progress(.reasoning)
            let answer = try await router.answerResource(question: text, context: explicitResource)
            try ensureActive(requestID)
            guard await resourceContext.validate(explicitResource, requestID: requestID), privacy.classify(answer.text).policy != .neverProcess else { throw CancellationError() }
            await resourceContext.cancel(requestID: requestID); await progress(.success)
            return .init(text: answer.text, route: answer.route, contextCount: 1, extractedItems: [])
        }
        await memory.beginReadOnlyRequest(requestID, conversationID: conversationID)
        try ensureActive(requestID)
        let summaryReferences = Set(await memory.snapshot().contextItems.filter {
            ["connectedApps", "watchedWeb", "gmail"].contains($0.metadata["authoritySource"] ?? $0.metadata["source"] ?? "")
        }.map(\.sourceIdentifier))
        if !summaryReferences.isEmpty {
            let allowed = Set((try? await information?.retrieve(.init(sources: [.connectedApps, .watchedWeb, .gmail], limit: InformationLimits.records)))?.map(\.externalID) ?? [])
            if !summaryReferences.isSubset(of: allowed) {
                // Assistant turns can quote the revoked titles too. Retire the
                // bounded conversation, not just its structured fact array.
                await memory.clearRevokedContext(requestID: requestID)
            }
            try ensureActive(requestID)
        }
        // Screen data has a separate, read-only route in this same Core. It
        // never receives a memory capability, reaches a planner, or enters any
        // actionable session facts, information or Daily Context store. Only a
        // bounded derived answer may support a later read-only question.
        if screenSource != nil || ScreenContextPolicy.isScreenQuestion(text) {
            guard privacy.classify(text).policy != .neverProcess else { throw SuzzmeCoreError.restrictedContent }
            await memory.clearScreenUnderstanding()
            try ensureActive(requestID)
            await progress(.gatheringContext)
            guard let screenSource else {
                await progress(.success)
                return .init(text: "Screen Awareness is off for this request. Use Ask about this screen to allow a single capture.", route: .localContext, contextCount: 0, extractedItems: [])
            }
            do {
                let screen = try await contextEngine.collectScreen(from: screenSource, requestID: requestID)
                try ensureActive(requestID)
                // Only explicitly requested personal context is collected, from
                // the same authorized sources. Screen text cannot select sources.
                let personal = query.sources.isEmpty ? [] : try await contextEngine.collect(from: sources, request: .init(query: query))
                try ensureActive(requestID)
                await progress(.reasoning)
                let wantsGuidance = visualGuidance && ScreenContextPolicy.asksForGuidance(text)
                let answer = try await router.answerScreen(question: text, context: screen, wantsGuidance: wantsGuidance, personalContext: personal)
                try ensureActive(requestID)
                guard await screenSource.validate(screen) else { throw ScreenContextError.focusChanged }
                try ensureActive(requestID)
                let responseText = answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !responseText.isEmpty, responseText.count <= 2_000,
                      privacy.classify(responseText).policy != .neverProcess else { throw SuzzmeIntelligenceError.invalidOutput }
                let reference = answer.spatialReference.flatMap {
                    wantsGuidance && $0.isValid(for: screen, requestID: requestID, now: .now) ? $0 : nil
                }
                await screenSource.cancel(requestID: requestID)
                try ensureActive(requestID)
                if answer.usedOnDeviceModel {
                    await memory.rememberScreenUnderstanding(requestID: requestID, question: text, answer: responseText)
                    try ensureActive(requestID)
                }
                await progress(.success)
                return .init(text: responseText, route: answer.usedOnDeviceModel ? .onDeviceIntelligence : .localContext,
                    contextCount: 1 + personal.count, extractedItems: [], spatialReference: reference,
                    screenMetadata: reference == nil ? nil : screen.metadata)
            } catch {
                await screenSource.cancel(requestID: requestID)
                throw error
            }
        }
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
        // Account-backed external facts have their own ephemeral read route.
        // The same existing model has no tools; results cannot reach any planner.
        let summaryReference: SuzzmeSummaryResourceReference?
        if let resourceContext, screenSource == nil, !ScreenContextPolicy.isScreenQuestion(text) {
            summaryReference = await resourceContext.resolveSummaryReference(text, context: await memory.snapshot().contextItems)
        } else { summaryReference = nil }
        if let resourceContext, screenSource == nil, !ScreenContextPolicy.isScreenQuestion(text), await resourceContext.recognizes(summaryReference?.question ?? text) {
            try ensureActive(requestID)
            guard privacy.classify(text).policy != .neverProcess else { throw SuzzmeCoreError.restrictedContent }
            await progress(.gatheringContext)
            do {
                if let resource = try await contextEngine.collectResource(from: resourceContext, question: text, requestID: requestID, summaryReference: summaryReference) {
                    try ensureActive(requestID)
                    await progress(.reasoning)
                    let answer = try await router.answerResource(question: text, context: resource)
                    try ensureActive(requestID)
                    guard await resourceContext.validate(resource, requestID: requestID),
                          privacy.classify(answer.text).policy != .neverProcess else { throw CancellationError() }
                    await resourceContext.cancel(requestID: requestID)
                    try ensureActive(requestID)
                    await progress(.success)
                    return .init(text: answer.text, route: answer.route, contextCount: 1, extractedItems: [])
                }
            } catch let failure as SuzzmeResourceContextFailure {
                await resourceContext.cancel(requestID: requestID)
                try ensureActive(requestID)
                await progress(.error)
                return .init(text: failure.recovery, route: .localContext, contextCount: 0, extractedItems: [])
            } catch {
                await resourceContext.cancel(requestID: requestID)
                throw error
            }
        }
        let emailFollowUp = ["who sent the latest one", "who sent the latest email", "and what about the email", "what about the email"].contains(text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)))
        if emailFollowUp, let information {
            let referenced = await memory.snapshot().contextItems.filter { $0.metadata["source"] == "gmail" && !$0.isExpired }
            try ensureActive(requestID)
            guard !referenced.isEmpty else { return .init(text: "Which selected email source do you mean? Ask about your selected Gmail headers first.", route: .localContext, contextCount: 0, extractedItems: []) }
            await progress(.gatheringContext); try await information.refresh(source: .gmail, force: true)
            let events = try await information.retrieve(.init(sources: [.gmail], limit: 30)).sorted { $0.sourceUpdatedAt > $1.sourceUpdatedAt }
            try ensureActive(requestID)
            guard let latest = events.first, referenced.contains(where: { reference in
                let accountPrefix = reference.sourceIdentifier.split(separator: ":").prefix(4).joined(separator: ":") + ":"
                return latest.externalID.hasPrefix(accountPrefix)
            }) else { return .init(text: "The referenced Gmail source is no longer available. Refresh its authorized headers before continuing.", route: .localContext, contextCount: 0, extractedItems: []) }
            await progress(.success)
            return .init(text: "Latest authorized header: “\(latest.title)”. Checked \(latest.observedAt.formatted()). Message bodies were not read.", route: .localContext, contextCount: 1, extractedItems: [])
        }
        if var informationQuery = InformationRequest.query(for: text), let information {
            let calendarChanges = text.localizedCaseInsensitiveContains("calendar")
            let taskChanges = text.localizedCaseInsensitiveContains("reminder")
            if calendarChanges || taskChanges { informationQuery.sources.insert(.connectedApps) }
            await progress(.gatheringContext)
            // Recheck live snapshots. History never substitutes for a failed source.
            try await information.refresh(force: true)
            try ensureActive(requestID)
            let events = try await information.retrieve(informationQuery).filter { event in
                if calendarChanges { return event.source == .calendar || event.entities.contains("googleCalendar") }
                if taskChanges { return event.source == .reminders || event.entities.contains("googleTasks") }
                return true
            }
            let health = try await information.health()
            try ensureActive(requestID)
            await progress(.success)
            // Selected header references support a bounded read-only follow-up.
            // They never enter long-term Memory or action planning.
            if informationQuery.sources == [.gmail] {
                await memory.remember(context: events.map { event in
                    .init(sourceIdentifier: event.externalID, content: event.title,
                          timestamp: event.observedAt, metadata: ["source": "gmail"],
                          expiration: Date.now.addingTimeInterval(120))
                })
                try ensureActive(requestID)
            }
            // Source text stays quoted data. No model or memory admission runs.
            return .init(text: InformationRequest.response(events: events, health: health, query: informationQuery),
                         route: .localContext, contextCount: events.count, extractedItems: [])
        }
        let precedingSession = await memory.snapshot()
        try ensureActive(requestID)
        let hasScreenFollowUp = precedingSession.screenUnderstanding != nil && SuzzmeScreenUnderstanding.isFollowUp(text)
        let selectedGoogle = try await selectedGoogleContext(for: text, query: query)
        try ensureActive(requestID)
        if let contextUnavailableMessage, selectedGoogle.isEmpty, !isDailyOverviewRequest(text), !hasScreenFollowUp {
            return .init(text: contextUnavailableMessage, route: .localContext, contextCount: 0, extractedItems: [])
        }
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
                    guard await memory.rememberReadOnlyExchange(question: text, answer: briefing.narration, requestID: requestID) else { throw CancellationError() }
                    await progress(.success)
                    return .init(text: briefing.narration, route: .localContext, contextCount: briefing.items.count, extractedItems: [])
                }
            } catch ProactiveError.disabled {
                // Turning scheduled summaries off must not disable direct,
                // user-initiated questions about the day.
            }
        }
        if text.lowercased().contains("what happened in my projects today") {
            // An empty project summary is not a general-knowledge question.
            // Reuse Information's authorized projection and health disclosure;
            // never ask a model to invent activity (or an earlier screen).
            guard let information else { throw SuzzmeCoreError.contextUnavailable }
            let projectQuery = InformationQuery(sources: [.connectedApps], since: Calendar.current.startOfDay(for: .now), limit: 5)
            let events = try await information.retrieve(projectQuery)
            let health = try await information.health()
            try ensureActive(requestID)
            let answer = InformationRequest.response(events: events, health: health, query: projectQuery)
            guard await memory.rememberReadOnlyExchange(question: text, answer: answer, requestID: requestID) else { throw CancellationError() }
            await progress(.success)
            return .init(text: answer, route: .localContext, contextCount: events.count, extractedItems: [])
        }
        let session = await memory.snapshot()
        let collection = try await contextEngine.collectWithHealth(from: sources, request: SuzzmeContextRequest(query: query))
        try ensureActive(requestID)
        let nativeIDs = Set(collection.items.compactMap { $0.metadata["icalUID"] })
        let gatheredContext = collection.items + selectedGoogle.filter { item in
            guard let uid = item.metadata["icalUID"], nativeIDs.contains(uid) else { return true }
            return !collection.items.contains { $0.metadata["icalUID"] == uid && $0.metadata["title"] == item.metadata["title"] && $0.metadata["start"] == item.metadata["start"] && $0.metadata["end"] == item.metadata["end"] && $0.metadata["allDay"] == item.metadata["allDay"] }
        }
        guard activeRequestID == requestID else { throw CancellationError() }
        // A freshly checked open-work query replaces the conversational reminder
        // selection. Prior session facts cannot resurrect completed/deleted work.
        // An unavailable source never proves absence.
        let replacingReminders = sources.contains(where: { $0.identifier == "reminders" }) && !collection.unavailableSources.contains("reminders")
        guard await memory.replaceSelectedInformationContext(with: selectedGoogle, gatheredContext: gatheredContext,
            replacingReminders: replacingReminders, requestID: requestID) else { throw CancellationError() }
        try ensureActive(requestID)
        let currentSession = await memory.snapshot()
        let context = SessionMemoryEngine.merging(currentSession.contextItems, with: gatheredContext).filter {
            !collection.unavailableSources.contains($0.metadata["source"] ?? "")
        }
        await progress(.reasoning)
        let response = try await router.route(text: text, context: context, conversation: session.turns,
            screenUnderstanding: currentSession.screenUnderstanding, existingFingerprints: existingFingerprints)
        guard activeRequestID == requestID else { throw CancellationError() }
        let answer = collection.unavailableSources.contains("reminders")
            ? "I couldn’t check Reminders right now. " + response.text : response.text
        guard await memory.rememberReadOnlyExchange(question: text, answer: answer, requestID: requestID) else { throw CancellationError() }
        try ensureActive(requestID)
        await progress(.success)
        return .init(text: answer, route: response.route, contextCount: context.count, extractedItems: response.extractedItems)
    }

    /// Authorized Information projection into the existing question route. No
    /// second Context engine, remote model, durable snapshot or action authority.
    private func selectedGoogleContext(for text: String, query: SuzzmeContextQuery) async throws -> [SuzzmeContextItem] {
        guard let information, !isDailyOverviewRequest(text), !SuzzmeQuestionIntent.isGeneralExplanation(text),
              SuzzmeQuestionIntent.classify(text) != .capture,
              ["schedule", "meeting", "tomorrow", "today", "task", "due", "unfinished", "priorit", "focus", "when", "what time"].contains(where: text.lowercased().contains) else { return [] }
        try await information.refresh(source: .connectedApps, force: true)
        var result: [SuzzmeContextItem] = []
        for (service, kind) in [("googleCalendar", SuzzmeContextSourceKind.calendar), ("googleTasks", .reminders)] where query.sources.contains(kind) {
            let events = try await information.retrieve(.init(sources: [.connectedApps], entity: service, limit: query.limit))
            for event in events where event.objectState == .active {
                if let range = query.dateRange, let date = event.effectiveAt, !range.contains(date) { continue }
                if text.localizedCaseInsensitiveContains("morning"), let date = event.effectiveAt, Calendar.current.component(.hour, from: date) >= 12 { continue }
                var metadata = ["source": kind.rawValue, "authoritySource": "connectedApps", "title": event.title,
                                "provider": service, "completed": "false", "allDay": String(event.isAllDay == true)]
                if let date = event.effectiveAt { metadata[kind == .calendar ? "start" : "due"] = ISO8601DateFormatter().string(from: date) }
                if let end = event.effectiveUntil { metadata["end"] = ISO8601DateFormatter().string(from: end) }
                if let uid = event.entities.first(where: { $0.hasPrefix("ical:") }) { metadata["icalUID"] = String(uid.dropFirst(5)) }
                result.append(.init(sourceIdentifier: event.externalID, content: event.title, timestamp: event.observedAt,
                                    intent: kind == .calendar ? .event : .task, metadata: metadata,
                                    expiration: min(event.expiresAt, Date.now.addingTimeInterval(120))))
            }
        }
        return Array(result.prefix(query.limit))
    }

    func cancel(requestID: UUID) async {
        if activeRequestID == requestID { activeRequestID = nil; settingsFollowUp = nil; pendingAction = nil }
        await memory.retireReadOnlyRequest(requestID)
        await resourceContext?.cancel(requestID: requestID)
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

    func prepareProactiveBriefing(from sources: [any ContextSource], now: Date = .now, profileName: String? = nil, rememberInSession: Bool = true, calendar: Calendar = .current, summaryCutoff: Date? = nil) async throws -> ProactiveSnapshot {
        guard let proactive else { throw ProactiveError.invalidState }
        let snapshot = try await proactive.prepare(from: sources, now: now, calendar: calendar, profileName: profileName, summaryCutoff: summaryCutoff ?? now)
        if rememberInSession, let briefing = snapshot.briefing {
            let context = briefing.items.prefix(ProactiveLimits.briefingItems).map { item in
                let provenance = snapshot.dailyContext?.entries.first { $0.id == item.candidateID }
                return SuzzmeContextItem(
                    sourceIdentifier: provenance?.sourceReference ?? "proactive:\(item.candidateID)",
                    content: item.summary,
                    timestamp: briefing.createdAt,
                    entities: item.relatedEntities,
                    intent: item.kind == .schedule || item.kind == .scheduleChange ? .event : item.kind == .reminder || item.kind == .deadline ? .reminder : .information,
                    importance: item.delivery == .timeCritical ? .urgent : .important,
                    sensitivity: item.sensitivity,
                    metadata: [
                        "candidateID": item.candidateID,
                        "source": provenance?.source ?? "proactive-briefing",
                        "proactiveProjection": "true",
                        "title": provenance?.title ?? item.summary,
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
        return SuzzmeQuestionIntent.classify(text) == .priorities && !lower.contains("tomorrow")
            || lower.contains("what do i have today")
            || lower.contains("what happened in my projects today")
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

    func cancelProactivePreparation(respectingTaskCancellation: Bool = false) async {
        guard !respectingTaskCancellation || !Task.isCancelled else { return }
        await proactive?.cancel(respectingTaskCancellation: respectingTaskCancellation)
    }
}

enum SuzzmeCoreError: LocalizedError, Sendable { case restrictedContent, contextUnavailable
    var errorDescription: String? { switch self { case .restrictedContent: "Suzzme won’t process secret or authentication information."; case .contextUnavailable: "Your local context is not available right now." } }
}
