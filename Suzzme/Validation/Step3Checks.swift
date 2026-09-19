import Foundation
import SwiftData

@main
struct Step3Checks {
    @MainActor static func main() async throws {
        let privacy = PrivacyEngine()
        precondition(privacy.classify("My password is 1234").policy == .neverProcess)
        precondition(privacy.classify("Bearer abc123").policy == .neverProcess)
        precondition(privacy.classify("My medical appointment is tomorrow").policy == .localOnly)
        precondition(privacy.classify("Public campus event").sensitivity == .public)

        let engine = ContextEngine(privacyEngine: privacy)
        let normalized = await engine.normalize([
            SuzzmeContextItem(sourceIdentifier: "manual", content: "  Study group at 4 PM.  "),
            SuzzmeContextItem(sourceIdentifier: "manual", content: "password is secret"),
            SuzzmeContextItem(sourceIdentifier: "manual", content: "   ")
        ])
        precondition(normalized.count == 1)
        precondition(normalized[0].content == "Study group at 4 PM.")
        precondition(normalized[0].sensitivity == .personal)
        let duplicate = await engine.normalize([normalized[0], normalized[0]])
        precondition(duplicate.count == 1)
        let collected = try await engine.collect(from: [
            StaticContextSource(items: normalized),
            FailingContextSource()
        ])
        precondition(collected.count == 1)

        let memory = SessionMemoryEngine(maximumTurns: 2, lifetime: 1)
        let start = Date(timeIntervalSince1970: 1_000)
        await memory.remember(role: .user, text: "When is it?", now: start)
        let currentMemory = await memory.snapshot(now: start)
        precondition(currentMemory.turns.count == 1)
        let expiredMemory = await memory.snapshot(now: start.addingTimeInterval(2))
        precondition(expiredMemory.turns.isEmpty)
        await memory.remember(context: [SuzzmeContextItem(sourceIdentifier: "manual", content: "secret", sensitivity: .restricted)])
        let restrictedSnapshot = await memory.snapshot()
        precondition(restrictedSnapshot.contextItems.isEmpty)

        let controller = AssistantStateController()
        controller.transition(to: .gatheringContext)
        precondition(controller.state == .gatheringContext)
        precondition(controller.message == "Checking your context…")
        controller.reset()
        precondition(controller.state == .idle)
        controller.fail(message: "A safe error")
        precondition(controller.state == .error)
        try? await Task.sleep(for: .seconds(1.6))
        precondition(controller.state == .idle)
        controller.complete()
        precondition(controller.state == .success)
        try? await Task.sleep(for: .seconds(1.6))
        precondition(controller.state == .idle)

        let action = SuzzmeAction(type: .sendMessage, title: "Send update", risk: .consequential)
        let safeAction = SuzzmeAction(type: .openApp, title: "Open Calendar", risk: .readOnly)
        precondition(action.requiresConfirmation)
        precondition(!safeAction.requiresConfirmation)
        precondition(!SuzzmeActionSafety.mayExecute(action, userConfirmed: false))
        precondition(SuzzmeActionSafety.mayExecute(action, userConfirmed: true))

        let fallback = BasicIntelligenceService()
        let fallbackCapability = await fallback.capability()
        precondition(fallbackCapability == .unsupportedOS)
        let router = IntelligenceRouter(pipeline: SuzzmeUnderstandingPipeline(primary: fallback, fallback: fallback))
        let localContext = [SuzzmeContextItem(sourceIdentifier: "calendar", content: "Operating Systems at 10 AM", intent: .event)]
        let focused = try await router.route(text: "What do I need to focus on today?", context: localContext, existingFingerprints: [])
        precondition(focused.route == .localContext)
        let extracted = try await router.route(text: "Submit the report before Friday.", context: [], existingFingerprints: [])
        precondition(extracted.route == .deterministic)
        precondition(extracted.extractedItems.first?.category == .deadline)
        let core = SuzzmeCore(router: router)
        do {
            _ = try await core.respond(to: "My password is secret", sources: [], existingFingerprints: []) { _ in }
            preconditionFailure("Restricted content must not reach routing.")
        } catch SuzzmeCoreError.restrictedContent {}

        // Exercise the real privacy → core → durable-store boundary. No
        // restricted request may leave a durable record behind.
        let durableContainer = try ModelContainer(
            for: StoredSuzzmeItem.self, StoredSuzzmeMemory.self, StoredSuzzmeMemoryRelationship.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let durableStore = LongTermMemoryStore(modelContainer: durableContainer)
        await durableStore.setEnabled(true)
        let durableCore = SuzzmeCore(router: router, memoryStore: durableStore)
        for restricted in [
            "Remember my password is hunter2",
            "Remember my OTP is 123456",
            "Remember my verification code is 123456",
            "Remember my API key is sk-test",
            "Remember my access token is private",
            "Remember my bearer token is private"
        ] {
            do {
                _ = try await durableCore.respond(to: restricted, sources: [], existingFingerprints: []) { _ in }
                preconditionFailure("Restricted content must not reach persistence.")
            } catch SuzzmeCoreError.restrictedContent {}
        }
        let restrictedRecords = try await durableStore.memories()
        precondition(restrictedRecords.isEmpty)

        // Conversation-level bulk forgetting must propose, cancel without a
        // write, and only delete the requested scope after confirmation.
        let seedRequest = UUID()
        await durableStore.authorize(seedRequest)
        _ = try await durableStore.commit(.remember(type: .project, name: "Alpha", detail: "Your project"), requestID: seedRequest)
        _ = try await durableStore.commit(.remember(type: .project, name: "Beta", detail: "Your project"), requestID: seedRequest)
        _ = try await durableStore.commit(.relationship(person: "Aryan Sharma", project: "Alpha"), requestID: seedRequest)
        let proposal = try await durableCore.respond(to: "Forget everything about Project Alpha.", sources: [], requestID: UUID(), existingFingerprints: []) { _ in }
        precondition(proposal.action?.status == .awaitingConfirmation)
        let proposedRecords = try await durableStore.memories()
        precondition(proposedRecords.contains { $0.name == "Alpha" })
        let cancellation = try await durableCore.respond(to: "no", sources: [], requestID: UUID(), existingFingerprints: []) { _ in }
        precondition(cancellation.action?.status == .cancelled)
        let cancelledRecords = try await durableStore.memories()
        precondition(cancelledRecords.contains { $0.name == "Alpha" })
        let secondProposal = try await durableCore.respond(to: "Forget everything about Project Alpha.", sources: [], requestID: UUID(), existingFingerprints: []) { _ in }
        precondition(secondProposal.action?.status == .awaitingConfirmation)
        let confirmation = try await durableCore.respond(to: "yes", sources: [], requestID: UUID(), existingFingerprints: []) { _ in }
        precondition(confirmation.action?.status == .completed)
        let afterConfirmation = try await durableStore.memories()
        precondition(!afterConfirmation.contains { $0.name == "Alpha" })
        precondition(afterConfirmation.contains { $0.name == "Beta" })
        precondition(afterConfirmation.contains { $0.name == "Aryan Sharma" })

        // A newer live Apple-context item answers schedule questions instead
        // of any older durable memory with similar wording.
        let liveRequest = UUID()
        await durableStore.authorize(liveRequest)
        _ = try await durableStore.commit(.remember(type: .event, name: "Old Project Meeting", detail: "Yesterday at 9 AM"), requestID: liveRequest)
        let liveEvent = SuzzmeContextItem(
            sourceIdentifier: "live-calendar-event",
            content: "Current Project Meeting",
            intent: .event,
            metadata: ["source": "calendar", "start": ISO8601DateFormatter().string(from: .now)]
        )
        let liveResponse = try await durableCore.respond(to: "What do I have today?", sources: [StaticContextSource(items: [liveEvent])], requestID: UUID(), existingFingerprints: []) { _ in }
        precondition(liveResponse.text.contains("Current Project Meeting"))
        precondition(!liveResponse.text.contains("Old Project Meeting"))

        let sessionCore = SuzzmeCore(router: router, memory: SessionMemoryEngine())
        let meeting = SuzzmeContextItem(sourceIdentifier: "calendar", content: "Project meeting tomorrow at 11 AM", intent: .event)
        _ = try await sessionCore.respond(to: "When is my project meeting?", sources: [StaticContextSource(items: [meeting])], existingFingerprints: []) { _ in }
        let followUp = try await sessionCore.respond(to: "Who is attending?", sources: [], existingFingerprints: []) { _ in }
        precondition(followUp.route == .localContext)
        precondition(followUp.text.contains("don’t have attendee information"))
        print("PASS: context normalization, privacy, session expiry, assistant state, routing, and action confirmation")
    }
}

private struct StaticContextSource: ContextSource {
    let identifier = "test-static"
    let items: [SuzzmeContextItem]
    func fetchContext(for request: SuzzmeContextRequest) async throws -> [SuzzmeContextItem] { items }
}

private struct FailingContextSource: ContextSource {
    let identifier = "test-failing"
    func fetchContext(for request: SuzzmeContextRequest) async throws -> [SuzzmeContextItem] {
        throw SuzzmeContextError.sourceUnavailable(identifier)
    }
}
