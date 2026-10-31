import Foundation
import SwiftData

/// Deterministic boundary fixtures. No response here is real-model acceptance.
private actor ConversationModelFixture: SuzzmeIntelligenceService {
    struct Call: Sendable { let question: String; let conversation: String; let facts: String }
    private(set) var questions: [Call] = []
    private(set) var extractions: [String] = []
    private let blocks: Bool
    private var answerContinuation: CheckedContinuation<String?, Never>?
    private var readyContinuation: CheckedContinuation<Void, Never>?
    init(blocks: Bool = false) { self.blocks = blocks }
    func capability() async -> IntelligenceCapability { .available }
    func summarize(text: String) async throws -> String { text }
    func understand(text: String, referenceDate: Date) async throws -> [ExtractedSuzzmeItem] {
        extractions.append(text)
        return [.init(title: "Fixture deadline", summary: "Explicit input fact", category: .deadline,
            priority: .normal, confidence: 1, reason: "Recording fixture")]
    }
    func answerQuestion(question: String, facts: String, conversation: String, screenUnderstanding: String?) async throws -> String? {
        questions.append(.init(question: question, conversation: conversation, facts: facts))
        readyContinuation?.resume(); readyContinuation = nil
        if blocks { return await withCheckedContinuation { answerContinuation = $0 } }
        return question == "What is two plus two?" ? "Fixture answer: four." : "Fixture conversational answer."
    }
    func waitUntilStarted() async {
        if !questions.isEmpty { return }
        await withCheckedContinuation { readyContinuation = $0 }
    }
    func release() { answerContinuation?.resume(returning: "Late fixture answer"); answerContinuation = nil }
}

private struct ConversationCapabilityFixture: SuzzmeCapability {
    let id: SuzzmeCapabilityID
    let store: ActionStoreDouble
    func availability() -> SuzzmeCapabilityAvailability { .available }
    func resolve(_ plan: SuzzmeActionPlan) -> SuzzmeActionPlan {
        switch plan.payload {
        case var .reminder(value):
            value.calendarIdentifier = "fixture-local"
            return plan.replacingPayload(.reminder(value))
        case var .calendar(value):
            value.calendarIdentifier = "fixture-local"
            return plan.replacingPayload(.calendar(value))
        case .completedReminders: return plan
        }
    }
    func execute(_ plan: SuzzmeActionPlan, authorization: isolated SuzzmeActionExecutionCoordinator) async throws -> SuzzmeCapabilityResult {
        try SuzzmeActionMutation.execute(plan, store: store, authorization: authorization)
    }
}

@main @MainActor struct Step21IntelligenceChecks {
    static var passed = 0
    static var failed = 0
    static func expect(_ value: Bool, _ label: String) {
        FileHandle.standardOutput.write(Data("\(value ? "PASS" : "FAIL") \(label)\n".utf8))
        if value { passed += 1 } else { failed += 1 }
    }
    static func ask(_ core: SuzzmeCore, _ text: String, scope: UUID, request: UUID = UUID()) async throws -> SuzzmeCoreResponse {
        FileHandle.standardOutput.write(Data("FIXTURE INPUT: \(text)\n".utf8))
        return try await core.respond(to: text, sources: [], query: .infer(from: text), requestID: request,
            existingFingerprints: [], conversationID: scope) { _ in }
    }

    static func scheduledBriefingMemoryIsolation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmeStep21ScheduledMemory-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date.now
        let file = directory.appendingPathComponent("proactive.json")
        let session = SessionMemoryEngine()
        let existing = SuzzmeContextItem(sourceIdentifier: "interactive-fixture", content: "Current conversation context", timestamp: now)
        await session.remember(context: [existing], intent: .information, now: now)
        let before = await session.snapshot(now: now)
        let model = ConversationModelFixture()
        let core = SuzzmeCore(router: .init(pipeline: .init(primary: model)), memory: session,
            proactive: .init(store: .init(fileURL: file)))
        let item = SuzzmeItem(id: UUID(), title: "Review the fixture report", summary: "Prepare the synthetic review notes",
            source: .manual, category: .deadline, priority: .important, createdAt: now,
            dueDate: now.addingTimeInterval(3_600))
        let sources: [any ContextSource] = [SuzzmeItemContextSource(items: [item])]
        let background = try await core.prepareProactiveBriefing(from: sources, now: now, rememberInSession: false)
        let persisted = try await ProactiveIntelligenceStore(fileURL: file).current(now: now)
        expect(background.briefing?.items.isEmpty == false && persisted.briefing?.id == background.briefing?.id
            && persisted.briefing?.items.contains { $0.summary.contains(item.title) } == true,
               "scheduled preparation persists a nonempty briefing from actual grounded local items")
        let afterBackground = await session.snapshot(now: now)
        expect(afterBackground.contextItems == before.contextItems && afterBackground.turns == before.turns
            && afterBackground.activeIntent == before.activeIntent,
               "scheduled preparation leaves the injected interactive session memory unchanged")

