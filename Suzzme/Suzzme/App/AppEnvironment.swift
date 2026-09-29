import Foundation
import Observation

@MainActor @Observable
final class AppEnvironment {
    private let understandingPipeline: SuzzmeUnderstandingPipeline
    private let core: SuzzmeCore
    private let information: InformationEngine?
    private let proactive: ProactiveIntelligenceEngine?
    private let watchedLinkStore: WatchedLinkStore
    private let proactiveNotifications = ProactiveNotificationDelivery()
    private(set) var informationHealth: [InformationHealth] = []
    private(set) var informationEvents: [InformationEvent] = []
    private(set) var informationError: String?
    private(set) var isRefreshingInformation = false
    private(set) var proactivePreferences = ProactivePreferences()
    private(set) var proactiveSnapshot: ProactiveSnapshot?
    private(set) var proactiveError: String?
    private(set) var isPreparingBriefing = false
    private(set) var watchedLinks: [WatchedLinkRecord] = []
    private(set) var watchedLinkError: String?
    private let privacy = PrivacyEngine()
    private let permissions = AppleContextPermissions()
    private let calendarSource = CalendarContextSource()
    private let remindersSource = RemindersContextSource()
    private let contactsSource = ContactsContextSource()
    private(set) var sourcePermissions: [SuzzmeContextSourceKind: SuzzmePermissionState] = [:]
    private var pendingConfirmation: (actionID: UUID, requestID: UUID)?
    private(set) var presentedResponse: String?
    private(set) var presentedAction: SuzzmeAction?
    var presentedActionOwner: UUID? { pendingConfirmation?.requestID }
    private var activeAssistantRequestID: UUID?
    private var voiceApproval: (sessionID: UUID, actionID: UUID, requestID: UUID)?
    private var submittedVoiceSessionID: UUID?
    private(set) var lastVoiceResponse: SuzzmeCoreResponse?
    private(set) var lastVoiceResponseRevision = UUID()
    private let itemStore: SuzzmeItemStore?
    private let memoryStore: LongTermMemoryStore?
    private(set) var briefing: DailyBriefing?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    let assistant = AssistantStateController()
    let voice: VoiceSessionController
    let invocation = InvocationCoordinator()
    var presenceState: SuzzmeAssistantState { assistant.state }
    var proactivePresenceSignal: SuzzmeProactivePresenceSignal {
        if !(proactiveSnapshot?.timeCriticalItems.isEmpty ?? true) { return .timeCritical }
        if !(proactiveSnapshot?.opportunities.isEmpty ?? true) { return .opportunity }
        if proactiveSnapshot?.briefing?.deliveryState == .ready { return .dailySummaryReady }
        return .none
    }
    private(set) var lastUnderstandingResult: SuzzmeUnderstandingResult?
    private(set) var activityItems: [SuzzmeItem] = []

