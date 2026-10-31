import XCTest
import SwiftUI
import SwiftData
@testable import Suzzme

/// Exact original assertions hosted by the unchanged production iOS app.
/// In-memory memory records are controlled fixtures, not user/runtime evidence.
/// The six Mac path assertions use the separately extracted exact shape source.
final class FinalUIHostedBehaviorTests: XCTestCase {
    @MainActor func testPreservedUIAssertionsAndConversationOwnership() async throws {
        PreservedFinalUIBehaviorChecks.passed = 0
        PreservedFinalUIBehaviorChecks.failed = 0
        try await PreservedFinalUIBehaviorChecks.main()
        XCTAssertEqual(PreservedFinalUIBehaviorChecks.failed, 0)
        XCTAssertEqual(PreservedFinalUIBehaviorChecks.passed, 80,
                       "All 53 original checks, 12 conversation checks and 15 ownership checks must execute")
    }
}

@MainActor private enum PreservedFinalUIBehaviorChecks {
    static var passed = 0
    static var failed = 0
    static func check(_ value: Bool, _ name: String) {
        if value { passed += 1 } else { failed += 1 }
        print("\(value ? "PASS" : "FAIL") \(name)")
        XCTAssertTrue(value, name)
    }
    static func main() async throws {
        for state in SuzzmeAssistantState.allCases {
            let value = SuzzmeAssistantPresentation.make(for: state)
            check(SuzzmeSystemPresenceState(state).presentation == value && !value.systemStatus.isEmpty, "shared semantic mapping: \(state)")
        }
        check(!SuzzmeAssistantPresentation.make(for: .idle).isVisible, "idle hidden")
        check(SuzzmeAssistantPresentation.make(for: .success).shouldCollapse, "success collapses")
        check(SuzzmeAssistantPresentation.make(for: .success).title != "Done", "generic request completion never claims mutation done")
        check(SuzzmePresenceAnimation.minimal.duration == 0, "minimal has no continuous motion")
        check(Set(SuzzmePresenceTheme.allCases.map(\.accessibilityName)).count == 5, "five distinct named themes")
        for theme in SuzzmePresenceTheme.allCases {
            check(theme.colors(for: .light).face != theme.colors(for: .dark).face, "face adapts: \(theme)")
        }
        for kind in [SuzzmeSystemActivityKind.assistantInteraction, .dailySummaryReady, .opportunityReady, .timeCriticalNotice] {
            check(!SuzzmeActivityEligibility.isEligible(kind), "no fabricated Live Activity: \(kind)")
        }
        let router = AppRouter()
        for destination in AppDestination.allCases {
            router.selection = destination
            check(router.selection == destination && !destination.title.isEmpty, "navigation: \(destination)")
        }
        check(SuzzmeActionType.deleteReminder.confirmationLabel == "Delete Reminder" && SuzzmeActionType.deleteCalendarEvent.confirmationLabel == "Delete Event", "specific destructive verbs")
        check(SuzzmePermissionState.authorized.displayName != SuzzmePermissionState.unavailable.displayName && SuzzmePermissionState.denied.displayName != SuzzmePermissionState.notDetermined.displayName, "permission availability distinctions")
        for size in [CGSize(width: 316, height: 102), CGSize(width: 380, height: 300), CGSize(width: 10, height: 10)] {
            let rect = CGRect(origin: .zero, size: size)
            for attached in [false, true] {
                let bounds = SuzzmeNotchSurfaceShape(attached: attached, neckWidth: 180).path(in: rect).boundingRect
                check(rect.contains(bounds), "presence geometry bounded: \(size), attached \(attached)")
            }
        }
        let schema = Schema([StoredSuzzmeMemory.self, StoredSuzzmeMemoryRelationship.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let memory = LongTermMemoryStore(modelContainer: container)
        await memory.setEnabled(true)
        _ = try await memory.remember(type: .project, name: "Final UI Fixture", detail: "Disposable validation project")
        let environment = AppEnvironment(memoryStore: memory, watchedLinkURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let response = try await environment.askSuzzme("Forget everything about Project Final UI Fixture.")
        guard let action = response.action, let owner = environment.presentedActionOwner else {
            check(false, "real confirmation created"); print("Final UI failed: \(failed)"); return
        }
        check(environment.presentedAction?.id == action.id && environment.presenceState == .awaitingConfirmation, "central action projected into Presence")
        do { try await environment.respondToPresentedAction(id: UUID(), owner: owner, confirmed: true); check(false, "wrong action rejected") }
        catch { check(true, "wrong action rejected") }
        do { try await environment.respondToPresentedAction(id: action.id, owner: UUID(), confirmed: true); check(false, "wrong owner rejected") }
        catch { check(true, "wrong owner rejected") }
        check(try await memory.projectID(named: "Final UI Fixture") != nil, "stale callbacks cannot mutate")
        try await environment.respondToPresentedAction(id: action.id, owner: owner, confirmed: false)
        check(environment.presentedAction == nil && environment.presentedActionOwner == nil, "cancel clears confirmation projection")
        check(try await memory.projectID(named: "Final UI Fixture") != nil, "cancel preserves target")
        do { try await environment.respondToPresentedAction(id: action.id, owner: owner, confirmed: true); check(false, "cancelled confirmation rejected") }
        catch { check(true, "cancelled confirmation rejected") }
        _ = try await environment.askSuzzme("Forget everything about Project Final UI Fixture.")
        guard let next = environment.presentedAction, let nextOwner = environment.presentedActionOwner else { check(false, "second proposal"); return }
        check(next.id != action.id, "new proposal has new identity")
        try await environment.respondToPresentedAction(id: next.id, owner: nextOwner, confirmed: true)
        check(try await memory.projectID(named: "Final UI Fixture") == nil, "valid UI confirmation reaches central execution")
        do { try await environment.respondToPresentedAction(id: next.id, owner: nextOwner, confirmed: true); check(false, "duplicate confirmation rejected") }
        catch { check(true, "duplicate confirmation rejected") }
        await environment.cancelVoiceSession()
        check(environment.presentedResponse == nil && environment.presentedAction == nil, "cancellation removes private presentation")
        _ = try await memory.remember(type: .project, name: "Cancelled Fixture", detail: "Disposable cancellation validation")
        _ = try await environment.askSuzzme("Forget everything about Project Cancelled Fixture.")
        await environment.cancelVoiceSession()
        _ = try await environment.askSuzzme("confirm")
        check(try await memory.projectID(named: "Cancelled Fixture") != nil, "cancelled Core memory proposal cannot revive through text")
        await presentationDismissalChecks(environment)
        try await conversationPresentationChecks(environment)
        print("Final UI passed: \(passed)")
        print("Final UI failed: \(failed)")
    }

    static func conversationPresentationChecks(_ environment: AppEnvironment) async throws {
        await environment.cancelVoiceSession()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var presentation = SuzzmeConversationPresentation()
        let firstOwner = UUID()
        let firstID = presentation.append(question: "What can you do?", requestID: firstOwner, now: now)
        let firstAnswer = try await environment.askSuzzme("What can you do?", requestID: firstOwner)
        check(presentation.complete(firstAnswer, entryID: firstID, requestID: firstOwner, now: now),
              "production Core answer enters only its matching conversation turn")
        let nextOwner = UUID()
        let nextID = presentation.append(question: "What can you help me with?", requestID: nextOwner, now: now)
        let nextAnswer = try await environment.askSuzzme("What can you help me with?", requestID: nextOwner)
        _ = presentation.complete(nextAnswer, entryID: nextID, requestID: nextOwner, now: now)
        check(presentation.entries.count == 2 && presentation.entries.first?.response?.text == firstAnswer.text,
              "a real follow-up keeps the earlier question and completed answer visible")
        check(presentation.entries.last?.response?.route == nextAnswer.route && nextAnswer.route == .deterministic,
              "conversation attribution preserves the real Core route without a model claim")
        check(!presentation.complete(nextAnswer, entryID: firstID, requestID: nextOwner, now: now),
              "a superseding request cannot replace another turn's response")

        let interruptedOwner = UUID()
        let interruptedID = presentation.append(question: "Explain photosynthesis", requestID: interruptedOwner, now: now)
        _ = presentation.fail("Cancelled", entryID: interruptedID, requestID: interruptedOwner, cancelled: true, now: now)
        check(!presentation.complete(firstAnswer, entryID: interruptedID, requestID: interruptedOwner, now: now),
              "late model output cannot resurrect a cancelled conversation turn")
        check(presentation.retryQuestion(for: interruptedID) == "Explain photosynthesis",
              "cancelled read-only generation retains its exact question for deliberate retry")
        let mutationOwner = UUID()
        let mutationID = presentation.append(question: "Can you delete my reminder?", requestID: mutationOwner, now: now)
        _ = presentation.fail("Verification unavailable", entryID: mutationID, requestID: mutationOwner, now: now)
        check(presentation.retryQuestion(for: mutationID) == nil,
              "an uncertain mutation is editable but never offered as automatic retry")
        let confirmationOwner = UUID()
        let confirmationID = presentation.append(question: "Confirm the reviewed action", requestID: confirmationOwner, now: now)
        _ = presentation.fail("Action changed", entryID: confirmationID, requestID: confirmationOwner, now: now)
        check(presentation.retryQuestion(for: confirmationID) == nil,
              "a failed confirmation cannot replay an old action approval")
        let restrictedID = presentation.append(question: "My password is disposable-validation-secret", requestID: UUID(), now: now)
        check(presentation.entries.first(where: { $0.id == restrictedID })?.question == "Restricted input was omitted.",
              "conversation history never extends retention of restricted voice input")

        for _ in 0..<SessionMemoryEngine.defaultMaximumTurns {
            _ = presentation.append(question: "What can you do?", requestID: UUID(), now: now)
        }
        check(presentation.entries.count == SessionMemoryEngine.defaultMaximumTurns / 2
              && !presentation.entries.contains(where: { $0.id == firstID }),
              "visible exchanges stay within the existing Core session-turn bound")
        presentation.purgeExpired(now: now.addingTimeInterval(SessionMemoryEngine.defaultLifetime + 1))
        check(presentation.entries.isEmpty, "conversation projection expires with the existing Core session policy")
        let clearedOwner = UUID()
        let clearedID = presentation.append(question: "What can you do?", requestID: clearedOwner, now: now)
        presentation.clear()
        check(!presentation.complete(firstAnswer, entryID: clearedID, requestID: clearedOwner, now: now),
              "a cleared conversation cannot receive a late owned answer")
        await environment.dismissInteraction(nextOwner)
    }

    static func presentationDismissalChecks(_ environment: AppEnvironment) async {
        var oldPresentation = AskSuzzmePresentationOwnership()
        oldPresentation.captureInitialRequest(nil)
        check(oldPresentation.requestID == nil, "an untouched Ask presentation owns no global request")
        let oldRequest = oldPresentation.beginRequest()
        check(oldPresentation.requestID == oldRequest, "typed presentation captures its request before dispatch")
        do {
            _ = try await environment.askSuzzme("What can you do?", requestID: oldRequest)
            let newerRequest = UUID()
            let newerResponse = try await environment.askSuzzme("What can you do?", requestID: newerRequest)
            oldPresentation.captureInitialRequest(newerRequest)
            check(oldPresentation.requestID == oldRequest, "navigation reappearance cannot adopt a newer global request")
            oldPresentation.finishVoiceResponse(sessionID: oldRequest, currentRequestID: newerRequest)
            check(oldPresentation.requestID == oldRequest, "a stale voice revision cannot adopt an arbitrary current request")
            await environment.dismissInteraction(oldPresentation.requestID)
            check(environment.currentInteractionID == newerRequest && environment.presentedResponse == newerResponse.text,
                  "dismissing an older Ask presentation preserves the actual newer Core response")
            var passivePresentation = AskSuzzmePresentationOwnership()
            passivePresentation.captureInitialRequest(nil)
            await environment.dismissInteraction(passivePresentation.requestID)
            check(environment.currentInteractionID == newerRequest,
                  "dismissing an untouched Ask presentation cannot cancel a later global invocation")
            var currentPresentation = AskSuzzmePresentationOwnership()
            currentPresentation.captureInitialRequest(newerRequest)
            await environment.dismissInteraction(currentPresentation.requestID)
            check(environment.currentInteractionID == nil && environment.presentedResponse == nil,
                  "dismissing the owned Ask presentation still retires its actual Core response")
            let initialVoiceSession = environment.voice.sessionID
            let cancelledVoiceRequest = UUID()
            let cancelledStart = Task { await environment.invokeSuzzme(requestID: cancelledVoiceRequest) }
            cancelledStart.cancel()
            let started = await cancelledStart.value
            check(!started, "Talk dismissed before dispatch cannot invoke a microphone session")
            check(environment.currentInteractionID == nil && environment.voice.sessionID == initialVoiceSession && !environment.voice.isListening,
                  "cancelled Talk dispatch changes neither request ownership nor VoiceSessionController")
        } catch { check(false, "real presentation ownership fixture completes") }

        var voicePresentation = AskSuzzmePresentationOwnership()
        let confirmationOwner = UUID()
        let voiceRequest = voicePresentation.beginRequest(confirmationOwner: confirmationOwner)
        check(voicePresentation.requestID == voiceRequest, "local Talk captures its request before microphone suspension")
        voicePresentation.finishVoiceResponse(sessionID: UUID(), currentRequestID: confirmationOwner)
        check(voicePresentation.requestID == voiceRequest, "foreign voice sessions cannot restore a presentation confirmation")
        voicePresentation.finishVoiceResponse(sessionID: voiceRequest, currentRequestID: UUID())
        check(voicePresentation.requestID == voiceRequest, "superseding global requests cannot steal local Talk ownership")
        voicePresentation.finishVoiceResponse(sessionID: voiceRequest, currentRequestID: confirmationOwner)
        check(voicePresentation.requestID == confirmationOwner,
              "an owned voice confirmation restores its known original Core request")
        var attachedVoicePresentation = AskSuzzmePresentationOwnership()
        attachedVoicePresentation.captureInitialRequest(voiceRequest, confirmationOwner: confirmationOwner)
        attachedVoicePresentation.finishVoiceResponse(sessionID: voiceRequest, currentRequestID: confirmationOwner)
        check(attachedVoicePresentation.requestID == confirmationOwner,
              "Ask initially displaying an active voice confirmation retains original action ownership")
        let typedFollowUp = attachedVoicePresentation.beginRequest()
        attachedVoicePresentation.finishVoiceResponse(sessionID: typedFollowUp, currentRequestID: confirmationOwner)
        check(attachedVoicePresentation.requestID == typedFollowUp,
              "a typed follow-up drops old voice confirmation ownership")
    }
}
