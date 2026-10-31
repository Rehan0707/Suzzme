import Foundation
import FirebaseAuth
import Observation

@MainActor @Observable
final class AppEnvironment {
    // MARK: - Shared services and observable state

    private let understandingPipeline: SuzzmeUnderstandingPipeline
    private let core: SuzzmeCore
    private let information: InformationEngine?
    private let proactive: ProactiveIntelligenceEngine?
    private let watchedLinkStore: WatchedLinkStore
    private let proactiveNotifications = ProactiveNotificationDelivery()
    private let notificationNavigation = SummaryNotificationNavigation()
    private(set) var summaryNotificationsAuthorized = false
    private(set) var informationHealth: [InformationHealth] = []
    private(set) var informationEvents: [InformationEvent] = []
    private(set) var informationError: String?
    private(set) var isRefreshingInformation = false
    private(set) var proactivePreferences = ProactivePreferences()
    private(set) var proactiveSnapshot: ProactiveSnapshot?
    private(set) var proactiveError: String?
    private(set) var isPreparingBriefing = false
    private(set) var companionDeliveryPreferences: CompanionAccountPreferences?
    private(set) var companionDeliveryError: String?
    private(set) var isSavingCompanionSchedule = false
    private var isRefreshingCompanionSchedule = false
    private var storedCompanionSummary: CompanionSummary?
    /// A summary is never visible during an account transition, even before
    /// Firebase's account-change listener has cleared the old presentation.
    var companionSummary: CompanionSummary? {
        guard CompanionSummaryOwnership.permits(currentUID: CompanionSummaryStore.currentUser?.uid, ownerUID: companionAccountID) else { return nil }
        return storedCompanionSummary
    }
    private(set) var companionAccountEmail: String?
    private(set) var companionError: String?
    private(set) var isLoadingCompanionSummary = false
    private(set) var hasCheckedCompanionSummary = false
    private var companionAccountID: String?
    private var companionLoadRevision = UUID()
    #if os(macOS)
    private let companionMutations = CompanionSummaryMutationQueue()
    private var lastUrgentCompanionFacts: [String] = []
    private var lastUrgentCompanionEvaluation = Date.distantPast
    private(set) var sharesSummaryWithIPhone = false
    private(set) var lastCompanionPublishAt: Date?
    #endif
    private(set) var watchedLinks: [WatchedLinkRecord] = []
    private(set) var watchedLinkError: String?
    var watchedLinksAvailable: Bool { BoundedWatchedLinkFetcher().isAvailable }
    private let privacy = PrivacyEngine()
    private let permissions = AppleContextPermissions()
    private let calendarSource = CalendarContextSource()
    private let remindersSource = RemindersContextSource()
    private let contactsSource = ContactsContextSource()
    let gmailAccount = GmailAccountController()
    let integrations: IntegrationController
    let localKnowledge: LocalKnowledgeController
    private let composioSummarySelections: ComposioSummarySelectionStore
    func makeSharedAppWorkspace() -> SharedAppContextController {
        SharedAppContextController(pipeline: understandingPipeline)
    }
    func makeComposioWorkspace() -> ComposioWorkspace {
        ComposioWorkspace(pipeline: understandingPipeline, summarySelections: composioSummarySelections,
            onSummarySelectionsRetired: { [weak self] accountIDs in
                guard let self else { throw CancellationError() }
                try await self.composioSummarySelectionsRetired(accountIDs)
            })
    }
    private(set) var sourcePermissions: [SuzzmeContextSourceKind: SuzzmePermissionState] = [:]
    private(set) var sourcePermissionError: String?
    private var pendingConfirmation: (actionID: UUID, requestID: UUID)?
    private(set) var presentedResponse: String?
    private(set) var presentedAction: SuzzmeAction?
    var presentedActionOwner: UUID? { pendingConfirmation?.requestID }
    private var activeAssistantRequestID: UUID?
    private var activeConversationID: UUID?
    private var voiceConversationID: UUID?
    private var voiceApproval: (sessionID: UUID, actionID: UUID, requestID: UUID)?
    private var submittedVoiceSessionID: UUID?
    private var globalPushToTalkToken: UUID?
    private var transientStartOwner: UUID?
    private var explicitScreenVoiceSessionID: UUID?
    private var pendingScreenQuestion: (requestID: UUID, text: String, speak: Bool)?
    var screenConsentRequestID: UUID? { pendingScreenQuestion?.requestID }
    var screenConsentMessage: String? {
        pendingScreenQuestion == nil ? nil : "Use this screen for your question? Suzzme reads one image locally and discards it. Screen Recording permission is needed."
    }
    private(set) var presentedScreenGuidance: SpatialReference?
    private(set) var presentedScreenMetadata: ScreenContextMetadata?
    let screenPreferences = ScreenAwarenessPreferences()
    #if os(macOS)
    let whatsAppAccess = WhatsAppLocalAccess.shared
    private let screenSource = MacScreenContextSource()
    let browserBridge = MacBrowserBridgeController()
    @ObservationIgnored lazy var scheduledBriefing = ScheduledBriefingEngine { [weak self] slot in
        guard let self else { throw CancellationError() }
        return try await self.runScheduledBriefing(slot)
    }
    private(set) var scheduledBriefingNoticeID: UUID?
    func dismissScheduledBriefingNotice() { scheduledBriefingNoticeID = nil }
    #endif
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
    var presenceRequestID: UUID? { activeAssistantRequestID ?? invocation.activeRequestID }
    var proactivePresenceSignal: SuzzmeProactivePresenceSignal {
        #if os(iOS)
        if CompanionSummaryStore.currentUser != nil {
            guard let summary = companionSummary,
                  Calendar.current.isDateInToday(summary.localDay),
                  Date.now.timeIntervalSince(summary.generatedAt) < ProactiveLimits.briefingFreshness else { return .none }
            return .dailySummaryReady
        }
        #endif
        if !(proactiveSnapshot?.timeCriticalItems.isEmpty ?? true) { return .timeCritical }
        #if os(macOS)
        if scheduledBriefingNoticeID != nil, proactivePreferences.dailyBriefingEnabled,
           proactiveSnapshot?.briefing?.deliveryState == .ready { return .dailySummaryReady }
        #endif
        if !(proactiveSnapshot?.opportunities.isEmpty ?? true) { return .opportunity }
        if proactiveSnapshot?.briefing?.deliveryState == .ready { return .dailySummaryReady }
        return .none
    }
    private(set) var lastUnderstandingResult: SuzzmeUnderstandingResult?
    private(set) var activityItems: [SuzzmeItem] = []

    private var profileName: String {
        UserDefaults.standard.string(forKey: "suzzme.profile.name")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Environment setup

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
        let composioSummarySelections = ComposioSummarySelectionStore()
        self.composioSummarySelections = composioSummarySelections
        let localKnowledgeEngine = LocalKnowledgeEngine(pipeline: understandingPipeline)
        self.localKnowledge = LocalKnowledgeController(engine: localKnowledgeEngine)
        let calendarSource = self.calendarSource
        let remindersSource = self.remindersSource
        let permissions = self.permissions
        let gmailAccount = self.gmailAccount
        let integrationGateway = IntegrationGateway(google: gmailAccount, customMCP: CustomMCPClient())
        self.integrations = IntegrationController(gateway: integrationGateway)
        let watchedLinkStore = WatchedLinkStore(fileURL: watchedLinkURL)
        self.watchedLinkStore = watchedLinkStore
        let information = informationStore.map { store in
            var sources: [any InformationSource] = [
                AppleInformationSource(id: .calendar, calendar: calendarSource, reminders: remindersSource, permissions: permissions),
                AppleInformationSource(id: .reminders, calendar: calendarSource, reminders: remindersSource, permissions: permissions),
                GmailInformationSource(account: gmailAccount,
                    canSummarize: { await understandingPipeline.capability().usesFoundationModels },
                    summarize: { text in
                        let result = try await understandingPipeline.summarizeImportantEmail(text)
                        return GmailBodySummary(text: result.text, usedOnDeviceModel: result.usedOnDeviceModel)
                    }),
                UserSelectedMessageSource(),
                WatchedWebInformationSource(store: watchedLinkStore),
                IntegrationInformationSource(gateway: integrationGateway, supplementals: [
                    GoogleConnectedInformationSource(account: gmailAccount),
                    ComposioInformationSource(selections: composioSummarySelections, summarize: { facts in
                        let summary = try await understandingPipeline.summarizeGroundedFacts(facts)
                        return summary.usedOnDeviceModel ? summary.text : nil
                    })
                ])
            ]
            #if os(macOS)
            sources.append(LocalKnowledgeInformationSource(engine: localKnowledgeEngine))
            sources.append(WhatsAppLocalSource(access: WhatsAppLocalAccess.shared, understanding: understandingPipeline))
            #endif
            return InformationEngine(registry: InformationSourceRegistry(sources), store: store)
        }
        self.information = information
        let proactive = proactiveStore.map {
            ProactiveIntelligenceEngine(
                store: $0,
                information: information,
                memoryStore: memoryStore,
                localBriefingSummarizer: { facts in
                    let summary = try await understandingPipeline.summarizeGroundedFacts(facts)
                    return summary.usedOnDeviceModel ? summary.text : nil
                }
            )
        }
        self.proactive = proactive
        let settingsCoordinator = proactive.map { SuzzmeSettingsCapabilityCoordinator(proactive: $0) }
        self.core = SuzzmeCore(router: IntelligenceRouter(pipeline: understandingPipeline), memoryStore: memoryStore, settingsCoordinator: settingsCoordinator, information: information, proactive: proactive, resourceContext: integrationGateway)
        self.itemStore = itemStore
        self.memoryStore = memoryStore
        self.briefing = briefing
        self.voice = VoiceSessionController(assistant: assistant)
    }

