import os

// This file is appended only to a disposable copy of AppEnvironment.swift.
// Same-file access seeds ownership without adding test APIs to the app or
// authorizing an action, microphone session, screenshot, or permission prompt.
private final class EnvironmentCancellationCheckGate: Sendable {
    private struct State {
        var started = false
        var released = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    var started: Bool { state.withLock { $0.started } }
    var released: Bool { state.withLock { $0.released } }
    func markStarted() { state.withLock { $0.started = true } }
    func release() { state.withLock { $0.released = true } }
}

extension SuzzmeCore {
    fileprivate func holdExecutorForEnvironmentCheck(_ gate: EnvironmentCancellationCheckGate) {
        gate.markStarted()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !gate.released && ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
    }
}

extension AppEnvironment {
    fileprivate func holdCoreForEnvironmentCheck(_ gate: EnvironmentCancellationCheckGate) async {
        await core.holdExecutorForEnvironmentCheck(gate)
    }

    fileprivate func seedSplitOwnershipForEnvironmentCheck(original: UUID, current: UUID) {
        let action = SuzzmeAction(type: .forgetMemory, title: "Disposable ownership fixture",
                                 risk: .consequential, status: .awaitingConfirmation)
        pendingConfirmation = (action.id, original)
        presentedAction = action
        voiceApproval = (current, action.id, original)
        activeAssistantRequestID = current
        globalPushToTalkToken = current
        transientStartOwner = current
        explicitScreenVoiceSessionID = current
        pendingScreenQuestion = (current, "Explain this screen", false)
        presentedResponse = "Disposable private response"
        let display = ScreenDisplayGeometry(displayID: 1, x: 0, y: 0, width: 800, height: 600, scaleFactor: 1)
        presentedScreenMetadata = .init(requestID: current, capturedAt: .now, display: display,
                                        pixelWidth: 800, pixelHeight: 600, activeApplicationPID: nil)
        presentedScreenGuidance = .init(requestID: current, displayID: 1, normalizedX: 0.5,
                                       normalizedY: 0.5, label: "Disposable fixture", confidence: 1)
        _ = invocation.cancel()
        _ = invocation.begin(requestID: current)
        _ = voice.beginSession(id: current)
        assistant.transition(to: .understanding)
    }

    fileprivate var transientPointersClearedForEnvironmentCheck: Bool {
        voiceApproval == nil && globalPushToTalkToken == nil && transientStartOwner == nil
            && explicitScreenVoiceSessionID == nil && pendingConfirmation == nil
    }

    fileprivate func seedExplicitScreenVoiceForEnvironmentCheck(_ id: UUID) {
        activeAssistantRequestID = id
        explicitScreenVoiceSessionID = id
        _ = invocation.cancel()
        _ = invocation.begin(requestID: id)
        _ = voice.beginSession(id: id)
    }

    fileprivate func seedPreparingVoiceForEnvironmentCheck(_ id: UUID) {
        activeAssistantRequestID = id
        globalPushToTalkToken = id
        transientStartOwner = id
        _ = invocation.cancel()
        _ = invocation.begin(requestID: id)
        _ = voice.beginSession(id: id)
        presentedResponse = "Getting ready to listen…"
        assistant.transition(to: .understanding)
    }

    fileprivate func seedSummaryPresentationForEnvironmentCheck(
        requestID: UUID?, voiceSessionID: UUID, preparingOwner: UUID? = nil,
        state: SuzzmeAssistantState = .idle
    ) {
        activeAssistantRequestID = requestID
        transientStartOwner = preparingOwner
        globalPushToTalkToken = preparingOwner
        _ = voice.beginSession(id: voiceSessionID)
        assistant.transition(to: state)
    }

    fileprivate func cancelSummaryPresentationForEnvironmentCheck(requestID: UUID?, voiceSessionID: UUID) {
        guard ownsSummaryPresentation(requestID: requestID, voiceSessionID: voiceSessionID) else { return }
        assistant.reset()
    }

    fileprivate func attemptSummaryCompletionForEnvironmentCheck(requestID: UUID?, voiceSessionID: UUID) {
        guard ownsSummaryPresentation(requestID: requestID, voiceSessionID: voiceSessionID) else { return }
        assistant.complete(message: "Disposable summary finished.")
    }