        let interactive = try await core.prepareProactiveBriefing(from: sources, now: now)
        let afterInteractive = await session.snapshot(now: now)
        let expected = Set((interactive.briefing?.items ?? []).map(\.candidateID))
        let remembered = Set(afterInteractive.contextItems.filter { $0.metadata["proactiveProjection"] == "true" }
            .compactMap { $0.metadata["candidateID"] })
        expect(!expected.isEmpty && remembered == expected && afterInteractive.contextItems.contains(existing),
               "default interactive preparation still projects its real briefing into the same session memory")
        let providerQuestions = await model.questions
        let providerExtractions = await model.extractions
        expect(providerQuestions.isEmpty && providerExtractions.isEmpty,
               "summary memory isolation uses deterministic local Core paths without model-provider calls")
    }

    static func main() async throws {
        print("STEP 21 DETERMINISTIC FIXTURES — NOT REAL AI ACCEPTANCE")
        let model = ConversationModelFixture()
        let memory = SessionMemoryEngine()
        let core = SuzzmeCore(router: .init(pipeline: .init(primary: model)), memory: memory)
        let scope = UUID()
        for question in ["Name a primary color.", "What is photosynthesis?", "Explain quantum computing.", "Give me an example of a metaphor."] {
            let answer = try await ask(core, question, scope: scope)
            expect(answer.route == .onDeviceIntelligence && answer.extractedItems.isEmpty && answer.action == nil,
                "ordinary question reaches read-only model boundary: \(question)")
        }
        expect(await model.extractions.isEmpty, "general questions never reach extraction")
        let arithmeticScope = UUID()
        _ = try await ask(core, "What is two plus two?", scope: arithmeticScope)
        for followUp in ["And add three to that result.", "Explain it.", "Compare that with the previous answer.", "Summarize our conversation.", "Summarize what we discussed."] {
            let answer = try await ask(core, followUp, scope: arithmeticScope)
            let call = await model.questions.last
            expect(answer.extractedItems.isEmpty && answer.action == nil && answer.route == .onDeviceIntelligence,
                "follow-up stays read-only: \(followUp)")
            expect(call?.conversation.isEmpty == false && call?.conversation.contains(followUp) == false,
                "model receives prior turns, without duplicating current prompt")
        }
        let arithmetic = await model.questions.first { $0.question == "And add three to that result." }
        expect(arithmetic?.conversation.contains("What is two plus two?") == true
            && arithmetic?.conversation.contains("Fixture answer: four.") == true, "arithmetic reference includes complete preceding exchange")
        expect(arithmetic?.conversation.contains("primary color") == false, "switching conversations discards unrelated turns")
        expect(await model.extractions.isEmpty, "pronouns, arithmetic and summaries do not extract")
        let summaryCall = await model.questions.last
        expect(summaryCall?.conversation.contains("What is two plus two?") == true,
            "conversation summary retains earlier short exchanges within the existing budget")

        let countBeforeEmptySummary = await model.questions.count
        for question in ["Summarize our conversation.", "Summarize what we discussed.", "Please recap our chat."] {
            let answer = try await ask(core, question, scope: UUID())
            expect(answer.route == .localContext && answer.text.contains("no earlier messages") && answer.extractedItems.isEmpty,
                "fresh conversation summary reports missing history: \(question)")
        }
        expect(await model.questions.count == countBeforeEmptySummary, "empty conversation summary never invites model fabrication")

        let captures = ["Extract the tasks from this note: submit the report tomorrow.", "Submit the report before Friday.",
            "Please extract the facts from this note: Lecture tomorrow at 10 AM?"]
        for content in captures {
            let answer = try await ask(core, content, scope: UUID())
            expect(answer.extractedItems.count == 1 && answer.action == nil, "explicit/dated capture remains available: \(content)")
            expect(SuzzmeContextQuery.infer(from: content).sources.isEmpty, "pasted capture needs no unrelated Apple-source access")
        }
        expect(await model.extractions.count == captures.count, "authorized capture routes use existing extraction boundary")

        let schema = Schema([StoredSuzzmeMemory.self, StoredSuzzmeMemoryRelationship.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let store = LongTermMemoryStore(modelContainer: container)
        await store.setEnabled(true)
        let durable = SuzzmeCore(router: .init(pipeline: .init(primary: model)), memoryStore: store)
        let saved = try await ask(durable, "Remember my main project is Step21Fixture", scope: UUID())
        let storedMemories = try await store.allMemories()
        expect(saved.text.contains("remember") && !storedMemories.isEmpty, "explicit memory save still reaches authorized memory store")

        let actionStore = ActionStoreDouble()
        let coordinator = SuzzmeActionExecutionCoordinator(registry: .init(capabilities: [
            ConversationCapabilityFixture(id: .calendar, store: actionStore), ConversationCapabilityFixture(id: .reminders, store: actionStore)]))
        let actionCore = SuzzmeCore(router: .init(pipeline: .init(primary: model)), actionCoordinator: coordinator)
        let calendarOwner = UUID(), actionScope = UUID()
        let calendar = try await ask(actionCore, "Create a calendar event Study tomorrow at 3 PM", scope: actionScope, request: calendarOwner)
        expect(calendar.action?.status == .awaitingConfirmation && actionStore.state.withLock { $0.writes == 0 }, "calendar creation still proposes, without writing")
        await actionCore.cancel(requestID: calendarOwner)
        let reminderOwner = UUID()
        let reminder = try await ask(actionCore, "Remind me to study tomorrow at 8 PM", scope: actionScope, request: reminderOwner)
        expect(reminder.action?.status == .awaitingConfirmation && actionStore.state.withLock { $0.writes == 0 }, "reminder creation still requires confirmation")
        do {
            _ = try await actionCore.respond(to: "confirm", sources: [], requestID: reminderOwner,
                confirmationActionID: UUID(), existingFingerprints: [], conversationID: actionScope) { _ in }
            expect(false, "wrong confirmation rejected")
        } catch SuzzmeCapabilityError.staleRequest { expect(true, "wrong confirmation rejected") }
        let confirmed = try await actionCore.respond(to: "confirm", sources: [], requestID: reminderOwner,
            confirmationActionID: reminder.action?.id, existingFingerprints: [], conversationID: actionScope) { _ in }
        expect(confirmed.action?.status == .completed && actionStore.state.withLock { $0.writes == 1 }, "reviewed confirmation performs exactly one fixture write")
        let ambiguous = try await ask(core, "Add it", scope: UUID())
        expect(ambiguous.action == nil && ambiguous.extractedItems.isEmpty, "ambiguous request cannot fabricate an action or extraction")

        let blockedModel = ConversationModelFixture(blocks: true)
        let cancelledMemory = SessionMemoryEngine()
        let cancellable = SuzzmeCore(router: .init(pipeline: .init(primary: blockedModel)), memory: cancelledMemory)
        let cancelOwner = UUID(), cancelScope = UUID()
        let task = Task { try await ask(cancellable, "Explain cancellation", scope: cancelScope, request: cancelOwner) }
        await blockedModel.waitUntilStarted()
        await cancellable.cancel(requestID: cancelOwner); task.cancel()
        await blockedModel.release()
        do { _ = try await task.value; expect(false, "late cancelled answer rejected") }
        catch is CancellationError { expect(true, "late cancelled answer rejected") }
        expect(await cancelledMemory.snapshot().turns.isEmpty, "cancelled question and answer never enter subsequent model history")

        let a = UUID(), b = UUID()
        _ = try await ask(core, "Explain CONVERSATION_A_MARKER", scope: a)
        _ = try await ask(core, "Explain it", scope: b)
        expect(await model.questions.last?.conversation.isEmpty == true, "new conversation cannot read A history")
        _ = try await ask(core, "Explain it", scope: a)
        expect(await model.questions.last?.conversation.isEmpty == true, "returning to a retired ID cannot resurrect its history")

        let now = Date.now
        let expired = SuzzmeSessionTurn(id: UUID(), role: .assistant, text: "EXPIRED_MARKER", timestamp: now, expiresAt: now.addingTimeInterval(-1))
        let restricted = SuzzmeSessionTurn(id: UUID(), role: .assistant, text: "My password is RESTRICTED_MARKER", timestamp: now, expiresAt: now.addingTimeInterval(60))
        let router = IntelligenceRouter(pipeline: .init(primary: model))
        _ = try await router.route(text: "Explain that", context: [], conversation: [expired, restricted], existingFingerprints: [], referenceDate: now)
        expect(await model.questions.last?.conversation.isEmpty == true, "expired and restricted turns are excluded at the model boundary")
        let count = await model.questions.count
        let unavailableSummary = try await router.route(text: "Summarize what we discussed.", context: [],
            conversation: [expired, restricted], existingFingerprints: [], referenceDate: now)
        expect(unavailableSummary.route == .localContext && unavailableSummary.text.contains("no earlier messages"),
            "expired/private-only history is unavailable for conversation summaries")
        expect(await model.questions.count == count, "excluded history summary does not reach generation")
        do { _ = try await ask(core, "My password is RESTRICTED_INPUT", scope: UUID()); expect(false, "secret input rejected") }
        catch SuzzmeCoreError.restrictedContent { expect(true, "secret input rejected") }
        expect(await model.questions.count == count, "restricted input never reaches model")
        expect(await memory.snapshot().turns.allSatisfy { !$0.text.contains("RESTRICTED_INPUT") }, "restricted input does not enter history")
        let owner = UUID(), newer = UUID()
        await cancelledMemory.beginReadOnlyRequest(owner, conversationID: a)
        await cancelledMemory.beginReadOnlyRequest(newer, conversationID: b)
        expect(await cancelledMemory.rememberReadOnlyExchange(question: "Old", answer: "Old answer", requestID: owner) == false,
            "stale exchange cannot enter a newer conversation")
        expect(await cancelledMemory.rememberReadOnlyExchange(question: "My password is SECRET", answer: "Safe", requestID: newer) == false,
            "exchange commit enforces privacy independently of its caller")
        try await scheduledBriefingMemoryIsolation()
        print("Step 21 passed: \(passed)")
        print("Step 21 failed: \(failed)")
        if failed != 0 { exit(1) }
    }
}