    // MARK: - Information sources and accounts

    func refreshInformation(force: Bool = false, source: InformationSourceID? = nil) async {
        guard let information else { informationError = "Local information storage is unavailable. Your existing memories are unchanged."; return }
        guard !isRefreshingInformation else { return }
        isRefreshingInformation = true
        defer { isRefreshingInformation = false }
        do {
            try await information.refresh(source: source, force: force)
            try Task.checkCancellation()
            await inspectInformation()
            await integrations.load()
            await loadWatchedLinks()
        } catch is CancellationError { }
        catch { informationError = "Updates could not be saved. Please try again." }
    }

    func restoreGmailSignIn() async {
        await gmailAccount.restorePreviousSignIn()
    }

    func handleGmailSignInURL(_ url: URL) {
        gmailAccount.handle(url)
    }

    func disconnectGmail() async {
        let identity = gmailAccount.googleAccountIdentifier
        // Retire credentials first. A storage error must never keep access alive.
        await gmailAccount.disconnect()
        await core.clearSession()
        do {
            try await information?.setEnabled(.gmail, enabled: false)
            if let identity {
                try await information?.removeObjects(source: .gmail, prefix: GmailAccessGrant.namespace(for: identity))
                for service in GoogleSelectionPolicy.services {
                    // Account/service prefix covers all retired selection generations.
                    let prefix = GoogleSelectionPolicy.namespace(accountID: identity, service: service, generation: UUID())
                        .split(separator: ":").prefix(3).joined(separator: ":") + ":"
                    try await information?.removeObjects(source: .connectedApps, prefix: prefix)
                }
            }
            try await clearProactiveAndSharedContent(); proactiveSnapshot = nil
            await inspectInformation()
        } catch {
            informationEvents = []
            informationError = "Google access was retired. Some cached information could not be deleted; retry cleanup. It cannot authorize answers."
        }
    }

    func gmailSelectionChanged(retiredPrefix: String?) async {
        await core.clearSession()
        do {
            try await clearProactiveAndSharedContent(); proactiveSnapshot = nil
            if let retiredPrefix { try await information?.removeObjects(source: .gmail, prefix: retiredPrefix) }
            try await information?.setEnabled(.gmail, enabled: true)
            try await information?.refresh(source: .gmail, force: true)
            await inspectInformation()
        } catch { informationError = "Gmail could not be refreshed. Retry source cleanup and refresh." }
    }

    func googleSelectionsChanged(enableIntake: Bool, retiredPrefix: String? = nil) async {
        await core.clearSession()
        do {
            try await clearProactiveAndSharedContent(); proactiveSnapshot = nil
            if let retiredPrefix { try await information?.removeObjects(source: .connectedApps, prefix: retiredPrefix) }
            if enableIntake { try await information?.setEnabled(.connectedApps, enabled: true) }
            try await information?.refresh(source: .connectedApps, force: true)
            await inspectInformation()
        } catch { informationError = "Source updates could not be refreshed. Try again." }
    }

    func inspectInformation() async {
        guard let information else { informationError = "Local information storage is unavailable."; return }
        do {
            informationEvents = try await information.retrieve()
            informationHealth = try await information.health()
            informationError = nil
        } catch { informationEvents = []; informationError = "Updates are unavailable. Please try again." }
    }

    #if os(macOS)
    private(set) var whatsAppChats: [WhatsAppChatChoice] = []
    private(set) var selectedWhatsAppChats: Set<String> = []
    private(set) var whatsAppFolderConnected = false
    private(set) var whatsAppError: String?

    func loadWhatsAppChats() async {
        whatsAppFolderConnected = await whatsAppAccess.hasFolder()
        selectedWhatsAppChats = await whatsAppAccess.selectedChatIDs()
        guard whatsAppFolderConnected else { whatsAppChats = []; return }
        do {
            whatsAppChats = try await whatsAppAccess.chats()
            whatsAppError = nil
        } catch {
            whatsAppChats = []
            whatsAppError = "WhatsApp's local database could not be read. Check Full Disk Access and the selected folder."
        }
    }

    func connectWhatsApp(folder: URL) async {
        do {
            whatsAppChats = try await whatsAppAccess.connect(folder: folder)
        } catch {
            whatsAppError = "Choose WhatsApp's shared folder and allow access. Suzzme could not read ChatStorage.sqlite."
            return
        }
        whatsAppFolderConnected = true
        selectedWhatsAppChats = []
        whatsAppError = nil
        proactiveSnapshot = nil
        await core.clearSession()
        try? await clearProactiveAndSharedContent()
        do {
            try await information?.removeAllObjects(source: .whatsapp)
            try await information?.setEnabled(.whatsapp, enabled: false)
            await inspectInformation()
        } catch {
            whatsAppError = "The folder is connected, but older local summaries could not be cleared. Retry cleanup before selecting chats."
        }
    }

    func setWhatsAppChats(_ ids: Set<String>) async {
        do {
            try await whatsAppAccess.select(ids)
        } catch {
            whatsAppError = "The chat selection could not be saved. Please retry."
            return
        }
        selectedWhatsAppChats = ids
        proactiveSnapshot = nil
        await core.clearSession()
        try? await clearProactiveAndSharedContent()
        do {
            try await information?.removeAllObjects(source: .whatsapp)
            try await information?.setEnabled(.whatsapp, enabled: !ids.isEmpty)
            whatsAppError = nil
            await inspectInformation()
            if !ids.isEmpty { await refreshInformation(force: true, source: .whatsapp) }
        } catch {
            whatsAppError = "Chat access changed, but local summary cleanup could not finish. Retry the selection before using a briefing."
        }
    }

    func disconnectWhatsApp() async {
        await whatsAppAccess.disconnect()
        whatsAppChats = []
        selectedWhatsAppChats = []
        whatsAppFolderConnected = false
        proactiveSnapshot = nil
        await core.clearSession()
        try? await clearProactiveAndSharedContent()
        do {
            try await information?.setEnabled(.whatsapp, enabled: false)
            try await information?.removeAllObjects(source: .whatsapp)
            whatsAppError = nil
            await inspectInformation()
        } catch {
            whatsAppError = "WhatsApp access was removed. Some local summaries could not be deleted; retry cleanup."
        }
    }
    #endif

    func setInformationEnabled(_ source: InformationSourceID, enabled: Bool) async {
        guard let information else {
            informationError = "Local information storage is unavailable."
            return
        }
        do {
            try await information.setEnabled(source, enabled: enabled)
            if !enabled { await core.clearSession(); try await clearProactiveAndSharedContent(); proactiveSnapshot = nil }
            await inspectInformation()
            if enabled { await refreshInformation(force: true, source: source) }
        } catch { informationError = "That update setting could not be saved." }
    }

    func setIntegrationSummaryResources(_ account: IntegrationAccount, urls: [String]) async {
        guard let information else { informationError = "Local information storage is unavailable."; return }
        do {
            try await integrations.gateway.setSummaryResources(accountID: account.id, urls: urls)
            // Consent is retired before deleting derived observations. A failed
            // cleanup never restores the old permission.
            try await information.removeObjects(source: .connectedApps, prefix: IntegrationInformationSource.prefix(accountID: account.id))
            if !urls.isEmpty { try await information.setEnabled(.connectedApps, enabled: true) }
            await core.clearSession()
            try await clearProactiveAndSharedContent(); proactiveSnapshot = nil
            await integrations.load()
            await inspectInformation()
        } catch {
            await integrations.load()
            informationError = "The summary setting or its local cleanup could not finish. Review the account and try again."
        }
    }

    private func composioSummarySelectionsRetired(_ accountIDs: Set<String>) async throws {
        guard !accountIDs.isEmpty else { return }
        guard let information else { throw IntegrationFailure.storageUnavailable }
        for accountID in accountIDs {
            try await information.removeObjects(source: .connectedApps,
                prefix: ComposioInformationSource.prefix(accountID: accountID))
        }
        await core.clearSession()
        try await clearProactiveAndSharedContent(); proactiveSnapshot = nil
        if try await composioSummarySelections.hasSelections() {
            try await information.setEnabled(.connectedApps, enabled: true)
        }
        try await information.refresh(source: .connectedApps, force: true)
        await inspectInformation()
    }

