import Testing
import Foundation
import SwiftData
@testable import Suzzme

/// Controlled model/storage boundaries; separate from genuine runtime generation.
@Suite @MainActor struct Step21ConversationOwnershipTests {
    @Test func presentationScopeFlowsThroughEnvironmentAndDropsOtherHistory() async throws {
        let model = OwnershipModelFixture()
        let environment = AppEnvironment(understandingPipeline: .init(primary: model), watchedLinkURL: fixtureURL())
        let a = UUID(), b = UUID()
        _ = try await environment.askSuzzme("Explain SCOPE_A_MARKER", conversationID: a)
        _ = try await environment.askSuzzme("Explain that", conversationID: a)
        let continued = await model.history
        #expect(continued.contains("SCOPE_A_MARKER"))
        _ = try await environment.askSuzzme("Explain it", conversationID: b)
        let switched = await model.history
        #expect(switched.isEmpty)
        #expect(environment.currentConversationID == b)
        await environment.cancelVoiceSession()
    }

    @Test func newConversationCannotAdoptAnOldConfirmation() async throws {
        let store = try makeStore()
        await store.setEnabled(true)
        _ = try await store.remember(type: .project, name: "Step21 Scope Fixture", detail: "Disposable unit fixture")
        let environment = AppEnvironment(understandingPipeline: .init(primary: OwnershipModelFixture()), memoryStore: store, watchedLinkURL: fixtureURL())
        let proposal = try await environment.askSuzzme("Forget everything about Project Step21 Scope Fixture.", conversationID: UUID())
        #expect(proposal.action?.status == .awaitingConfirmation)
        _ = try await environment.askSuzzme("yes", conversationID: UUID())
        let stillPresent = try await store.projectID(named: "Step21 Scope Fixture")
        #expect(stillPresent != nil)
        #expect(environment.presentedAction == nil)
        await environment.cancelVoiceSession()
    }

    @Test func reviewedConfirmationAdapterKeepsItsConversationScope() async throws {
        let store = try makeStore()
        await store.setEnabled(true)
        _ = try await store.remember(type: .project, name: "Step21 Review Fixture", detail: "Disposable unit fixture")
        let environment = AppEnvironment(understandingPipeline: .init(primary: OwnershipModelFixture()), memoryStore: store, watchedLinkURL: fixtureURL())
        _ = try await environment.askSuzzme("Forget everything about Project Step21 Review Fixture.", conversationID: UUID())
        let action = try #require(environment.presentedAction)
        let owner = try #require(environment.presentedActionOwner)
        try await environment.respondToPresentedAction(id: action.id, owner: owner, confirmed: true)
        let remaining = try await store.projectID(named: "Step21 Review Fixture")
        #expect(remaining == nil)
        await environment.cancelVoiceSession()
    }

    private func makeStore() throws -> LongTermMemoryStore {
        let schema = Schema([StoredSuzzmeMemory.self, StoredSuzzmeMemoryRelationship.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        return .init(modelContainer: container)
    }
    private func fixtureURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmeStep21-\(UUID()).json")
    }
}

private actor OwnershipModelFixture: SuzzmeIntelligenceService {
    private(set) var history = ""
    func capability() async -> IntelligenceCapability { .available }
    func understand(text: String, referenceDate: Date) async throws -> [ExtractedSuzzmeItem] { [] }
    func summarize(text: String) async throws -> String { text }
    func answerQuestion(question: String, facts: String, conversation: String, screenUnderstanding: String?) async throws -> String? {
        history = conversation
        return "Fixture response for \(question)"
    }
}
