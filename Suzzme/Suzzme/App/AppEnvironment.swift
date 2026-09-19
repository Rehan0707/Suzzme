import Foundation
import Observation

@MainActor @Observable
final class AppEnvironment {
    private let intelligence: any IntelligenceService
    private let understandingPipeline: SuzzmeUnderstandingPipeline
    private let core: SuzzmeCore
    private let privacy = PrivacyEngine()
    private let permissions = AppleContextPermissions()
    private let calendarSource = CalendarContextSource()
    private let remindersSource = RemindersContextSource()
    private let contactsSource = ContactsContextSource()
    private(set) var sourcePermissions: [SuzzmeContextSourceKind: SuzzmePermissionState] = [:]
    private var activeAssistantRequestID: UUID?
    private let itemStore: SuzzmeItemStore?
    private let memoryStore: LongTermMemoryStore?
    private(set) var briefing: DailyBriefing?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    let assistant = AssistantStateController()
    let voice: VoiceSessionController
    let invocation = InvocationCoordinator()
    var presenceState: SuzzmeAssistantState { assistant.state }
    private(set) var lastUnderstandingResult: SuzzmeUnderstandingResult?
    private(set) var activityItems: [SuzzmeItem] = []

    init(
        intelligence: any IntelligenceService = MockIntelligenceService(),
        understandingPipeline: SuzzmeUnderstandingPipeline = SuzzmeUnderstandingPipeline(),
        itemStore: SuzzmeItemStore? = nil,
        briefing: DailyBriefing? = nil,
        memoryStore: LongTermMemoryStore? = nil
    ) {
        self.intelligence = intelligence
        self.understandingPipeline = understandingPipeline
        self.core = SuzzmeCore(memoryStore: memoryStore)
        self.itemStore = itemStore
        self.memoryStore = memoryStore
        self.briefing = briefing
        self.voice = VoiceSessionController(assistant: assistant)
    }

    func loadIfNeeded() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if let storedItems = try itemStore?.allItems() {
                activityItems = storedItems
                guard !storedItems.isEmpty else {
                    if let briefing, Calendar.current.isDateInToday(briefing.date) { return }
                    briefing = try await intelligence.dailyBriefing(for: .now, name: "Rehan")
                    return
                }
                briefing = DailyBriefingBuilder.make(from: storedItems)
            } else {
                if let briefing, Calendar.current.isDateInToday(briefing.date) { return }
                briefing = try await intelligence.dailyBriefing(for: .now, name: "Rehan")
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
        briefing = DailyBriefingBuilder.make(from: activityItems)
        return saved
    }

    func askSuzzme(_ text: String, speakResponse: Bool = false, requestID: UUID? = nil) async throws -> SuzzmeCoreResponse {
        let requestID = requestID ?? UUID()
        activeAssistantRequestID = requestID
        assistant.transition(to: .understanding)
        var completed = false
        defer {
            if activeAssistantRequestID == requestID, !completed { assistant.reset() }
        }
        let fingerprints = try itemStore?.fingerprints() ?? []
        let query = SuzzmeContextQuery.infer(from: text)
        let permissionStates = await permissionStates(for: query.sources)
        sourcePermissions.merge(permissionStates) { _, new in new }
        if !query.sources.isEmpty, permissionStates.values.allSatisfy({ $0 != .authorized }) {
            let response = SuzzmeCoreResponse(text: unavailableMessage(for: query.sources, states: permissionStates), route: .localContext, contextCount: 0, extractedItems: [])
            completed = true
            if speakResponse && voice.speaksResponses { voice.speak(response.text) } else { assistant.complete() }
            return response
        }
        let sources = contextSources(for: query) + [SuzzmeItemContextSource(items: activityItems)]
        do {
            let response = try await core.respond(to: text, sources: sources, query: query, requestID: requestID, existingFingerprints: fingerprints) { [weak self] state in
                await MainActor.run {
                    guard self?.activeAssistantRequestID == requestID else { return }
                    self?.assistant.transition(to: state)
                }
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
            if response.action?.status == .awaitingConfirmation {
                assistant.transition(to: .awaitingConfirmation)
            } else if speakResponse && voice.speaksResponses {
                voice.speak(response.text)
            } else {
                assistant.complete()
            }
            return response
        } catch is CancellationError {
            await core.cancel(requestID: requestID)
            guard activeAssistantRequestID == requestID else { throw CancellationError() }
            assistant.fail(message: "That request was cancelled.")
            completed = true
            throw CancellationError()
        } catch {
            guard activeAssistantRequestID == requestID else { throw CancellationError() }
            assistant.fail(message: error.localizedDescription)
            completed = true
            throw error
        }
    }

    private func permissionStates(for kinds: Set<SuzzmeContextSourceKind>) async -> [SuzzmeContextSourceKind: SuzzmePermissionState] {
        var statuses: [SuzzmeContextSourceKind: SuzzmePermissionState] = [:]
        for kind in kinds { statuses[kind] = await permissions.status(for: kind) }
        return statuses
    }

    private func unavailableMessage(for kinds: Set<SuzzmeContextSourceKind>, states: [SuzzmeContextSourceKind: SuzzmePermissionState]) -> String {
        guard let kind = kinds.first, let state = states[kind] else { return "That source isn’t available right now." }
        let name = switch kind { case .calendar: "Calendar"; case .reminders: "Reminders"; case .contacts: "Contacts" }
        return state == .notDetermined ? "Connect \(name) in Intelligence Sources to answer that." : "\(name) access is off. You can enable it in Intelligence Sources."
    }

    /// The only start path for an explicit system or in-app invocation.
    /// It gives VoiceSessionController the same request identity SuzzmeCore
    /// later receives with the final transcript.
    @discardableResult
    func invokeSuzzme() async -> Bool {
        switch invocation.begin() {
        case .alreadyActive:
            return false
        case let .started(requestID):
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

    func cancelVoiceSession() async {
        let requestID = invocation.cancel() ?? activeAssistantRequestID
        voice.cancel()
        guard let requestID else { return }
        await core.cancel(requestID: requestID)
        if activeAssistantRequestID == requestID { activeAssistantRequestID = nil }
    }

    func submitVoiceTranscript(_ text: String, sessionID: UUID) async throws -> SuzzmeCoreResponse {
        guard activeAssistantRequestID == sessionID else { throw CancellationError() }
        do {
            let response = try await askSuzzme(text, speakResponse: true, requestID: sessionID)
            if response.action?.status != .awaitingConfirmation { invocation.finish(sessionID) }
            return response
        } catch {
            invocation.finish(sessionID)
            throw error
        }
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
    func deleteMemory(_ memory: SuzzmeMemoryRecord) async throws { try await memoryStore?.delete(id: memory.id) }
    func clearPersonalMemory() async throws { try await memoryStore?.clear() }

    func clearSessionMemory() async { await core.clearSession() }

    func intelligenceCapability() async -> IntelligenceCapability {
        await understandingPipeline.capability()
    }

    static var preview: AppEnvironment { AppEnvironment(briefing: MockIntelligenceService.sample()) }
}