    func disconnectIntegration(_ account: IntegrationAccount) async {
        await integrations.disconnect(account)
        do {
            try await information?.removeObjects(source: .connectedApps, prefix: IntegrationInformationSource.prefix(accountID: account.id))
            await core.clearSession(); try await clearProactiveAndSharedContent(); proactiveSnapshot = nil
        } catch { informationError = "Access was retired, but local summary cleanup needs another attempt." }
        await inspectInformation()
    }

    func importSelectedMessage(_ text: String) async -> SelectedMessageImportResult {
        guard let information else {
            informationError = "Local information storage is unavailable."
            return .unavailable
        }
        do {
            let result = try await information.importSelectedMessage(text)
            await inspectInformation()
            await core.clearSession()
            return result
        } catch {
            informationError = "The selected message could not be saved. Please try again."
            return .unavailable
        }
    }

    /// Prepares a reviewable summary of a user-selected chat export. Raw text
    /// stays in memory and never enters InformationStore or a network model.
    func summarizeSelectedConversation(_ text: String) async -> String? {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, content.count <= 24_000 else {
            informationError = "Choose up to 24,000 characters of conversation text to summarize."
            return nil
        }
        guard PrivacyEngine().classify(content).policy != .neverProcess else {
            informationError = "This conversation contains protected information and was not summarized."
            return nil
        }
        guard await understandingPipeline.capability().usesFoundationModels else {
            informationError = "On-device Apple Intelligence is unavailable on this device. You can still import a short excerpt."
            return nil
        }
        do {
            var remaining = content[...]
            var parts: [String] = []
            while !remaining.isEmpty {
                try Task.checkCancellation()
                let end = remaining.index(remaining.startIndex, offsetBy: min(4_000, remaining.count))
                let chunk = String(remaining[..<end])
                remaining = remaining[end...]
                let result = try await understandingPipeline.summarizeGroundedFacts(chunk)
                guard result.usedOnDeviceModel else { throw SuzzmeIntelligenceError.invalidOutput }
                parts.append(String(result.text.prefix(360)))
            }
            let combined = parts.joined(separator: "\n")
            let final: String
            if combined.count <= InformationLimits.selectedMessageCharacters {
                final = combined
            } else {
                let result = try await understandingPipeline.summarizeGroundedFacts(combined)
                guard result.usedOnDeviceModel else { throw SuzzmeIntelligenceError.invalidOutput }
                final = result.text
            }
            let summary = final.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty, summary.count <= InformationLimits.selectedMessageCharacters,
                  PrivacyEngine().classify(summary).policy != .neverProcess else {
                throw SuzzmeIntelligenceError.invalidOutput
            }
            informationError = nil
            return summary
        } catch is CancellationError {
            return nil
        } catch {
            informationError = "The on-device summary could not be prepared. Review a shorter excerpt and try again."
            return nil
        }
    }

    @discardableResult
    func removeImportedMessages() async -> Bool {
        guard let information else {
            informationError = "Local information storage is unavailable."
            return false
        }
        do {
            try await information.removeAllObjects(source: .messages)
            await core.clearSession()
            try await clearProactiveAndSharedContent()
            proactiveSnapshot = nil
            await inspectInformation()
            return informationError == nil
        } catch {
            informationError = "Imported messages could not be removed. Please try again."
            return false
        }
    }

    func cancelInformationIntake(respectingTaskCancellation: Bool = false) async {
        guard !respectingTaskCancellation || !Task.isCancelled else { return }
        await information?.cancel(respectingTaskCancellation: respectingTaskCancellation)
        guard !respectingTaskCancellation || !Task.isCancelled else { return }
        await watchedLinkStore.cancelAll(respectingTaskCancellation: respectingTaskCancellation)
    }