    private var profileName: String {
        let value = UserDefaults.standard.string(forKey: "suzzme.profile.name")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return "Rehan" }
        return value
    }

    init(
        understandingPipeline: SuzzmeUnderstandingPipeline = SuzzmeUnderstandingPipeline(),
        itemStore: SuzzmeItemStore? = nil,
        briefing: DailyBriefing? = nil,
        memoryStore: LongTermMemoryStore? = nil,
        informationStore: InformationStore? = nil,
        proactiveStore: ProactiveIntelligenceStore? = nil,
        watchedLinkURL: URL = WatchedLinkStore.defaultURL()
    ) {
        self.understandingPipeline = understandingPipeline
        let calendarSource = self.calendarSource
        let remindersSource = self.remindersSource
        let permissions = self.permissions
        let watchedLinkStore = WatchedLinkStore(fileURL: watchedLinkURL)
        self.watchedLinkStore = watchedLinkStore
        let information = informationStore.map { store in
            InformationEngine(registry: InformationSourceRegistry([
                AppleInformationSource(id: .calendar, calendar: calendarSource, reminders: remindersSource, permissions: permissions),
                AppleInformationSource(id: .reminders, calendar: calendarSource, reminders: remindersSource, permissions: permissions),
                WatchedWebInformationSource(store: watchedLinkStore)
            ]), store: store)
        }
        self.information = information
        let proactive = proactiveStore.map {
            ProactiveIntelligenceEngine(store: $0, information: information, memoryStore: memoryStore)
        }
        self.proactive = proactive
        let settingsCoordinator = proactive.map { SuzzmeSettingsCapabilityCoordinator(proactive: $0) }
        self.core = SuzzmeCore(memoryStore: memoryStore, settingsCoordinator: settingsCoordinator, information: information, proactive: proactive)
        self.itemStore = itemStore
        self.memoryStore = memoryStore
        self.briefing = briefing
        self.voice = VoiceSessionController(assistant: assistant)
    }

    func refreshInformation(force: Bool = false) async {
        guard let information else { informationError = "Local information storage is unavailable. Your existing memories are unchanged."; return }
        guard !isRefreshingInformation else { return }
        isRefreshingInformation = true
        defer { isRefreshingInformation = false }
        do {
            try await information.refresh(force: force)
            try Task.checkCancellation()
            await inspectInformation()
            await loadWatchedLinks()
        } catch is CancellationError { }
        catch { informationError = "Updates could not be saved. Please try again." }
    }

    func inspectInformation() async {
        guard let information else { informationError = "Local information storage is unavailable."; return }
        do {
            informationEvents = try await information.retrieve()
            informationHealth = try await information.health()
            informationError = nil
        } catch { informationEvents = []; informationError = "Updates are unavailable. Please try again." }
    }

    func setInformationEnabled(_ source: InformationSourceID, enabled: Bool) async {
        guard let information else {
            informationError = "Local information storage is unavailable."
            return
        }
        do {
            try await information.setEnabled(source, enabled: enabled)
            if !enabled { await core.clearSession(); try await core.clearProactiveContent(); proactiveSnapshot = nil }
            await inspectInformation()
            if enabled { await refreshInformation(force: true) }
        } catch { informationError = "That update setting could not be saved." }
    }

    func cancelInformationIntake() async { await information?.cancel(); await watchedLinkStore.cancelAll() }

    func loadWatchedLinks() async {
        do {
            watchedLinks = try await watchedLinkStore.records()
            watchedLinkError = nil
        }
        catch { watchedLinkError = error.localizedDescription }
    }

    /// Called only after the destructive reset dialog is confirmed.
    func resetWatchedLinks() async {
        do {
            await cancelInformationIntake()
            await core.cancelProactivePreparation()
            try await information?.setEnabled(.watchedWeb, enabled: false)
            try await information?.removeAllObjects(source: .watchedWeb)
            try await core.clearProactiveContent()
            proactiveSnapshot = nil
            try await watchedLinkStore.reset()
            await loadWatchedLinks()
            await inspectInformation()
        } catch { watchedLinkError = "Watched Links could not be reset. Other unavailable stores may need recovery first." }
    }

    func addWatchedLink(name: String, url: String) async -> Bool {
        do {
            _ = try await watchedLinkStore.add(name: name, url: url)
            try await information?.setEnabled(.watchedWeb, enabled: true)
            await loadWatchedLinks()
            await refreshInformation(force: true)
            return true
        } catch {
            watchedLinkError = error.localizedDescription
            return false
        }
    }

    func setWatchedLinkEnabled(_ link: WatchedLinkRecord, enabled: Bool) async {
        do {
            await information?.cancel()
            await core.cancelProactivePreparation()
            if !enabled {
                try await information?.removeObjects(source: .watchedWeb, prefix: link.sourceIdentity + "#")
                try await core.clearProactiveContent()
                proactiveSnapshot = nil
            }
            try await watchedLinkStore.setEnabled(link.id, enabled: enabled)
            let remaining = try await watchedLinkStore.records().contains(where: \.enabled)
            if enabled || !remaining { try await information?.setEnabled(.watchedWeb, enabled: enabled) }
            await loadWatchedLinks()
            if enabled { await refreshInformation(force: true) }
        } catch { watchedLinkError = error.localizedDescription }
    }

    func refreshWatchedLink(_ link: WatchedLinkRecord) async {
        guard link.enabled else { return }
        do {
            try await watchedLinkStore.requestRefresh(link.id)
            try await information?.refresh(source: .watchedWeb, force: true, supersede: true)
            await loadWatchedLinks(); await inspectInformation()
        } catch { watchedLinkError = error.localizedDescription }
    }

    func removeWatchedLink(_ link: WatchedLinkRecord) async {
        do {
            await information?.cancel()
            await core.cancelProactivePreparation()
            try await watchedLinkStore.setEnabled(link.id, enabled: false)
            try await information?.removeObjects(source: .watchedWeb, prefix: link.sourceIdentity + "#")
            try await core.clearProactiveContent()
            proactiveSnapshot = nil
            try await watchedLinkStore.remove(link.id)
            let remaining = try await watchedLinkStore.records().contains(where: \.enabled)
            if !remaining { try await information?.setEnabled(.watchedWeb, enabled: false) }
            await loadWatchedLinks()
        } catch { watchedLinkError = error.localizedDescription }
    }

    func prepareInformationClear() async -> InformationClearReceipt? {
        guard let information else {
            informationError = "Local information storage is unavailable."
            return nil
        }
        do { return try await information.prepareClear() }
        catch { informationError = "Updates could not be prepared for clearing."; return nil }
    }

    func clearInformation(_ receipt: InformationClearReceipt) async {
        guard let information else {
            informationError = "Local information storage is unavailable."
            return
        }
        do {
            try await information.clear(receipt)
            await inspectInformation()
        } catch { informationError = "Updates changed. Review and confirm clearing again." }
    }

    func loadIfNeeded() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if let storedItems = try itemStore?.allItems() {
                activityItems = storedItems
                briefing = storedItems.isEmpty ? briefing : DailyBriefingBuilder.make(from: storedItems, name: profileName)
            } else {
                // Production does not manufacture a briefing when no grounded data exists.
                // Preview environments may still inject the Step 1 sample explicitly.
                briefing = briefing.flatMap { Calendar.current.isDateInToday($0.date) ? $0 : nil }
            }
        } catch is CancellationError {
            // A later appearance can retry a cancelled load.
        } catch {
            errorMessage = "Your day couldn’t be loaded. Please try again."
        }
    }

    func understand(text: String) async throws -> SuzzmeUnderstandingResult {
        guard privacy.classify(text).policy != .neverProcess else { throw SuzzmeCoreError.restrictedContent }
        assistant.transition(to: .understanding)
        defer { assistant.reset() }
        let fingerprints = try itemStore?.fingerprints() ?? []
        let result = try await understandingPipeline.process(text, existingFingerprints: fingerprints)
        lastUnderstandingResult = result
        return result
    }

    @discardableResult
    func saveUnderstandingResult(_ result: SuzzmeUnderstandingResult) throws -> Int {
        guard let itemStore else { throw SuzzmeIntelligenceError.persistenceUnavailable }
        let saved = try itemStore.save(result.items)
        activityItems = try itemStore.allItems()
        briefing = DailyBriefingBuilder.make(from: activityItems, name: profileName)
        return saved
    }

    func updateProfileName(_ name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        UserDefaults.standard.set(value, forKey: "suzzme.profile.name")
        guard let current = briefing else { return }
        let items = current.importantItems + current.upcomingItems + current.carriedOverItems + current.completedItems
        briefing = DailyBriefingBuilder.make(from: items, date: current.date, name: value)
    }

    func askSuzzme(_ text: String, speakResponse: Bool = false, requestID: UUID? = nil, confirmationActionID: UUID? = nil) async throws -> SuzzmeCoreResponse {
        let isReply = SuzzmeActionConfirmation.isAffirmative(text) || SuzzmeActionConfirmation.isCancellation(text)
        let previousRequestID = pendingConfirmation?.requestID ?? activeAssistantRequestID
        let approval = isReply ? pendingConfirmation : nil
        if let confirmationActionID, approval?.actionID != confirmationActionID { throw SuzzmeCapabilityError.staleRequest }
        let requestID = approval?.requestID ?? requestID ?? UUID()
        if !isReply { pendingConfirmation = nil; presentedAction = nil; presentedResponse = nil }
        activeAssistantRequestID = requestID
        if !isReply, let previousRequestID, previousRequestID != requestID { await core.cancel(requestID: previousRequestID) }
        guard activeAssistantRequestID == requestID else { throw CancellationError() }
        assistant.transition(to: .understanding)
        var completed = false
        defer {
            if activeAssistantRequestID == requestID, !completed { assistant.reset() }
        }
        let fingerprints = try itemStore?.fingerprints() ?? []
        let query = SuzzmeContextQuery.infer(from: text)
        let permissionStates = await permissionStates(for: query.sources)
        guard activeAssistantRequestID == requestID, !Task.isCancelled else { throw CancellationError() }
        sourcePermissions.merge(permissionStates) { _, new in new }
        // Local memory, confirmations and settings do not require Apple-source access.
        // Core applies this limitation only if the request reaches source-based answering.
        let unavailableContext = !query.sources.isEmpty && permissionStates.values.allSatisfy({ $0 != .authorized })
            ? unavailableMessage(for: query.sources, states: permissionStates) : nil
        let sources = contextSources(for: query) + [SuzzmeItemContextSource(items: activityItems)]
        do {
            let response = try await core.respond(to: text, sources: sources, query: query, requestID: requestID, confirmationActionID: confirmationActionID ?? approval?.actionID, existingFingerprints: fingerprints, contextUnavailableMessage: unavailableContext, profileName: profileName) { [weak self] state in
                await MainActor.run {
                    guard self?.activeAssistantRequestID == requestID else { return }
                    self?.assistant.transition(to: state)
                }
            }
            if Self.isDailyOverviewRequest(text) {
                proactiveSnapshot = try? await core.currentProactiveSnapshot()
            }
            invocation.reloadStoredPreferences()
            if proactive != nil {
                proactivePreferences = (try? await core.proactivePreferences()) ?? proactivePreferences
                if !proactivePreferences.timeCriticalEnabled { await proactiveNotifications.cancelPending() }
            }
            let capability = await understandingPipeline.capability()
            guard activeAssistantRequestID == requestID else { throw CancellationError() }
            lastUnderstandingResult = SuzzmeUnderstandingResult(
                items: response.extractedItems,
                reasons: Dictionary(uniqueKeysWithValues: response.extractedItems.map { ($0.id, "Processed locally by Suzzme.") }),
                skippedDuplicateCount: 0,
                capability: capability
            )
            completed = true
            presentedResponse = response.text
            if let action = response.action, action.status == .awaitingConfirmation {
                pendingConfirmation = (action.id, requestID)
                presentedAction = action
                assistant.transition(to: .awaitingConfirmation)
                if speakResponse && voice.speaksResponses { voice.speak(response.text, then: .awaitingConfirmation) }
            } else if speakResponse && voice.speaksResponses {
                voice.speak(response.text)
            } else {
                assistant.complete()
            }
            if response.action?.status != .awaitingConfirmation { pendingConfirmation = nil; presentedAction = nil }
            return response
        } catch is CancellationError {
            await core.cancel(requestID: requestID)
            guard activeAssistantRequestID == requestID else { throw CancellationError() }
            pendingConfirmation = nil
            presentedAction = nil
            presentedResponse = nil
            assistant.fail(message: "That request was cancelled.")
            completed = true
            throw CancellationError()
        } catch {
            guard activeAssistantRequestID == requestID else { throw CancellationError() }
            pendingConfirmation = nil
            presentedAction = nil
            presentedResponse = nil
            await core.cancel(requestID: requestID)
            guard activeAssistantRequestID == requestID else { throw CancellationError() }
            assistant.fail(message: error.localizedDescription)
            completed = true
            throw error
        }
    }

    /// Presentation adapter only. Ownership is checked before forwarding to the
    /// existing central confirmation/execution/verification path.
    func respondToPresentedAction(id: UUID, owner: UUID, confirmed: Bool) async throws {
        guard pendingConfirmation?.actionID == id, pendingConfirmation?.requestID == owner,
              presentedAction?.id == id else { throw SuzzmeCapabilityError.staleRequest }
        let response = try await askSuzzme(confirmed ? "confirm" : "cancel", confirmationActionID: id)
        lastVoiceResponse = response
        lastVoiceResponseRevision = UUID()
    }

    private func permissionStates(for kinds: Set<SuzzmeContextSourceKind>) async -> [SuzzmeContextSourceKind: SuzzmePermissionState] {
        var statuses: [SuzzmeContextSourceKind: SuzzmePermissionState] = [:]
        for kind in kinds { statuses[kind] = await permissions.status(for: kind) }
        return statuses
    }

    private func unavailableMessage(for kinds: Set<SuzzmeContextSourceKind>, states: [SuzzmeContextSourceKind: SuzzmePermissionState]) -> String {
        guard let kind = kinds.first, let state = states[kind] else { return "That source isn’t available right now." }
        let name = switch kind { case .calendar: "Calendar"; case .reminders: "Reminders"; case .contacts: "Contacts" }
        if state == .writeOnly { return "Full \(name) access is needed to verify changes. Upgrade access in Intelligence Sources." }
        return state == .notDetermined ? "Connect \(name) in Intelligence Sources to answer that." : "\(name) access is off. You can enable it in Intelligence Sources."
    }

    /// The only start path for an explicit system or in-app invocation.
    /// It gives VoiceSessionController the same request identity SuzzmeCore
    /// later receives with the final transcript.
    @discardableResult
    func invokeSuzzme() async -> Bool {
        if pendingConfirmation != nil, !voice.isListening, let previous = invocation.activeRequestID { invocation.finish(previous) }
        switch invocation.begin() {
        case .alreadyActive:
            return false
        case let .started(requestID):
            voiceApproval = pendingConfirmation.map { (requestID, $0.actionID, $0.requestID) }
            activeAssistantRequestID = requestID
            _ = voice.beginSession(id: requestID)
            await voice.start(sessionID: requestID)
            if !voice.isListening {
                invocation.finish(requestID)
                if activeAssistantRequestID == requestID { activeAssistantRequestID = nil }
                return false
            }
            return true
        }
    }

    func startVoiceSession() async {
        _ = await invokeSuzzme()
    }

    func consumeSystemVoiceInvocationIfNeeded() async {
        guard invocation.consumeSystemVoiceInvocation() else { return }
        _ = await invokeSuzzme()
    }

    func consumeSystemDailySummaryIfNeeded() async {
        guard invocation.consumeSystemDailySummary() else { return }
        await speakCurrentBriefing()
    }

    var currentInteractionID: UUID? { activeAssistantRequestID }

    func dismissInteraction(_ requestID: UUID?) async {
        guard let requestID, activeAssistantRequestID == requestID else { return }
        await cancelVoiceSession()
    }

    func cancelVoiceSession() async {
        let requestID = pendingConfirmation?.requestID ?? invocation.cancel() ?? activeAssistantRequestID
        pendingConfirmation = nil
        presentedAction = nil
        presentedResponse = nil
        voiceApproval = nil
        _ = invocation.cancel()
        voice.cancel()
        guard let requestID else { return }
        await core.cancel(requestID: requestID)
        if activeAssistantRequestID == requestID { activeAssistantRequestID = nil }
    }

    func submitVoiceTranscript(_ text: String, sessionID: UUID) async throws -> SuzzmeCoreResponse {
        guard activeAssistantRequestID == sessionID, submittedVoiceSessionID != sessionID else { throw CancellationError() }
        submittedVoiceSessionID = sessionID
        let reply = SuzzmeActionConfirmation.isAffirmative(text) || SuzzmeActionConfirmation.isCancellation(text)
        let approval = voiceApproval
        if reply {
            guard let approval, approval.sessionID == sessionID,
                  pendingConfirmation?.actionID == approval.actionID,
                  pendingConfirmation?.requestID == approval.requestID else { throw SuzzmeCapabilityError.staleRequest }
        }
        do {
            let response = try await askSuzzme(text, speakResponse: true, requestID: sessionID, confirmationActionID: reply ? approval?.actionID : nil)
            lastVoiceResponse = response
            lastVoiceResponseRevision = UUID()
            if response.action?.status != .awaitingConfirmation { invocation.finish(sessionID) }
            return response
        } catch {
            invocation.finish(sessionID)
            throw error
        }
    }

    func consumeFinalVoiceTranscript() async {
        guard let text = voice.finalTranscript, let sessionID = voice.finalizedSessionID,
              submittedVoiceSessionID != sessionID else { return }
        do { _ = try await submitVoiceTranscript(text, sessionID: sessionID) }
        catch is CancellationError { }
        catch { assistant.fail(message: error.localizedDescription) }
    }

    func refreshSourcePermissions() async {
        var statuses: [SuzzmeContextSourceKind: SuzzmePermissionState] = [:]
        for kind in SuzzmeContextSourceKind.allCases { statuses[kind] = await permissions.status(for: kind) }
        sourcePermissions = statuses
    }

    func requestSourcePermission(_ kind: SuzzmeContextSourceKind) async {
        _ = await permissions.request(kind)
        await refreshSourcePermissions()
    }

    private func contextSources(for query: SuzzmeContextQuery) -> [any ContextSource] {
        var sources: [any ContextSource] = []
        if query.sources.contains(.calendar) { sources.append(calendarSource) }
        if query.sources.contains(.reminders) { sources.append(remindersSource) }
        if query.sources.contains(.contacts) { sources.append(contactsSource) }
        return sources
    }


    func personalMemories() async throws -> [SuzzmeMemoryRecord] { try await memoryStore?.memories() ?? [] }
    func personalMemoryEnabled() async -> Bool { await memoryStore?.isEnabled() ?? false }
    func setPersonalMemoryEnabled(_ enabled: Bool) async { await memoryStore?.setEnabled(enabled) }
    func deleteMemory(_ memory: SuzzmeMemoryRecord) async throws { try await memoryStore?.delete(id: memory.id); await core.clearSession() }
    func clearPersonalMemory() async throws { try await memoryStore?.clear(); await core.clearSession() }

    func clearSessionMemory() async { await core.clearSession() }

    func loadProactiveState() async {
        guard proactive != nil else { return }
        do {
            proactivePreferences = try await core.proactivePreferences()
            proactiveSnapshot = try await core.currentProactiveSnapshot()
            proactiveError = nil
        } catch {
            proactiveError = "Your proactive intelligence settings are unavailable right now."
        }
    }

    func prepareProactiveBriefing(showActivity: Bool = false) async {
        guard proactive != nil, !isPreparingBriefing else { return }
        isPreparingBriefing = true
        proactiveError = nil
        if showActivity { assistant.transition(to: .gatheringContext) }
        defer { isPreparingBriefing = false }
        do {
            if showActivity { await refreshInformation(force: true) }
            let sources: [any ContextSource] = [calendarSource, remindersSource, SuzzmeItemContextSource(items: activityItems)]
            if showActivity { assistant.transition(to: .reasoning) }
            let snapshot = try await core.prepareProactiveBriefing(from: sources, profileName: profileName)
            proactiveSnapshot = snapshot
            proactivePreferences = try await core.proactivePreferences()
            if showActivity { assistant.complete(message: snapshot.briefing == nil ? "Nothing new needs your attention." : "Your briefing is ready.") }
            await deliverTimeCriticalItems(snapshot.timeCriticalItems)
        } catch ProactiveError.disabled {
            proactiveSnapshot = nil
            if showActivity { assistant.reset() }
        } catch is CancellationError {
            if showActivity { assistant.reset() }
        } catch {
            proactiveError = "Your briefing couldn’t be prepared. Nothing else was changed."
            if showActivity { assistant.fail(message: proactiveError) }
        }
    }

    func updateProactivePreferences(_ value: ProactivePreferences) async {
        guard proactive != nil else { return }
        do {
            let validated = value.validated()
            if validated.timeCriticalEnabled && !proactivePreferences.timeCriticalEnabled {
                _ = await proactiveNotifications.requestAuthorization()
            }
            try await core.updateProactivePreferences(validated)
            proactivePreferences = validated
            if !validated.timeCriticalEnabled { await proactiveNotifications.cancelPending() }
            if !validated.dailyBriefingEnabled { proactiveSnapshot = nil }
            await core.cancelProactivePreparation()
            if validated.dailyBriefingEnabled || validated.preparedAssistanceEnabled || validated.timeCriticalEnabled {
                await prepareProactiveBriefing()
            }
        } catch {
            proactiveError = "That proactive intelligence setting couldn’t be saved."
        }
    }

    func speakCurrentBriefing() async {
        await prepareProactiveBriefing(showActivity: true)
        guard let briefing = proactiveSnapshot?.briefing,
              briefing.deliveryState != .stale,
              !briefing.narration.isEmpty else { return }
        voice.speakBriefing(briefing.narration, id: briefing.id)
    }

    func consumeBriefingVoiceLifecycle() async {
        defer { voice.acknowledgeBriefingLifecycle() }
        do {
            if let id = voice.completedBriefingID {
                try await core.markBriefingDelivered(id: id, partial: false)
            } else if let id = voice.interruptedBriefingID {
                try await core.markBriefingDelivered(id: id, partial: true)
            }
            proactiveSnapshot = try await core.currentProactiveSnapshot()
        } catch {
            proactiveError = "Briefing progress couldn’t be saved."
        }
    }

    func cancelProactivePreparation() async {
        await core.cancelProactivePreparation()
    }

    func dismissOpportunity(_ opportunity: SuzzmeOpportunity) async {
        do {
            try await core.dismissOpportunity(id: opportunity.id)
            proactiveSnapshot = try await core.currentProactiveSnapshot()
        } catch {
            proactiveError = "That opportunity couldn’t be dismissed."
        }
    }

    /// Explicit recovery resets preferences too; never invoked automatically.
    func resetProactiveData() async {
        do {
            try await core.resetProactiveData()
            await proactiveNotifications.cancelPending()
            proactiveSnapshot = nil
            proactivePreferences = try await core.proactivePreferences()
            proactiveError = nil
        } catch { proactiveError = "Proactive data could not be reset. Please try again." }
    }

    func clearProactiveContent() async {
        do {
            try await core.clearProactiveContent()
            proactiveSnapshot = try await core.currentProactiveSnapshot()
        } catch {
            proactiveError = "Proactive intelligence data couldn’t be cleared."
        }
    }

    private func deliverTimeCriticalItems(_ items: [ProactiveBriefingItem]) async {
        guard proactivePreferences.timeCriticalEnabled else { return }
        for item in items.prefix(2) {
            do {
                if try await proactiveNotifications.deliverTimeCritical(candidateID: item.candidateID) {
                    try await core.markProactiveDelivered(candidateID: item.candidateID)
                }
            } catch {
                // System delivery is opportunistic. Keep the item eligible for a later attempt.
            }
        }
    }

    func intelligenceCapability() async -> IntelligenceCapability {
        await understandingPipeline.capability()
    }

    private static func isDailyOverviewRequest(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("what do i have today")
            || lower.contains("what matters today")
            || lower.contains("daily summary")
            || lower.contains("summarize my day")
            || lower.contains("tell me about my day")
    }

    static var preview: AppEnvironment { AppEnvironment(briefing: MockIntelligenceService.sample(), watchedLinkURL: FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmePreview-\(UUID()).json")) }
}