    fileprivate func ownsSummaryPresentationForEnvironmentCheck(requestID: UUID?, voiceSessionID: UUID) -> Bool {
        ownsSummaryPresentation(requestID: requestID, voiceSessionID: voiceSessionID)
    }
}

@main @MainActor struct GlobalEnvironmentChecks {
    static var passed = 0
    static var failed = 0

    static func check(_ value: Bool, _ label: String) {
        print("\(value ? "PASS" : "FAIL") \(label)")
        if value { passed += 1 } else { failed += 1 }
    }

    static func main() async throws {
        guard let domain = Bundle.main.bundleIdentifier, domain.hasPrefix("dev.suzzme.GlobalEnv") else {
            print("FAIL environment checks require the isolated copied app namespace")
            exit(1)
        }
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.set(false, forKey: "suzzme.voice.speaksResponses")
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmeGlobalEnv-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let environment = AppEnvironment(watchedLinkURL: folder.appendingPathComponent("watched.json"))
        environment.voice.speaksResponses = false
        environment.screenPreferences.mode = .askWhenNeeded
        check(!environment.voice.speaksResponses && !environment.voice.isListening,
              "isolated environment never starts microphone capture or speech")

        let consentA = UUID()
        let screenResponse = try await environment.askSuzzme("Explain this screen", requestID: consentA)
        check(environment.screenConsentRequestID == consentA && environment.currentInteractionID == consentA,
              "actual screen question creates consent owned by the current request")
        check(screenResponse.action == nil && environment.presentedAction == nil && environment.presentedActionOwner == nil,
              "screen consent carries no action authorization")
        check(environment.presenceState == .awaitingConfirmation && environment.presentedResponse == environment.screenConsentMessage,
              "screen consent appears as an explicit confirmation")
        check(screenResponse.extractedItems.isEmpty && environment.lastUnderstandingResult == nil
              && environment.activityItems.isEmpty && environment.presentedScreenMetadata == nil
              && environment.presentedScreenGuidance == nil,
              "consent returns before Core extraction, screen capture, or guidance")

        let originalRevision = environment.lastVoiceResponseRevision
        await environment.respondToScreenConsent(requestID: UUID(), granted: true)
        check(environment.screenConsentRequestID == consentA && environment.currentInteractionID == consentA
              && environment.lastVoiceResponseRevision == originalRevision,
              "foreign consent grant is ignored before any OS permission request")
        _ = environment.invocation.begin(requestID: consentA)
        await environment.respondToScreenConsent(requestID: consentA, granted: false)
        check(environment.screenConsentRequestID == nil, "owned screen denial clears the question")
        check(!environment.invocation.isActive, "owned screen denial retires its invocation")
        check(environment.presentedResponse == "I didn’t capture your screen."
              && environment.lastVoiceResponse?.text == environment.presentedResponse
              && environment.lastVoiceResponseRevision != originalRevision,
              "owned screen denial updates both visible answer and voice response revision")
        check(environment.presentedScreenMetadata == nil && environment.presentedScreenGuidance == nil
              && environment.presentedAction == nil,
              "screen denial leaves no capture metadata or actionable guidance")
        let deniedRevision = environment.lastVoiceResponseRevision
        await environment.respondToScreenConsent(requestID: consentA, granted: true)
        check(environment.lastVoiceResponseRevision == deniedRevision && environment.screenConsentRequestID == nil,
              "a delayed grant cannot revive a denied screen question")

        let consentB = UUID()
        _ = try await environment.askSuzzme("Explain this screen", requestID: consentB)
        let consentC = UUID()
        _ = try await environment.askSuzzme("What does this error mean?", requestID: consentC)
        let replacementConsentResponse = environment.presentedResponse
        await environment.respondToScreenConsent(requestID: consentB, granted: true)
        check(environment.screenConsentRequestID == consentC && environment.currentInteractionID == consentC
              && environment.presentedResponse == replacementConsentResponse,
              "superseded consent grant cannot replace the newer owned question")
        let regularRequest = UUID()
        let regularResponse = try await environment.askSuzzme("What can you do?", requestID: regularRequest)
        check(environment.screenConsentRequestID == nil && environment.currentInteractionID == regularRequest
              && environment.presentedResponse == regularResponse.text,
              "a regular request removes old screen consent")
        let regularRevision = environment.lastVoiceResponseRevision
        await environment.respondToScreenConsent(requestID: consentC, granted: true)
        check(environment.currentInteractionID == regularRequest && environment.presentedResponse == regularResponse.text
              && environment.lastVoiceResponseRevision == regularRevision && environment.screenConsentRequestID == nil,
              "late screen grant cannot act after a regular replacement request")

        let originalApproval = UUID()
        let currentInvocation = UUID()
        environment.seedSplitOwnershipForEnvironmentCheck(original: originalApproval, current: currentInvocation)
        let gate = EnvironmentCancellationCheckGate()
        let coreBlocker = Task { await environment.holdCoreForEnvironmentCheck(gate) }
        let gateStartDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !gate.started && ContinuousClock.now < gateStartDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        check(gate.started && !gate.released, "test holds Core cleanup without accessing a user capability")
        var cancellationFinished = false
        let cancellation = Task {
            await environment.cancelVoiceSession()
            cancellationFinished = true
        }
        let cleanupDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while environment.currentInteractionID != nil && ContinuousClock.now < cleanupDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        check(environment.currentInteractionID == nil && !cancellationFinished && !gate.released,
              "cancellation retires current ownership before suspended Core cleanup")
        check(!environment.invocation.isActive && environment.transientPointersClearedForEnvironmentCheck,
              "cancellation clears invocation, old approval, global token, and pending start before actor hops")
        check(environment.presentedResponse == nil && environment.screenConsentRequestID == nil
              && environment.presentedAction == nil && environment.presentedScreenMetadata == nil
              && environment.presentedScreenGuidance == nil && !environment.voice.isListening
              && environment.voice.sessionID != currentInvocation,
              "cancellation clears private presentation and retires the current voice session")
        gate.release()
        await coreBlocker.value
        await cancellation.value
        check(cancellationFinished && environment.currentInteractionID == nil
              && !environment.invocation.isActive && environment.transientPointersClearedForEnvironmentCheck,
              "split original-approval and current-invocation ownership stays retired after cleanup")

        let freshRequest = UUID()
        let freshResponse = try await environment.askSuzzme("What can you do?", requestID: freshRequest)
        let freshRevision = environment.lastVoiceResponseRevision
        do {
            _ = try await environment.submitVoiceTranscript("Explain this screen", sessionID: currentInvocation)
            check(false, "old final transcript cannot submit after a fresh request owns presentation")
        } catch is CancellationError {
            check(true, "old final transcript cannot submit after a fresh request owns presentation")
        } catch {
            check(false, "old final transcript cannot submit after a fresh request owns presentation")
        }
        await environment.respondToScreenConsent(requestID: currentInvocation, granted: true)
        check(environment.currentInteractionID == freshRequest && environment.presentedResponse == freshResponse.text
              && environment.lastVoiceResponseRevision == freshRevision && environment.screenConsentRequestID == nil,
              "cancelled consent and final callbacks cannot overwrite fresh output")

        let screenOwner = UUID()
        environment.seedSplitOwnershipForEnvironmentCheck(original: UUID(), current: screenOwner)
        let ownedMetadata = environment.presentedScreenMetadata
        let ownedGuidance = environment.presentedScreenGuidance
        let ownedAction = environment.presentedAction
        let ownedVoice = environment.voice.sessionID
        let ownedResponse = environment.presentedResponse
        let ownedState = environment.presenceState
        await environment.invalidateScreenContext(requestID: UUID())
        check(environment.presentedScreenMetadata == ownedMetadata && environment.presentedScreenGuidance == ownedGuidance,
              "foreign Space cleanup cannot clear current screen metadata or guidance")
        await environment.invalidateScreenContext(requestID: screenOwner)
        check(environment.presentedScreenMetadata == nil && environment.presentedScreenGuidance == nil
              && environment.currentInteractionID == screenOwner && environment.voice.sessionID == ownedVoice
              && environment.presentedAction?.id == ownedAction?.id && environment.presentedResponse == ownedResponse
              && environment.presenceState == ownedState && environment.invocation.isActive,
              "owned Space cleanup removes only screen evidence without cancelling voice, action or Presence")
        environment.seedSplitOwnershipForEnvironmentCheck(original: UUID(), current: screenOwner)
        await environment.invalidateScreenContext()
        check(environment.presentedScreenMetadata == nil && environment.presentedScreenGuidance == nil
              && environment.currentInteractionID == screenOwner,
              "intentional all-context invalidation remains available for privacy and lifecycle boundaries")
        await environment.cancelVoiceSession()

        let explicitVoice = UUID()
        environment.seedExplicitScreenVoiceForEnvironmentCheck(explicitVoice)
        let dayResponse = try await environment.submitVoiceTranscript("What do I have tomorrow?", sessionID: explicitVoice)
        check(environment.screenConsentRequestID == nil && environment.presentedScreenMetadata == nil
              && environment.presentedScreenGuidance == nil && !dayResponse.text.contains("Screen Recording"),
              "an ordinary day question in explicit-screen voice still avoids screen consent and capture")
        check(!environment.invocation.isActive && environment.lastVoiceResponse?.text == dayResponse.text,
              "ordinary voice response completes through the existing final transcript pipeline")
        await environment.cancelVoiceSession()
        let earlyRelease = UUID()
        environment.seedPreparingVoiceForEnvironmentCheck(earlyRelease)
        await environment.endGlobalPushToTalk(token: earlyRelease)
        check(environment.presentedResponse == environment.voice.message
              && environment.presentedResponse != "Getting ready to listen…" && !environment.invocation.isActive,
              "release before capture replaces owned preparation with the actual voice failure")
        let laterRequest = UUID()
        environment.seedPreparingVoiceForEnvironmentCheck(laterRequest)
        await environment.endGlobalPushToTalk(token: earlyRelease)
        check(environment.currentInteractionID == laterRequest && environment.presentedResponse == "Getting ready to listen…"
              && environment.invocation.isActive,
              "late release cannot clear the newer request's wake presentation")
        await environment.cancelVoiceSession()

        let summarySession = UUID()
        environment.seedSummaryPresentationForEnvironmentCheck(requestID: nil, voiceSessionID: summarySession)
        check(environment.ownsSummaryPresentationForEnvironmentCheck(requestID: nil, voiceSessionID: summarySession),
              "unchanged idle presentation accepts its bounded summary preparation")
        let summaryRequest = UUID()
        environment.seedSummaryPresentationForEnvironmentCheck(requestID: summaryRequest, voiceSessionID: summarySession)
        check(environment.ownsSummaryPresentationForEnvironmentCheck(requestID: summaryRequest, voiceSessionID: summarySession),
              "unchanged request and voice session retain summary presentation ownership")

        let replacementSession = UUID()
        environment.seedSummaryPresentationForEnvironmentCheck(requestID: summaryRequest, voiceSessionID: replacementSession)
        check(!environment.ownsSummaryPresentationForEnvironmentCheck(requestID: summaryRequest, voiceSessionID: summarySession),
              "new voice session retires an earlier summary preparation even with the same assistant request")
        let replacementRequest = UUID()
        environment.seedSummaryPresentationForEnvironmentCheck(requestID: replacementRequest, voiceSessionID: summarySession)
        check(!environment.ownsSummaryPresentationForEnvironmentCheck(requestID: summaryRequest, voiceSessionID: summarySession),
              "new assistant request retires summary presentation even with the same voice session")

        environment.seedSummaryPresentationForEnvironmentCheck(requestID: summaryRequest, voiceSessionID: summarySession,
                                                               preparingOwner: summaryRequest, state: .understanding)
        check(!environment.ownsSummaryPresentationForEnvironmentCheck(requestID: summaryRequest, voiceSessionID: summarySession),
              "transient voice preparation prevents summary presentation from claiming its phase")
        environment.seedSummaryPresentationForEnvironmentCheck(requestID: replacementRequest, voiceSessionID: replacementSession,
                                                               state: .listening)
        environment.attemptSummaryCompletionForEnvironmentCheck(requestID: summaryRequest, voiceSessionID: summarySession)
        check(environment.presenceState == .listening && environment.currentInteractionID == replacementRequest,
              "old summary completion cannot overwrite the newer listening owner")
        await environment.cancelVoiceSession()
        let cancelledSummarySession = UUID()
        environment.seedSummaryPresentationForEnvironmentCheck(requestID: nil, voiceSessionID: cancelledSummarySession, state: .gatheringContext)
        let cancelledTask = Task { @MainActor in
            while !Task.isCancelled { await Task.yield() }
            environment.cancelSummaryPresentationForEnvironmentCheck(requestID: nil, voiceSessionID: cancelledSummarySession)
        }
        cancelledTask.cancel()
        await cancelledTask.value
        check(environment.presenceState == .idle, "cancelled summary can reset its own preparation phase without getting stuck")
        print("Global environment acceptance: \(passed) passed / \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