    // MARK: - Watched links

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
            try await watchedLinkStore.reset()
            await loadWatchedLinks()
            if !(await clearRemovedWatchedContext(prefix: nil)) {
                watchedLinkError = "Saved watched pages were removed. Some derived updates could not be cleared; they remain ineligible until storage recovers."
            }
            await inspectInformation()
        } catch { watchedLinkError = "Watched Links reset could not finish. Reload to inspect saved pages, or review local storage recovery." }
    }

    func addWatchedLink(name: String, url: String) async -> Bool {
        guard watchedLinksAvailable else { watchedLinkError = WatchedLinkError.transportRestricted.localizedDescription; return false }
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
        guard !enabled || watchedLinksAvailable else { watchedLinkError = WatchedLinkError.transportRestricted.localizedDescription; return }
        do {
            await information?.cancel()
            await core.cancelProactivePreparation()
            // Revoke the authoritative permission before dependent cleanup.
            // A failure in another store must not leave this page enabled.
            try await watchedLinkStore.setEnabled(link.id, enabled: enabled)
            await loadWatchedLinks()
            if enabled {
                try await information?.setEnabled(.watchedWeb, enabled: true)
                await refreshInformation(force: true)
            }
            else if !(await clearRemovedWatchedContext(prefix: link.sourceIdentity + "#")) {
                watchedLinkError = "Checking is off. Some derived updates could not be cleared; they remain ineligible until storage recovers."
            }
        } catch { watchedLinkError = error.localizedDescription }
    }

    func refreshWatchedLink(_ link: WatchedLinkRecord) async {
        guard watchedLinksAvailable, link.permitsFetching else { return }
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
            // Saved-link deletion is independent of derived-store availability.
            try await watchedLinkStore.remove(link.id)
            await loadWatchedLinks()
            if !(await clearRemovedWatchedContext(prefix: link.sourceIdentity + "#")) {
                watchedLinkError = "The saved page was removed. Some derived updates could not be cleared; they remain ineligible until storage recovers."
            }
        } catch { watchedLinkError = error.localizedDescription }
    }

    private func clearRemovedWatchedContext(prefix: String?) async -> Bool {
        var complete = true
        do {
            if let prefix { try await information?.removeObjects(source: .watchedWeb, prefix: prefix) }
            else { try await information?.removeAllObjects(source: .watchedWeb) }
        } catch { complete = false }
        proactiveSnapshot = nil
        do { try await clearProactiveAndSharedContent() } catch { complete = false }
        do {
            let remaining = try await watchedLinkStore.records().contains(where: \.permitsFetching)
            if !remaining { try await information?.setEnabled(.watchedWeb, enabled: false) }
        } catch { complete = false }
        return complete
    }

    // MARK: - Information cleanup

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

    // MARK: - Saved items and extraction

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
        let requestOwner = activeAssistantRequestID
        let voiceOwner = voice.sessionID
        let presentsActivity = [.idle, .success, .error].contains(assistant.state)
            && ownsSummaryPresentation(requestID: requestOwner, voiceSessionID: voiceOwner)
            && !voice.isSpeaking && !voice.isPreparingSpeech
        if presentsActivity { assistant.transition(to: .understanding) }
        let activityRevision = assistant.revision
        defer {
            // A newer interaction can reuse a confirmation request ID. Only
            // this exact presentation may be reset when extraction finishes.
            if presentsActivity, assistant.revision == activityRevision,
               ownsSummaryPresentation(requestID: requestOwner, voiceSessionID: voiceOwner) {
                assistant.reset()
            }
        }
        let fingerprints = try itemStore?.fingerprints() ?? []
        let result = try await understandingPipeline.process(text, existingFingerprints: fingerprints)
        try Task.checkCancellation()
        guard activeAssistantRequestID == requestOwner, voice.sessionID == voiceOwner,
              assistant.revision == activityRevision else { throw CancellationError() }
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

    // MARK: - Assistant questions and action confirmation

    func askSuzzme(_ text: String, speakResponse: Bool = false, requestID: UUID? = nil, confirmationActionID: UUID? = nil, allowScreenContext: Bool = false, customMCPRead: CustomMCPReadRequest? = nil, conversationID: UUID? = nil) async throws -> SuzzmeCoreResponse {
        #if os(iOS)
        let owner = requestID ?? UUID()
        activeAssistantRequestID = owner
        voice.stopSpeech()
        await loadCompanionSummary()
        guard activeAssistantRequestID == owner, !Task.isCancelled else { throw CancellationError() }
        let answer: String
        let count: Int
        if Self.isDailyOverviewRequest(text), let uid = CompanionSummaryStore.currentUser?.uid,
           companionAccountID == uid, let summary = companionSummary, summary.isValid {
            answer = summary.narration
            count = summary.items.count
        } else {
            answer = "This iPhone receives and reads the summary prepared by your Mac. Open Today to check your shared summary."
            count = 0
        }
        presentedResponse = answer
        assistant.complete(message: answer)
        if speakResponse { voice.speak(answer) }
        return .init(text: answer, route: .localContext, contextCount: count, extractedItems: [])
        #else
        let isReply = SuzzmeActionConfirmation.isAffirmative(text) || SuzzmeActionConfirmation.isCancellation(text)
        let continuesConversation = activeConversationID == conversationID
        let replacesInteraction = !isReply || !continuesConversation
        let previousRequestIDs = Set([pendingConfirmation?.requestID, activeAssistantRequestID].compactMap { $0 })
        let approval = isReply && continuesConversation ? pendingConfirmation : nil
        if let confirmationActionID, approval?.actionID != confirmationActionID { throw SuzzmeCapabilityError.staleRequest }
        // Retire owned narration before a typed reply or replacement can finish.
        // Otherwise its queued didFinish can restore an old confirmation phase.
        voice.stopSpeech()
        let requestID = approval?.requestID ?? requestID ?? UUID()
        if replacesInteraction {
            pendingConfirmation = nil; presentedAction = nil; presentedResponse = nil
            pendingScreenQuestion = nil; presentedScreenGuidance = nil; presentedScreenMetadata = nil
        }
        activeAssistantRequestID = requestID
        activeConversationID = conversationID
        if replacesInteraction {
            for previousRequestID in previousRequestIDs where previousRequestID != requestID {
                #if os(macOS)
                await screenSource.cancel(requestID: previousRequestID)
                #endif
                await core.cancel(requestID: previousRequestID)
                guard activeAssistantRequestID == requestID, !Task.isCancelled else { throw CancellationError() }
            }
        }
        guard activeAssistantRequestID == requestID else { throw CancellationError() }
        #if os(macOS)
        let usesScreen = ScreenContextPolicy.isScreenQuestion(text)
            || (allowScreenContext && !ScreenContextPolicy.isPersonalDayQuestion(text))
        let screenAllowed = ScreenContextPolicy.mayCapture(text, mode: screenPreferences.mode,
            isVoice: speakResponse, explicitlyAllowed: allowScreenContext)
        if usesScreen, screenPreferences.mode != .off || allowScreenContext,
           !screenAllowed || !MacScreenContextSource.isAuthorized {
            pendingScreenQuestion = (requestID, String(text.prefix(2_000)), speakResponse)
            let message = screenConsentMessage ?? "Allow this screen for this question?"
            presentedResponse = message
            assistant.transition(to: .awaitingConfirmation)
            if speakResponse && voice.speaksResponses { voice.speak(message, then: .awaitingConfirmation) }
            return .init(text: message, route: .localContext, contextCount: 0, extractedItems: [])
        }
        let requestScreenSource: (any ScreenContextSource)? = usesScreen && screenAllowed ? screenSource : nil
        #else
        let requestScreenSource: (any ScreenContextSource)? = nil
        #endif
        let isScreenResponse = requestScreenSource != nil || ScreenContextPolicy.isScreenQuestion(text)
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
            let resource: SuzzmeResourceContext?
            if let customMCPRead {
                assistant.transition(to: .gatheringContext)
                resource = try await integrations.gateway.readCustomMCP(accountID: customMCPRead.accountID, tool: customMCPRead.tool, arguments: customMCPRead.arguments, requestID: requestID)
                guard activeAssistantRequestID == requestID, !Task.isCancelled else { throw CancellationError() }
            } else { resource = nil }
            let response = try await core.respond(to: text, sources: sources, query: query, requestID: requestID, confirmationActionID: confirmationActionID ?? approval?.actionID, existingFingerprints: fingerprints, contextUnavailableMessage: unavailableContext, profileName: profileName, screenSource: requestScreenSource, visualGuidance: screenPreferences.visualGuidance, explicitResource: resource, conversationID: conversationID) { [weak self] state in
                await MainActor.run {
                    guard self?.activeAssistantRequestID == requestID else { return }
                    self?.assistant.transition(to: state)
                }
            }
            // Provider failures retire gateway authority. Reflect that current
            // state in any already-open Integrations window, too.
            await integrations.load()
            guard activeAssistantRequestID == requestID, !Task.isCancelled else { throw CancellationError() }
            if !isScreenResponse, Self.isDailyOverviewRequest(text) {
                proactiveSnapshot = try? await core.currentProactiveSnapshot()
            }
            invocation.reloadStoredPreferences()
            if !isScreenResponse, proactive != nil {
                proactivePreferences = (try? await core.proactivePreferences()) ?? proactivePreferences
                try await reconcileSummaryDelivery()
                if !proactivePreferences.timeCriticalEnabled { await proactiveNotifications.cancelPending() }
            }
            let capability = await understandingPipeline.capability()
            guard activeAssistantRequestID == requestID else { throw CancellationError() }
            lastUnderstandingResult = SuzzmeUnderstandingResult(
                items: response.extractedItems,
                reasons: Dictionary(uniqueKeysWithValues: response.extractedItems.map { ($0.id, "Processed locally by Suzzme.") }),
                skippedDuplicateCount: 0,
                capability: capability,
                usedOnDeviceModel: response.route == .onDeviceIntelligence
            )
            completed = true
            presentedResponse = response.text
            presentedScreenGuidance = response.spatialReference
            presentedScreenMetadata = response.screenMetadata
            if let action = response.action, action.status == .awaitingConfirmation {
                pendingConfirmation = (action.id, requestID)
                presentedAction = action
                assistant.transition(to: .awaitingConfirmation)
                if speakResponse && voice.speaksResponses { voice.speak(response.text, then: .awaitingConfirmation) }
            } else if speakResponse && voice.speaksResponses {
                voice.speak(response.text)
            } else {
                assistant.complete(after: requestScreenSource == nil ? .seconds(1.5) : .seconds(4))
            }
            if response.action?.status != .awaitingConfirmation { pendingConfirmation = nil; presentedAction = nil }
            return response
        } catch is CancellationError {
            await core.cancel(requestID: requestID)
            guard activeAssistantRequestID == requestID else { throw CancellationError() }
            pendingConfirmation = nil
            presentedAction = nil
            presentedResponse = nil
            presentedScreenGuidance = nil; presentedScreenMetadata = nil
            assistant.fail(message: "That request was cancelled.")
            completed = true
            throw CancellationError()
        } catch {
            guard activeAssistantRequestID == requestID else { throw CancellationError() }
            pendingConfirmation = nil
            presentedAction = nil
            presentedResponse = nil
            presentedScreenGuidance = nil; presentedScreenMetadata = nil
            await core.cancel(requestID: requestID)
            guard activeAssistantRequestID == requestID else { throw CancellationError() }
            assistant.fail(message: error.localizedDescription)
            completed = true
            throw error
        }
        #endif
    }

    /// Presentation adapter only. Ownership is checked before forwarding to the
    /// existing central confirmation/execution/verification path.
    func respondToPresentedAction(id: UUID, owner: UUID, confirmed: Bool) async throws {
        guard pendingConfirmation?.actionID == id, pendingConfirmation?.requestID == owner,
              presentedAction?.id == id else { throw SuzzmeCapabilityError.staleRequest }
        let response = try await askSuzzme(confirmed ? "confirm" : "cancel", confirmationActionID: id, conversationID: activeConversationID)
        guard activeAssistantRequestID == owner, !Task.isCancelled else { throw CancellationError() }
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
    // MARK: - Voice invocation and screen consent

    func invokeSuzzme(requestID: UUID = UUID(), conversationID: UUID? = nil, waitsForRelease: Bool = false) async -> Bool {
        #if os(iOS)
        await loadCompanionSummary()
        guard !Task.isCancelled else { return false }
        readCompanionSummaryAloud()
        return companionSummary != nil && voice.speaksResponses
        #else
        guard !Task.isCancelled else { return false }
        retireFailedVoiceInvocationIfNeeded()
        if pendingConfirmation != nil, !voice.isListening, let previous = invocation.activeRequestID { invocation.finish(previous) }
        switch invocation.begin(requestID: requestID) {
        case .alreadyActive:
            return false
        case let .started(requestID):
            let scope = conversationID ?? (pendingConfirmation == nil ? nil : activeConversationID)
            voiceConversationID = scope
            voiceApproval = activeConversationID == scope ? pendingConfirmation.map { (requestID, $0.actionID, $0.requestID) } : nil
            activeAssistantRequestID = requestID
            _ = voice.beginSession(id: requestID)
            await voice.start(sessionID: requestID, waitsForRelease: waitsForRelease)
            if !voice.isListening {
                invocation.finish(requestID)
                if activeAssistantRequestID == requestID { activeAssistantRequestID = nil }
                return false
            }
            return true
        }
        #endif
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
    var currentConversationID: UUID? {
        if let owner = activeAssistantRequestID, owner == voice.sessionID { return voiceConversationID }
        return activeConversationID
    }

    /// Physical key ownership is independent from an async microphone prompt.
    /// A released/superseded chord may never start capture when that prompt returns.
    func beginGlobalPushToTalk(token: UUID) async {
        guard !Task.isCancelled else { return }
        globalPushToTalkToken = token
        await beginTransientVoice(token: token, waitsForRelease: true, allowsScreen: false)
    }

    func endGlobalPushToTalk(token: UUID) async {
        guard globalPushToTalkToken == token else { return }
        globalPushToTalkToken = nil
        if transientStartOwner == token { transientStartOwner = nil }
        guard activeAssistantRequestID == token, voice.sessionID == token else { return }
        voice.stop()
        if !voice.isFinalizing && voice.finalizedSessionID == nil {
            presentedResponse = voice.message
            invocation.finish(token)
        }
    }

    func invokeTransientVoice() async {
        await beginTransientVoice(token: UUID(), waitsForRelease: false, allowsScreen: false)
    }

    func askAboutCurrentScreen() async {
        await beginTransientVoice(token: UUID(), waitsForRelease: false, allowsScreen: true)
    }

    private func beginTransientVoice(token: UUID, waitsForRelease: Bool, allowsScreen: Bool) async {
        guard !Task.isCancelled else { return }
        transientStartOwner = token
        defer { if transientStartOwner == token { transientStartOwner = nil } }
        let previous = activeAssistantRequestID
        let approval = pendingConfirmation
        voiceConversationID = approval == nil ? nil : activeConversationID
        // Barge-in stops speech through the existing controller. Pending action
        // confirmation remains owned by its original request, never this chord.
        _ = invocation.cancel()
        voice.cancel()
        activeAssistantRequestID = token
        pendingScreenQuestion = nil
        presentedResponse = nil; presentedScreenGuidance = nil; presentedScreenMetadata = nil
        guard case .started = invocation.begin(requestID: token) else { return }
        voiceApproval = approval.map { (token, $0.actionID, $0.requestID) }
        explicitScreenVoiceSessionID = allowsScreen ? token : nil
        _ = voice.beginSession(id: token)
        // Publish an owned wake before awaiting old actor cleanup. This is
        // preparation, never a claim that the microphone is already recording.
        assistant.transition(to: .understanding, message: "Getting ready to listen…")
        presentedResponse = "Getting ready to listen…"
        #if os(macOS)
        if let previous, previous != token { await screenSource.cancel(requestID: previous) }
        #endif
        if approval == nil, let previous, previous != token { await core.cancel(requestID: previous) }
        guard activeAssistantRequestID == token, transientStartOwner == token,
              (!waitsForRelease || globalPushToTalkToken == token), !Task.isCancelled else { return }
        if voice.microphonePermission == .notDetermined || voice.speechPermission == .notDetermined {
            // The app-owned Presence is visible before any contextual OS prompt.
            presentedResponse = "To talk, Suzzme needs microphone and Speech Recognition access. Speech is processed on this device."
            await Task.yield()
        }
        guard activeAssistantRequestID == token, transientStartOwner == token,
              (!waitsForRelease || globalPushToTalkToken == token), !Task.isCancelled else { return }
        await voice.start(sessionID: token, waitsForRelease: waitsForRelease)
        guard activeAssistantRequestID == token else { return }
        if voice.isListening { presentedResponse = nil }
        if !voice.isListening && !voice.isFinalizing && voice.finalizedSessionID == nil {
            presentedResponse = voice.message
            invocation.finish(token)
        }
    }

    func cancelGlobalInteraction() async {
        integrations.clearBrowserHandoff()
        await cancelVoiceSession()
    }

    func invalidateScreenContext() async {
        presentedScreenGuidance = nil; presentedScreenMetadata = nil
        #if os(macOS)
        await screenSource.cancel()
        #endif
    }

    func invalidateScreenContext(requestID: UUID) async {
        guard activeAssistantRequestID == requestID else { return }
        presentedScreenGuidance = nil; presentedScreenMetadata = nil
        #if os(macOS)
        await screenSource.cancel(requestID: requestID)
        #endif
    }

    func respondToScreenConsent(requestID: UUID, granted: Bool) async {
        guard let pending = pendingScreenQuestion, pending.requestID == requestID,
              activeAssistantRequestID == requestID else { return }
        voice.stopSpeech()
        pendingScreenQuestion = nil
        guard granted else {
            invocation.finish(requestID)
            presentedResponse = "I didn’t capture your screen."
            lastVoiceResponse = .init(text: "I didn’t capture your screen.", route: .localContext, contextCount: 0, extractedItems: [])
            lastVoiceResponseRevision = UUID()
            assistant.complete()
            return
        }
        #if os(macOS)
        if !MacScreenContextSource.isAuthorized { _ = MacScreenContextSource.requestAuthorization() }
        guard activeAssistantRequestID == requestID else { return }
        guard MacScreenContextSource.isAuthorized else {
            invocation.finish(requestID)
            presentedResponse = "Screen Recording access is needed for this question. Voice and your other sources still work. Enable Suzzme in System Settings, then ask again."
            lastVoiceResponse = .init(text: presentedResponse ?? "Screen Recording access is needed.", route: .localContext, contextCount: 0, extractedItems: [])
            lastVoiceResponseRevision = UUID()
            assistant.fail(message: presentedResponse)
            return
        }
        do {
            let response = try await askSuzzme(pending.text, speakResponse: pending.speak,
                requestID: requestID, allowScreenContext: true, conversationID: activeConversationID)
            guard activeAssistantRequestID == requestID, !Task.isCancelled else { return }
            lastVoiceResponse = response; lastVoiceResponseRevision = UUID()
        } catch is CancellationError { }
        catch {
            guard activeAssistantRequestID == requestID else { return }
            assistant.fail(message: error.localizedDescription)
        }
        invocation.finish(requestID)
        #endif
    }

    func dismissInteraction(_ requestID: UUID?) async {
        guard let requestID, activeAssistantRequestID == requestID else { return }
        await cancelVoiceSession()
    }

    func cancelVoiceSession() async {
        let currentRequestID = activeAssistantRequestID
        let approvalRequestID = pendingConfirmation?.requestID
        let invocationRequestID = invocation.cancel()
        // Retire UI ownership synchronously, before any actor hop. A late
        // answer or final transcript must not revive an escaped interaction.
        activeAssistantRequestID = nil
        activeConversationID = nil
        voiceConversationID = nil
        pendingConfirmation = nil
        presentedAction = nil
        presentedResponse = nil
        voiceApproval = nil
        globalPushToTalkToken = nil; transientStartOwner = nil; explicitScreenVoiceSessionID = nil
        pendingScreenQuestion = nil; presentedScreenGuidance = nil; presentedScreenMetadata = nil
        _ = invocation.cancel()
        voice.cancel()
        #if os(macOS)
        if let currentRequestID { await screenSource.cancel(requestID: currentRequestID) }
        #endif
        let owners = Set([currentRequestID, approvalRequestID, invocationRequestID].compactMap { $0 })
        for owner in owners { await core.cancel(requestID: owner) }
    }

    func retireFailedVoiceInvocationIfNeeded() {
        guard [.idle, .error].contains(assistant.state), !voice.isListening,
              !voice.isFinalizing, voice.finalizedSessionID == nil,
              globalPushToTalkToken == nil, transientStartOwner == nil,
              let requestID = invocation.activeRequestID else { return }
        invocation.finish(requestID)
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
            let explicitlyAllowed = explicitScreenVoiceSessionID == sessionID
            explicitScreenVoiceSessionID = nil
            let response = try await askSuzzme(text, speakResponse: true, requestID: sessionID, confirmationActionID: reply ? approval?.actionID : nil, allowScreenContext: explicitlyAllowed, conversationID: voiceConversationID)
            let responseOwner = reply ? approval?.requestID : sessionID
            guard activeAssistantRequestID == responseOwner, voice.sessionID == sessionID,
                  !Task.isCancelled else { throw CancellationError() }
            lastVoiceResponse = response
            lastVoiceResponseRevision = UUID()
            if response.action?.status != .awaitingConfirmation, pendingScreenQuestion == nil { invocation.finish(sessionID) }
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
        catch {
            guard activeAssistantRequestID == sessionID else { return }
            assistant.fail(message: error.localizedDescription)
        }
    }

    // MARK: - Source permissions

    func refreshSourcePermissions() async {
        var statuses: [SuzzmeContextSourceKind: SuzzmePermissionState] = [:]
        for kind in SuzzmeContextSourceKind.allCases { statuses[kind] = await permissions.status(for: kind) }
        sourcePermissions = statuses
    }

    func requestSourcePermission(_ kind: SuzzmeContextSourceKind) async {
        sourcePermissionError = nil
        do { _ = try await permissions.request(kind) }
        catch {
            sourcePermissionError = "\(kind.title) access couldn’t be requested. Please try again, or review Suzzme’s access in system settings."
        }
        await refreshSourcePermissions()
        guard sourcePermissions[kind] == .authorized else { return }
        // Access and recent-update intake remain separate opt-ins. Contacts
        // have no intake source; granting access must not refresh other sources.
        guard let source = InformationSourceID(rawValue: kind.rawValue) else { return }
        // A permission sheet may not change the main scene's phase on Mac.
        // Refresh only this source if its recent updates were already enabled.
        await refreshInformation(force: true, source: source)
        await prepareProactiveBriefing()
    }

    private func contextSources(for query: SuzzmeContextQuery) -> [any ContextSource] {
        var sources: [any ContextSource] = []
        if query.sources.contains(.calendar) { sources.append(calendarSource) }
        if query.sources.contains(.reminders) { sources.append(remindersSource) }
        if query.sources.contains(.contacts) { sources.append(contactsSource) }
        return sources
    }


    // MARK: - Personal memory

    func personalMemories() async throws -> [SuzzmeMemoryRecord] { try await memoryStore?.memories() ?? [] }
    func personalMemoryEnabled() async -> Bool { await memoryStore?.isEnabled() ?? false }
    func setPersonalMemoryEnabled(_ enabled: Bool) async { await memoryStore?.setEnabled(enabled) }
    func deleteMemory(_ memory: SuzzmeMemoryRecord) async throws { try await memoryStore?.delete(id: memory.id); await core.clearSession() }
    func clearPersonalMemory() async throws { try await memoryStore?.clear(); await core.clearSession() }

    // MARK: - Proactive summaries and notifications

    #if os(macOS)
    /// Scheduled work uses the same permitted sources and summary coordinator.
    /// It never enters the interactive request, action, screen or voice paths.
    func runScheduledBriefing(_ slot: ScheduledBriefingSlot) async throws -> ScheduledBriefingOutput {
        guard let information, proactive != nil, let itemStore else { throw ScheduledBriefingRunError.unavailable }
        guard !isRefreshingInformation, !isPreparingBriefing, !isLoading else { throw ScheduledBriefingRunError.busy }
        let summaryOwnerUID = CompanionSummaryStore.currentUser?.uid
        let requestOwner = activeAssistantRequestID
        let voiceOwner = voice.sessionID
        try requireBackgroundSummaryOwnership(requestID: requestOwner, voiceSessionID: voiceOwner)
        isRefreshingInformation = true
        isPreparingBriefing = true
        defer { isRefreshingInformation = false; isPreparingBriefing = false }

        let preferences = try await core.proactivePreferences()
        guard preferences.dailyBriefingEnabled else { throw ScheduledBriefingRunError.disabled }
        try requireBackgroundSummaryOwnership(requestID: requestOwner, voiceSessionID: voiceOwner)
        activityItems = try itemStore.allItems()
        // InformationEngine checks enablement and authorization again before
        // fetching and committing. This does not request any new permissions.
        try await information.refresh(force: true, briefingCutoff: slot.scheduledAt, briefingCalendar: slot.schedule.calendar)
        try requireBackgroundSummaryOwnership(requestID: requestOwner, voiceSessionID: voiceOwner)
        let sources: [any ContextSource] = [calendarSource, remindersSource, SuzzmeItemContextSource(items: activityItems)]
        _ = try await core.prepareProactiveBriefing(from: sources, profileName: profileName, rememberInSession: false, calendar: slot.schedule.calendar, summaryCutoff: slot.scheduledAt)
        try requireBackgroundSummaryOwnership(requestID: requestOwner, voiceSessionID: voiceOwner)
        let health = try await information.health()
        let currentPreferences = try await core.proactivePreferences()
        // Permission revalidation is the last suspension before publication.
        // Recent source rows keep their own inspection/revalidation boundary.
        let snapshot = try await core.currentProactiveSnapshot()
        try requireBackgroundSummaryOwnership(requestID: requestOwner, voiceSessionID: voiceOwner)
        guard currentPreferences.dailyBriefingEnabled else { throw ScheduledBriefingRunError.disabled }
        guard currentPreferences.briefingHour == slot.schedule.hour,
              currentPreferences.briefingMinute == slot.schedule.minute else { throw CancellationError() }
        proactiveSnapshot = snapshot
        proactivePreferences = currentPreferences
        informationHealth = health
        proactiveError = nil
        await publishCompanionSummary(snapshot, ownerUID: summaryOwnerUID)
        scheduledBriefingNoticeID = snapshot.briefing == nil ? nil : UUID()
        let contributingSources = Set((snapshot.dailyContext?.activeEntries ?? []).map(\.source))
        let limitations = max(snapshot.dailyContext?.sourceLimitations.count ?? 0,
                             health.filter { $0.enabled && $0.state != .healthy }.count)
        return ScheduledBriefingOutput(generatedAt: snapshot.generatedAt, briefingID: snapshot.briefing?.id,
            itemCount: snapshot.briefing?.items.count ?? 0, sourceCount: contributingSources.count,
            limitationCount: limitations)
    }

    private func requireBackgroundSummaryOwnership(requestID: UUID?, voiceSessionID: UUID) throws {
        try Task.checkCancellation()
        guard activeAssistantRequestID == requestID, voice.sessionID == voiceSessionID,
              [.idle, .success, .error].contains(assistant.state),
              pendingConfirmation == nil, pendingScreenQuestion == nil,
              transientStartOwner == nil, globalPushToTalkToken == nil,
              !voice.isListening, !voice.isFinalizing, !voice.isSpeaking, !voice.isPreparingSpeech else {
            throw ScheduledBriefingRunError.busy
        }
    }
    #endif

    func loadProactiveState() async {
        guard proactive != nil else { return }
        #if os(macOS)
        if let uid = CompanionSummaryStore.currentUser?.uid, CompanionSummarySharing.needsRemoval(for: uid) {
            await removeSharedCompanionSummary()
        }
        #endif
        do {
            proactivePreferences = try await core.proactivePreferences()
            proactiveSnapshot = try await core.currentProactiveSnapshot()
            try await reconcileSummaryDelivery()
            proactiveError = nil
        } catch {
            // Failed authority revalidation must withhold previously rendered
            // derived facts, while keeping their saved source history intact.
            proactiveSnapshot = nil
            proactiveError = "Your proactive intelligence settings are unavailable right now."
        }
    }

    func savedDailyBriefings() async throws -> [ProactiveBriefing] {
        guard let proactive else { return [] }
        return try await proactive.savedBriefings()
    }

    func prepareProactiveBriefing(showActivity: Bool = false, background: Bool = false) async {
        #if os(iOS)
        await loadCompanionSummary()
        return
        #else
        guard proactive != nil, !isPreparingBriefing else { return }
        #if os(macOS)
        let summaryOwnerUID = CompanionSummaryStore.currentUser?.uid
        #endif
        let presentationOwner = activeAssistantRequestID
        let voiceOwner = voice.sessionID
        isPreparingBriefing = true
        proactiveError = nil
        if showActivity, !Task.isCancelled, ownsSummaryPresentation(requestID: presentationOwner, voiceSessionID: voiceOwner) { assistant.transition(to: .gatheringContext) }
        defer { isPreparingBriefing = false }
        do {
            if showActivity { await refreshInformation(force: true) }
            try Task.checkCancellation()
            let sources: [any ContextSource] = [calendarSource, remindersSource, SuzzmeItemContextSource(items: activityItems)]
            if showActivity, ownsSummaryPresentation(requestID: presentationOwner, voiceSessionID: voiceOwner) { assistant.transition(to: .reasoning) }
            let snapshot = try await core.prepareProactiveBriefing(from: sources, profileName: profileName, rememberInSession: !background)
            try Task.checkCancellation()
            if background { try requireBackgroundSummaryOwnership(requestID: presentationOwner, voiceSessionID: voiceOwner) }
            proactiveSnapshot = snapshot
            proactivePreferences = try await core.proactivePreferences()
            if background { try requireBackgroundSummaryOwnership(requestID: presentationOwner, voiceSessionID: voiceOwner) }
            #if os(macOS)
            await publishCompanionSummary(snapshot, ownerUID: summaryOwnerUID)
            #endif
            if showActivity, !Task.isCancelled, ownsSummaryPresentation(requestID: presentationOwner, voiceSessionID: voiceOwner) { assistant.complete(message: snapshot.briefing == nil ? "Nothing new needs your attention." : "Your briefing is ready.") }
            await deliverTimeCriticalItems(snapshot.timeCriticalItems)
        } catch ProactiveError.disabled {
            proactiveSnapshot = nil
            if showActivity, ownsSummaryPresentation(requestID: presentationOwner, voiceSessionID: voiceOwner) { assistant.reset() }
        } catch is CancellationError {
            proactiveSnapshot = nil
            if showActivity, ownsSummaryPresentation(requestID: presentationOwner, voiceSessionID: voiceOwner) { assistant.reset() }
        } catch {
            proactiveSnapshot = nil
            proactiveError = "Your briefing couldn’t be prepared. Nothing else was changed."
            if showActivity, ownsSummaryPresentation(requestID: presentationOwner, voiceSessionID: voiceOwner) { assistant.fail(message: proactiveError) }
        }
        #endif
    }

    private func ownsSummaryPresentation(requestID: UUID?, voiceSessionID: UUID) -> Bool {
        activeAssistantRequestID == requestID && voice.sessionID == voiceSessionID
            && voice.canStartSpeech && transientStartOwner == nil && globalPushToTalkToken == nil
            && assistant.state != .awaitingConfirmation
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
            await saveCompanionSchedule(from: validated)
            try await reconcileSummaryDelivery()
            if !validated.timeCriticalEnabled { await proactiveNotifications.cancelPending() }
            if !validated.dailyBriefingEnabled {
                proactiveSnapshot = nil
                #if os(macOS)
                dismissScheduledBriefingNotice()
                if !validated.timeCriticalEnabled {
                    if let uid = CompanionSummaryStore.currentUser?.uid {
                        CompanionSummarySharing.setEnabled(false, for: uid)
                        sharesSummaryWithIPhone = false
                    }
                    await removeSharedCompanionSummary()
                }
                #endif
            }
            await core.cancelProactivePreparation()
            if validated.dailyBriefingEnabled || validated.preparedAssistanceEnabled || validated.timeCriticalEnabled {
                await prepareProactiveBriefing()
            }
        } catch {
            proactiveError = "That proactive intelligence setting couldn’t be saved."
        }
    }

    private func reconcileSummaryDelivery() async throws {
        try await proactiveNotifications.reconcileSummary(proactivePreferences)
        summaryNotificationsAuthorized = await proactiveNotifications.summaryNotificationsAuthorized
    }

    func requestSummaryNotificationAuthorization() async {
        _ = await proactiveNotifications.requestAuthorization()
        do { try await reconcileSummaryDelivery() }
        catch { proactiveError = "Daily Summary notifications couldn’t be scheduled. You can still open your summary." }
    }

    func speakCurrentBriefing() async {
        #if os(iOS)
        await loadCompanionSummary()
        readCompanionSummaryAloud()
        #else
        guard !isPreparingBriefing else { return }
        let owner = activeAssistantRequestID
        let voiceOwner = voice.sessionID
        guard !Task.isCancelled, ownsSummaryPresentation(requestID: owner, voiceSessionID: voiceOwner) else { return }
        await prepareProactiveBriefing(showActivity: true)
        guard !Task.isCancelled, ownsSummaryPresentation(requestID: owner, voiceSessionID: voiceOwner),
              let briefing = proactiveSnapshot?.briefing,
              briefing.deliveryState != .stale,
              !briefing.narration.isEmpty else { return }
        voice.speakBriefing(briefing.narration, id: briefing.id)
        #endif
    }

    func consumeBriefingVoiceLifecycle() async {
        #if os(iOS)
        voice.acknowledgeBriefingLifecycle()
        return
        #else
        defer { voice.acknowledgeBriefingLifecycle() }
        do {
            if let id = voice.completedBriefingID {
                try await core.markBriefingDelivered(id: id, partial: false)
            } else if let id = voice.interruptedBriefingID {
                try await core.markBriefingDelivered(id: id, partial: true)
            }
            proactiveSnapshot = try await core.currentProactiveSnapshot()
        } catch {
            proactiveSnapshot = nil
            proactiveError = "Briefing progress couldn’t be saved."
        }
        #endif
    }

    func cancelProactivePreparation(respectingTaskCancellation: Bool = false) async {
        guard !respectingTaskCancellation || !Task.isCancelled else { return }
        await core.cancelProactivePreparation(respectingTaskCancellation: respectingTaskCancellation)
    }

    func dismissOpportunity(_ opportunity: SuzzmeOpportunity) async {
        do {
            try await core.dismissOpportunity(id: opportunity.id)
            proactiveSnapshot = try await core.currentProactiveSnapshot()
        } catch {
            proactiveSnapshot = nil
            proactiveError = "That opportunity couldn’t be dismissed."
        }
    }

    /// Explicit recovery resets preferences too; never invoked automatically.
    func resetProactiveData() async {
        #if os(macOS)
        scheduledBriefing.setEnabled(false)
        dismissScheduledBriefingNotice()
        #endif
        do {
            try await core.resetProactiveData()
            await proactiveNotifications.cancelPending()
            proactiveSnapshot = nil
            #if os(macOS)
            await removeSharedCompanionSummary()
            #endif
            proactivePreferences = try await core.proactivePreferences()
            try await reconcileSummaryDelivery()
            proactiveError = nil
        } catch { proactiveError = "Proactive data could not be reset. Please try again." }
    }

    func clearProactiveContent() async {
        #if os(macOS)
        scheduledBriefing.cancelCurrentRun()
        dismissScheduledBriefingNotice()
        #endif
        do {
            try await clearProactiveAndSharedContent()
            proactiveSnapshot = try await core.currentProactiveSnapshot()
        } catch {
            proactiveSnapshot = nil
            proactiveError = "Proactive intelligence data couldn’t be cleared."
        }
    }

    private func clearProactiveAndSharedContent() async throws {
        try await core.clearProactiveContent()
        #if os(macOS)
        await removeSharedCompanionSummary()
        #endif
    }

    // MARK: - iPhone companion summary

    func readCompanionSummaryAloud() {
        if voice.isSpeaking || voice.isPreparingSpeech { voice.stopSpeech(); return }
        guard let uid = CompanionSummaryStore.currentUser?.uid, companionAccountID == uid,
              let summary = companionSummary, summary.isValid else { return }
        voice.speak(summary.narration, preserveFullText: true)
    }

    func readDueCompanionUpdates() {
        guard let uid = CompanionSummaryStore.currentUser?.uid, companionAccountID == uid,
              let summary = companionSummary, summary.isValid, let delivery = summary.delivery,
              voice.speaksResponses, voice.canStartSpeech, !voice.isSpeaking, !voice.isPreparingSpeech,
              [.idle, .success, .error].contains(assistant.state) else { return }
        if CompanionPlaybackPreferences.urgentEnabled(for: uid) {
            let updates = CompanionDeliveryPolicy.urgentUpdates(delivery.urgentUpdates,
                alreadySpoken: CompanionPlaybackPreferences.urgentIDs(for: uid))
            if !updates.isEmpty {
                CompanionPlaybackPreferences.markUrgent(updates.map(\.id), for: uid)
                voice.speak(updates.map(\.text).joined(separator: " "), preserveFullText: true)
                return
            }
        }
        if CompanionPlaybackPreferences.routineEnabled(for: uid),
           let key = CompanionDeliveryPolicy.routineKey(schedule: delivery.schedule,
                generatedAt: summary.generatedAt, localDay: summary.localDay),
           CompanionPlaybackPreferences.lastRoutine(for: uid) != key {
            CompanionPlaybackPreferences.markRoutine(key, for: uid)
            voice.speak(summary.narration, preserveFullText: true)
        }
    }

    /// Same account-owned schedule on both devices. The phone never prepares it.
    func refreshCompanionSchedule() async {
        guard !isRefreshingCompanionSchedule, let uid = CompanionSummaryStore.currentUser?.uid else { return }
        isRefreshingCompanionSchedule = true
        defer { isRefreshingCompanionSchedule = false }
        do {
            let saved = try await CompanionAccountDeliveryStore.loadPreferences(expectedUID: uid)
            guard CompanionSummaryStore.currentUser?.uid == uid, !Task.isCancelled else { return }
            #if os(macOS)
            if let saved {
                var value = proactivePreferences
                value.dailyBriefingEnabled = saved.daily_enabled; value.timeCriticalEnabled = saved.urgent_enabled
                value.briefingHour = saved.hour; value.briefingMinute = saved.minute; value.timeZoneIdentifier = saved.time_zone
                if value != proactivePreferences {
                    try await core.updateProactivePreferences(value)
                    guard CompanionSummaryStore.currentUser?.uid == uid else { return }
                    proactivePreferences = value
                    try await reconcileSummaryDelivery()
                }
            } else if !isSavingCompanionSchedule {
                await saveCompanionSchedule(from: proactivePreferences)
                return
            }
            #endif
            companionDeliveryPreferences = saved
            companionDeliveryError = nil
        } catch {
            guard CompanionSummaryStore.currentUser?.uid == uid, !Task.isCancelled else { return }
            companionDeliveryError = "The shared schedule could not be refreshed. Check your connection."
        }
    }

    func saveCompanionSchedule(from value: ProactivePreferences) async {
        guard !isSavingCompanionSchedule, let uid = CompanionSummaryStore.currentUser?.uid else { return }
        isSavingCompanionSchedule = true
        defer { isSavingCompanionSchedule = false }
        do {
            let previous: CompanionAccountPreferences?
            if companionDeliveryPreferences?.firebase_uid == uid { previous = companionDeliveryPreferences }
            else { previous = try await CompanionAccountDeliveryStore.loadPreferences(expectedUID: uid) }
            guard CompanionSummaryStore.currentUser?.uid == uid else { return }
            let desired = CompanionAccountPreferences(firebase_uid: uid, daily_enabled: value.dailyBriefingEnabled,
                urgent_enabled: value.timeCriticalEnabled, hour: value.briefingHour, minute: value.briefingMinute,
                time_zone: value.timeZoneIdentifier, revision: max(1, previous?.revision ?? 1))
            let saved = try await CompanionAccountDeliveryStore.savePreferences(desired, expectedRevision: previous?.revision ?? 0)
            guard CompanionSummaryStore.currentUser?.uid == uid else { return }
            companionDeliveryPreferences = saved
            companionDeliveryError = nil
        } catch {
            guard CompanionSummaryStore.currentUser?.uid == uid, !Task.isCancelled else { return }
            companionDeliveryError = "The schedule was not shared. Refresh to check for a change on your other device, then save again."
        }
    }

    func loadCompanionSummary() async {
        let user = CompanionSummaryStore.currentUser
        companionAccountEmail = user?.email
        guard let user else {
            clearCompanionAccountPresentation()
            hasCheckedCompanionSummary = true
            return
        }
        if companionAccountID != user.uid {
            clearCompanionAccountPresentation()
            companionAccountID = user.uid
            storedCompanionSummary = CompanionSummaryStore.cached(for: user.uid)
        }
        guard !isLoadingCompanionSummary else { return }
        let revision = UUID()
        companionLoadRevision = revision
        isLoadingCompanionSummary = true
        companionError = nil
        defer {
            if companionLoadRevision == revision {
                isLoadingCompanionSummary = false
                hasCheckedCompanionSummary = true
            }
        }
        do {
            let summary = try await CompanionSummaryStore.load(expectedUID: user.uid)
            guard companionLoadRevision == revision, CompanionSummaryStore.currentUser?.uid == user.uid,
                  !Task.isCancelled else { return }
            storedCompanionSummary = summary
        } catch {
            guard companionLoadRevision == revision, CompanionSummaryStore.currentUser?.uid == user.uid,
                  !Task.isCancelled else { return }
            companionError = (error as? CompanionSummaryStoreError)?.localizedDescription
                ?? CompanionSummaryStoreError.unavailable.localizedDescription
        }
    }

    func clearCompanionAccountPresentation() {
        companionLoadRevision = UUID()
        isLoadingCompanionSummary = false
        if let companionAccountID { CompanionSummaryStore.removeCache(for: companionAccountID) }
        companionAccountID = nil
        companionAccountEmail = nil
        storedCompanionSummary = nil
        companionDeliveryPreferences = nil
        companionDeliveryError = nil
        #if os(iOS)
        CompanionPushRegistration.shared.accountCleared()
        #endif
        companionError = nil
        hasCheckedCompanionSummary = false
    }

    #if os(macOS)
    func refreshUrgentCompanionSummary() async {
        guard proactivePreferences.timeCriticalEnabled, let uid = CompanionSummaryStore.currentUser?.uid,
              CompanionSummarySharing.isEnabled(for: uid), !CompanionSummarySharing.needsRemoval(for: uid),
              !isRefreshingInformation, !isPreparingBriefing, !isLoading else { return }
        let request = activeAssistantRequestID
        let session = voice.sessionID
        do {
            try requireBackgroundSummaryOwnership(requestID: request, voiceSessionID: session)
            await refreshInformation()
            try requireBackgroundSummaryOwnership(requestID: request, voiceSessionID: session)
            guard CompanionSummaryStore.currentUser?.uid == uid,
                  CompanionSummarySharing.isEnabled(for: uid), proactivePreferences.timeCriticalEnabled else { return }
            let facts = informationEvents.map { "\($0.id)|\($0.fingerprint)|\($0.sourceUpdatedAt.timeIntervalSince1970)" }.sorted()
            guard facts != lastUrgentCompanionFacts || Date.now.timeIntervalSince(lastUrgentCompanionEvaluation) >= 300 else { return }
            lastUrgentCompanionFacts = facts
            lastUrgentCompanionEvaluation = .now
            await prepareProactiveBriefing(background: true)
        } catch {
            // Interaction, suspension, and cancellation take priority. The
            // next permitted cycle retries without touching the microphone.
        }
    }

    func loadCompanionSharingState() {
        guard let uid = CompanionSummaryStore.currentUser?.uid else {
            sharesSummaryWithIPhone = false
            companionAccountEmail = nil
            companionAccountID = nil
            lastCompanionPublishAt = nil
            return
        }
        if companionAccountID != uid { lastCompanionPublishAt = nil; companionAccountID = uid }
        companionAccountEmail = CompanionSummaryStore.currentUser?.email
        sharesSummaryWithIPhone = CompanionSummarySharing.isEnabled(for: uid)
        if CompanionSummarySharing.needsRemoval(for: uid) {
            Task { await removeSharedCompanionSummary() }
        }
    }

    func setCompanionSharing(_ enabled: Bool) async {
        guard let uid = CompanionSummaryStore.currentUser?.uid else {
            companionError = CompanionSummaryStoreError.noAccount.localizedDescription
            return
        }
        if enabled, CompanionSummarySharing.needsRemoval(for: uid) {
            await removeSharedCompanionSummary()
            guard !CompanionSummarySharing.needsRemoval(for: uid) else { return }
        }
        CompanionSummarySharing.setEnabled(enabled, for: uid)
        sharesSummaryWithIPhone = enabled
        companionError = nil
        if enabled {
            // Publish only a freshly prepared result, never a cached summary
            // that may have been prepared under an earlier account or grant.
            await prepareProactiveBriefing(showActivity: true)
        } else {
            await removeSharedCompanionSummary()
        }
    }

    private func publishCompanionSummary(_ snapshot: ProactiveSnapshot, ownerUID: String?) async {
        guard let uid = ownerUID, uid == CompanionSummaryStore.currentUser?.uid,
              CompanionSummarySharing.isEnabled(for: uid),
              !CompanionSummarySharing.needsRemoval(for: uid),
              let summary = CompanionSummary(snapshot: snapshot, preferences: proactivePreferences) else { return }
        await companionMutations.run { [self] in
            guard CompanionSummaryStore.currentUser?.uid == uid,
                  CompanionSummarySharing.isEnabled(for: uid),
                  !CompanionSummarySharing.needsRemoval(for: uid) else { return }
            do {
                try await CompanionSummaryStore.publish(summary, expectedUID: uid)
                guard CompanionSummaryStore.currentUser?.uid == uid,
                      CompanionSummarySharing.isEnabled(for: uid),
                      !CompanionSummarySharing.needsRemoval(for: uid) else { return }
                companionError = nil
                lastCompanionPublishAt = .now
            } catch {
                guard CompanionSummaryStore.currentUser?.uid == uid,
                      CompanionSummarySharing.isEnabled(for: uid) else { return }
                companionError = "This Daily Summary was prepared on your Mac, but could not be shared with iPhone. Try again in iPhone sharing settings."
            }
        }
    }

    private func removeSharedCompanionSummary() async {
        guard let uid = CompanionSummaryStore.currentUser?.uid else { return }
        CompanionSummarySharing.setNeedsRemoval(true, for: uid)
        await companionMutations.run { [self] in
            guard CompanionSummaryStore.currentUser?.uid == uid else { return }
            do {
                try await CompanionSummaryStore.removeSharedSummary(expectedUID: uid)
                CompanionSummarySharing.setNeedsRemoval(false, for: uid)
                guard CompanionSummaryStore.currentUser?.uid == uid else { return }
                companionError = nil
                lastCompanionPublishAt = nil
            } catch {
                guard CompanionSummaryStore.currentUser?.uid == uid else { return }
                companionError = "The shared iPhone copy could not be removed yet. Check your connection and try again."
            }
        }
    }
    #endif

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

    // MARK: - Capability and previews

    func intelligenceCapability() async -> IntelligenceCapability {
        await understandingPipeline.capability()
    }

    private static func isDailyOverviewRequest(_ text: String) -> Bool {
        let lower = text.lowercased()
        return SuzzmeQuestionIntent.classify(text) == .priorities && !lower.contains("tomorrow")
            || lower.contains("what do i have today")
            || lower.contains("what matters today")
            || lower.contains("daily summary")
            || lower.contains("summarize my day")
            || lower.contains("tell me about my day")
    }

    static var preview: AppEnvironment { AppEnvironment(briefing: MockIntelligenceService.sample(), watchedLinkURL: FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmePreview-\(UUID()).json")) }
}
