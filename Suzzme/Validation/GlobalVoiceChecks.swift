// global-voice-check.sh appends this acceptance-only extension to a temporary
// copy of the real controller. No test hooks or synthetic recognition API are
// compiled into Suzzme. These checks never open a microphone or speak audio.
private struct VoiceRecognitionCheckOwner {
    let sessionID: UUID
    let recognitionID: UUID
}

extension VoiceSessionController {
    fileprivate func seedRecognitionForCheck(
        id: UUID = UUID(), waitsForRelease: Bool = true
    ) -> VoiceRecognitionCheckOwner {
        _ = beginSession(id: id)
        let recognitionID = UUID()
        self.waitsForRelease = waitsForRelease
        request = Self.makeRecognitionRequest()
        recognitionOwnerID = recognitionID
        isListening = true
        assistant.transition(to: .listening)
        return VoiceRecognitionCheckOwner(sessionID: id, recognitionID: recognitionID)
    }

    fileprivate var currentRecognitionForCheck: VoiceRecognitionCheckOwner {
        VoiceRecognitionCheckOwner(sessionID: sessionID, recognitionID: recognitionOwnerID ?? UUID())
    }

    fileprivate var currentRecognitionRequestForCheck: SFSpeechAudioBufferRecognitionRequest? { request }

    fileprivate func seedSpeechForCheck(preview: Bool = false, then state: SuzzmeAssistantState = .success, briefing: UUID? = nil, started: Bool = true) -> [AVSpeechUtterance] {
        stopSpeech()
        stateAfterSpeech = state
        activeBriefingID = briefing
        let utterances = [AVSpeechUtterance(string: "First sentence."), AVSpeechUtterance(string: "Second sentence.")]
        speechLength = utterances.reduce(0) { $0 + $1.speechString.utf16.count }
        var offset = 0
        for utterance in utterances {
            speechSegments[ObjectIdentifier(utterance)] = SpeechSegment(offset: offset, length: utterance.speechString.utf16.count, isPreview: preview)
            offset += utterance.speechString.utf16.count
        }
        activeSpeechUtteranceID = ObjectIdentifier(utterances[0])
        isPreviewing = preview
        if !preview && started { assistant.transition(to: .speaking) }
        return utterances
    }

    fileprivate func emitRecognitionForCheck(
        _ text: String?, final: Bool = false, error: Bool = false, owner: VoiceRecognitionCheckOwner
    ) {
        handleRecognition(
            transcript: text, isFinal: final, hasError: error,
            sessionID: owner.sessionID, recognitionID: owner.recognitionID
        )
    }

    fileprivate func emitLevelForCheck(_ level: Double, owner: VoiceRecognitionCheckOwner) {
        updateAudioLevel(level, sessionID: owner.sessionID, recognitionID: owner.recognitionID)
    }

    fileprivate var recognitionResourcesReleasedForCheck: Bool {
        request == nil && recognitionTask == nil && recognitionOwnerID == nil && finalizationTask == nil
    }

    fileprivate func seedPendingStartForCheck() -> UUID {
        let id = beginSession()
        startingSessionID = id
        return id
    }

    fileprivate func ownsPendingStartForCheck(_ id: UUID) -> Bool { ownsStart(id) }

    fileprivate var queuedSpeechIDsForCheck: Set<ObjectIdentifier> { Set(speechSegments.keys) }
    fileprivate var activeSpeechIDForCheck: ObjectIdentifier? { activeSpeechUtteranceID }
    fileprivate var hasNaturalSpeechForCheck: Bool { neuralOwnerID != nil || neuralPlayer != nil || neuralTask != nil || neuralProgressTask != nil }
    fileprivate func interruptAudioForCheck() { interruptAudio() }
    fileprivate func seedNaturalPlaybackForCheck(briefing: UUID) {
        stopSpeech()
        neuralOwnerID = UUID()
        activeBriefingID = briefing
        isSpeaking = true
        speechProgress = 0.4
        assistant.transition(to: .speaking)
    }
    fileprivate func seedNaturalPreparationForCheck() {
        stopSpeech()
        neuralOwnerID = UUID()
        isPreparingSpeech = true
        assistant.transition(to: .reasoning)
        speechPreparationRevision = assistant.revision
    }

    fileprivate func postEngineConfigurationForCheck(ownEngine: Bool = true) {
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: ownEngine ? engine : AVAudioEngine())
    }

    fileprivate var engineIdentityForCheck: ObjectIdentifier { ObjectIdentifier(engine) }
    fileprivate var engineInvalidatedForCheck: Bool { engineIsInvalidated }

    fileprivate func invalidateEngineForCheck(_ identity: ObjectIdentifier) -> Bool {
        invalidateEngine(identity: identity)
    }

    fileprivate func emitRetiredEngineConfigurationForCheck(_ retired: AVAudioEngine) {
        // Exercise an already-delivering notification after its observer was
        // removed. The production identity lock must reject it immediately.
        handleAudioEngineConfigurationChange(Notification(name: .AVAudioEngineConfigurationChange, object: retired))
    }

    fileprivate var engineForCheck: AVAudioEngine { engine }

    fileprivate func prepareCaptureEngineForCheck(_ validate: (AVAudioEngine) throws -> Void) throws {
        try prepareCaptureEngine(validate: validate)
    }

    fileprivate static func acceptsMicrophoneFormatForCheck(
        hardwareRate: Double, hardwareChannels: AVAudioChannelCount,
        busRate: Double, busChannels: AVAudioChannelCount
    ) -> Bool {
        (try? validateMicrophoneFormat(hardwareRate: hardwareRate, hardwareChannels: hardwareChannels,
                                      busRate: busRate, busChannels: busChannels)) != nil
    }

    fileprivate static func staleMicrophoneFormatErrorForCheck() -> Error { MicrophoneInputError.changed }

    fileprivate func startOfflineEngineForCheck() throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1) else {
            throw NSError(domain: "VoiceChecks", code: 1)
        }
        _ = engine.outputNode
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1_024)
        try engine.start()
    }

    fileprivate func stopOfflineEngineForCheck() {
        engine.stop()
        engine.disableManualRenderingMode()
    }

    fileprivate func authorizeForCheck(
        id: UUID, microphoneStatus: () -> Permission, speechStatus: () -> Permission,
        requestMicrophone: () async -> Void, requestSpeech: () async -> Void
    ) async -> Bool {
        await authorize(sessionID: id, microphoneStatus: microphoneStatus, speechStatus: speechStatus,
                        requestMicrophone: requestMicrophone, requestSpeech: requestSpeech)
    }
}

private actor InterruptedLocalSpeech {
    private var continuation: CheckedContinuation<Data, Never>?
    private(set) var started = false
    private(set) var returned = false
    func render(_ text: String) async -> Data {
        let data = await withCheckedContinuation { continuation in
            self.continuation = continuation
            started = true
        }
        returned = true
        return data
    }
    func release() { continuation?.resume(returning: Data()); continuation = nil }
}

@main @MainActor struct GlobalVoiceChecks {
    static var passed = 0
    static var failed = 0

    static func check(_ value: Bool, _ label: String) {
        print("\(value ? "PASS" : "FAIL") \(label)")
        if value { passed += 1 } else { failed += 1 }
    }

    private static func checkAudioInterruptionLifecycle() async {
        let domain = "dev.suzzme.voice-interruption.\(UUID())"
        guard let defaults = UserDefaults(suiteName: domain) else {
            check(false, "audio interruption checks require isolated preferences")
            return
        }
        defer { defaults.removePersistentDomain(forName: domain) }
        let held = InterruptedLocalSpeech()
        let assistant = AssistantStateController()
        let voice = VoiceSessionController(assistant: assistant, defaults: defaults,
            localSpeechRenderer: { await held.render($0) })
        voice.speechEngine = .natural
        voice.previewSelectedVoice()
        for _ in 0..<100 {
            if await held.started { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        check(voice.isPreparingSpeech && voice.isPreviewing && voice.hasNaturalSpeechForCheck,
              "real natural renderer owns pending audio before playback")
        voice.interruptAudioForCheck()
        check(!voice.isPreparingSpeech && !voice.isPreviewing && !voice.hasNaturalSpeechForCheck
              && voice.message == "Speech stopped because audio was interrupted.",
              "system interruption retires natural generation and explicit preview before playback")
        let replacement = voice.seedRecognitionForCheck()
        await held.release()
        for _ in 0..<100 {
            if await held.returned { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        for _ in 0..<5 { await Task.yield() }
        check(!voice.hasNaturalSpeechForCheck && voice.queuedSpeechIDsForCheck.isEmpty
              && !voice.isSpeaking && voice.isListening && voice.sessionID == replacement.sessionID
              && assistant.state == .listening,
              "late interrupted renderer cannot start native fallback or overwrite newer listening")
        voice.interruptAudioForCheck()
        check(!voice.isListening && voice.recognitionResourcesReleasedForCheck
              && voice.sessionID != replacement.sessionID && assistant.state == .idle,
              "system interruption cancels current capture ownership without finalizing text")
        voice.seedNaturalPreparationForCheck()
        voice.interruptAudioForCheck()
        check(!voice.hasNaturalSpeechForCheck && !voice.isPreparingSpeech && assistant.state == .idle,
              "interrupted response generation clears only its owned reasoning presentation")
        voice.seedNaturalPreparationForCheck()
        assistant.transition(to: .listening)
        let newerPresentation = assistant.revision
        voice.interruptAudioForCheck()
        check(!voice.hasNaturalSpeechForCheck && !voice.isPreparingSpeech && assistant.state == .listening
              && assistant.revision == newerPresentation,
              "interrupted generation cannot clear a newer presentation on the same assistant")
        let briefing = UUID()
        voice.seedNaturalPlaybackForCheck(briefing: briefing)
        voice.interruptAudioForCheck()
        check(!voice.hasNaturalSpeechForCheck && !voice.isSpeaking && voice.speechProgress == 0
              && voice.interruptedBriefingID == briefing && voice.completedBriefingID == nil
              && assistant.state == .idle,
              "system interruption retires natural playback and marks briefing interrupted")
        let confirmationSpeech = voice.seedSpeechForCheck(then: .awaitingConfirmation)
        voice.interruptAudioForCheck()
        check(!voice.isSpeaking && voice.queuedSpeechIDsForCheck.isEmpty
              && assistant.state == .awaitingConfirmation && !confirmationSpeech.isEmpty,
              "system interruption retains the explicit confirmation after native speech stops")
        voice.cancel()
    }

    private static func checkMicrophoneEngineRecovery() async {
        check(VoiceSessionController.acceptsMicrophoneFormatForCheck(hardwareRate: 48_000, hardwareChannels: 1,
                  busRate: 48_000, busChannels: 1),
              "production microphone validation accepts matching hardware and tap formats")
        check(!VoiceSessionController.acceptsMicrophoneFormatForCheck(hardwareRate: 44_100, hardwareChannels: 1,
                  busRate: 48_000, busChannels: 1),
              "production microphone validation rejects stale bus sample rate before tap installation")
        check(!VoiceSessionController.acceptsMicrophoneFormatForCheck(hardwareRate: 48_000, hardwareChannels: 1,
                  busRate: 48_000, busChannels: 2),
              "production microphone validation rejects stale bus channel count before tap installation")
        check(!VoiceSessionController.acceptsMicrophoneFormatForCheck(hardwareRate: 0, hardwareChannels: 1,
                  busRate: 48_000, busChannels: 1)
              && !VoiceSessionController.acceptsMicrophoneFormatForCheck(hardwareRate: 48_000, hardwareChannels: 0,
                  busRate: 48_000, busChannels: 1),
              "cached usable bus format cannot conceal unavailable microphone hardware")
        check(!VoiceSessionController.acceptsMicrophoneFormatForCheck(hardwareRate: .nan, hardwareChannels: 1,
                  busRate: 48_000, busChannels: 1)
              && !VoiceSessionController.acceptsMicrophoneFormatForCheck(hardwareRate: 48_000, hardwareChannels: 1,
                  busRate: .infinity, busChannels: 1)
              && !VoiceSessionController.acceptsMicrophoneFormatForCheck(hardwareRate: 48_000, hardwareChannels: 1,
                  busRate: 0, busChannels: 0),
              "invalid or absent hardware and tap formats are rejected without touching microphone")

        let recoveryVoice = VoiceSessionController(assistant: AssistantStateController())
        let healthyEngineID = recoveryVoice.engineIdentityForCheck
        var inspectedEngineIDs: [ObjectIdentifier] = []
        do {
            try recoveryVoice.prepareCaptureEngineForCheck { inspectedEngineIDs.append(ObjectIdentifier($0)) }
            try recoveryVoice.prepareCaptureEngineForCheck { inspectedEngineIDs.append(ObjectIdentifier($0)) }
            check(inspectedEngineIDs == [healthyEngineID, healthyEngineID] && !recoveryVoice.engineInvalidatedForCheck,
                  "healthy repeated capture preparations reuse one controller-owned audio engine")
        } catch { check(false, "healthy engine preparation succeeds") }

        recoveryVoice.postEngineConfigurationForCheck(ownEngine: false)
        check(!recoveryVoice.engineInvalidatedForCheck,
              "other engine configuration cannot invalidate the owned capture engine")
        let retiredEngine = recoveryVoice.engineForCheck
        recoveryVoice.postEngineConfigurationForCheck()
        check(recoveryVoice.engineInvalidatedForCheck && recoveryVoice.engineIdentityForCheck == healthyEngineID,
              "own configuration synchronously invalidates identity without rebuilding in notification callback")
        do {
            try recoveryVoice.prepareCaptureEngineForCheck { inspectedEngineIDs.append(ObjectIdentifier($0)) }
            let recoveredEngineID = recoveryVoice.engineIdentityForCheck
            check(recoveredEngineID != healthyEngineID && !recoveryVoice.engineInvalidatedForCheck
                  && inspectedEngineIDs.last == recoveredEngineID,
                  "next capture recreates a dirty engine once on its owning actor")
            recoveryVoice.emitRetiredEngineConfigurationForCheck(retiredEngine)
            try? await Task.sleep(for: .milliseconds(10))
            check(!recoveryVoice.engineInvalidatedForCheck && recoveryVoice.engineIdentityForCheck == recoveredEngineID
                  && recoveryVoice.message == nil,
                  "queued retired-engine notification cannot invalidate or fail the replacement")
            check(!recoveryVoice.invalidateEngineForCheck(healthyEngineID) && !recoveryVoice.engineInvalidatedForCheck,
                  "retired identity cannot mark replacement dirty from another callback")
            try recoveryVoice.prepareCaptureEngineForCheck { inspectedEngineIDs.append(ObjectIdentifier($0)) }
            check(recoveryVoice.engineIdentityForCheck == recoveredEngineID,
                  "recovered healthy engine is reused instead of opening a new engine each session")
        } catch { check(false, "dirty engine recovery succeeds before microphone acquisition") }

        var formatChecks = 0
        let beforeFormatRetry = recoveryVoice.engineIdentityForCheck
        do {
            try recoveryVoice.prepareCaptureEngineForCheck { _ in
                formatChecks += 1
                if formatChecks == 1 { throw VoiceSessionController.staleMicrophoneFormatErrorForCheck() }
            }
            check(formatChecks == 2 && recoveryVoice.engineIdentityForCheck != beforeFormatRetry
                  && !recoveryVoice.engineInvalidatedForCheck,
                  "initial stale-format check rebuilds once then validates the replacement")
        } catch { check(false, "single stale format recovery succeeds") }
        formatChecks = 0
        do {
            try recoveryVoice.prepareCaptureEngineForCheck { _ in
                formatChecks += 1
                throw VoiceSessionController.staleMicrophoneFormatErrorForCheck()
            }
            check(false, "persistent microphone format mismatch must throw")
        } catch {
            check(formatChecks == 2 && recoveryVoice.engineInvalidatedForCheck,
                  "persistent format mismatch has one bounded rebuild retry without looping or opening capture")
        }
        let protectedRecognition = recoveryVoice.seedRecognitionForCheck()
        let activeEngineID = recoveryVoice.engineIdentityForCheck
        var inspectedActiveCapture = false
        do {
            try recoveryVoice.prepareCaptureEngineForCheck { _ in inspectedActiveCapture = true }
            check(false, "active capture must not rebuild its engine")
        } catch {
            check(!inspectedActiveCapture && recoveryVoice.isListening
                  && recoveryVoice.engineIdentityForCheck == activeEngineID
                  && recoveryVoice.currentRecognitionForCheck.recognitionID == protectedRecognition.recognitionID,
                  "next-capture recovery cannot rebuild or replace active recognition ownership")
        }
        recoveryVoice.stop()
        do {
            try recoveryVoice.prepareCaptureEngineForCheck { _ in inspectedActiveCapture = true }
            check(false, "finalizing capture must not rebuild its engine")
        } catch {
            check(!inspectedActiveCapture && recoveryVoice.isFinalizing
                  && recoveryVoice.engineIdentityForCheck == activeEngineID
                  && recoveryVoice.currentRecognitionForCheck.recognitionID == protectedRecognition.recognitionID,
                  "next-capture recovery cannot interrupt genuine-final waiting")
        }
        recoveryVoice.cancel()
    }

    static func main() async {
        let assistant = AssistantStateController()
        let voice = VoiceSessionController(assistant: assistant)
        var owner = voice.seedRecognitionForCheck()
        let initialRequest = voice.currentRecognitionRequestForCheck
        check(initialRequest?.taskHint == .dictation && initialRequest?.addsPunctuation == true
              && initialRequest?.shouldReportPartialResults == true && initialRequest?.requiresOnDeviceRecognition == true,
              "initial production request enables native dictation punctuation while requiring local recognition")
        voice.emitRecognitionForCheck("latest partial", owner: owner)
        voice.stop()
        check(!voice.isListening && voice.isFinalizing && voice.finalTranscript == nil,
              "release stops capture and does not promote latest partial")
        voice.emitRecognitionForCheck("updated partial after release", owner: owner)
        check(voice.partialTranscript == "updated partial after release" && voice.finalTranscript == nil,
              "partial after release cannot submit")
        voice.emitRecognitionForCheck("real final", final: true, owner: owner)
        check(voice.finalTranscript == "real final" && voice.finalizedSessionID == owner.sessionID && !voice.isFinalizing,
              "genuine final after release submits owned text")
        check(voice.recognitionResourcesReleasedForCheck && voice.audioLevel == 0,
              "successful final releases request, task, deadline, and level")
        voice.emitRecognitionForCheck("duplicate final", final: true, owner: owner)
        check(voice.finalTranscript == "real final", "duplicate final cannot replace submission")
        voice.emitRecognitionForCheck(nil, error: true, owner: owner)
        check(voice.message == nil && voice.finalTranscript == "real final",
              "late error cannot overwrite accepted final")

        owner = voice.seedRecognitionForCheck()
        voice.emitRecognitionForCheck("natural final while held", final: true, owner: owner)
        check(voice.isListening && !voice.isFinalizing && voice.finalTranscript == nil,
              "PTT natural final remains pending while shortcut held")
        voice.stop()
        check(voice.finalTranscript == "natural final while held" && voice.finalizedSessionID == owner.sessionID,
              "release submits pending genuine final")
        voice.stop()
        check(voice.message == nil, "repeated release cannot alter accepted final")

        owner = voice.seedRecognitionForCheck()
        let requestBeforeRotation = voice.currentRecognitionRequestForCheck
        voice.emitRecognitionForCheck("First final sentence.", final: true, owner: owner)
        let secondSegment = voice.currentRecognitionForCheck
        let rotatedRequest = voice.currentRecognitionRequestForCheck
        check(rotatedRequest != nil && rotatedRequest !== requestBeforeRotation
              && rotatedRequest?.taskHint == .dictation && rotatedRequest?.addsPunctuation == true
              && rotatedRequest?.shouldReportPartialResults == true && rotatedRequest?.requiresOnDeviceRecognition == true,
              "rotated production request retains native punctuation and mandatory on-device recognition")
        check(secondSegment.recognitionID != owner.recognitionID && secondSegment.sessionID == owner.sessionID,
              "early PTT final rotates segment ownership inside same physical session")
        voice.emitRecognitionForCheck("stale duplicate", final: true, owner: owner)
        check(voice.partialTranscript == "First final sentence.", "retired segment cannot append a duplicate final")
        voice.emitRecognitionForCheck("second partial", owner: secondSegment)
        check(voice.partialTranscript == "First final sentence. second partial" && voice.finalTranscript == nil,
              "continued PTT combines committed finals with display-only partial")
        voice.emitRecognitionForCheck("Second final sentence.", final: true, owner: secondSegment)
        voice.stop()
        check(voice.finalTranscript == "First final sentence. Second final sentence.",
              "release preserves every genuine final segment from held PTT")

        owner = voice.seedRecognitionForCheck()
        voice.emitRecognitionForCheck("Committed final.", final: true, owner: owner)
        let trailingSegment = voice.currentRecognitionForCheck
        voice.emitRecognitionForCheck("trailing partial", owner: trailingSegment)
        voice.stop()
        check(voice.isFinalizing && voice.finalTranscript == nil, "release with trailing partial waits for its true final")
        voice.emitRecognitionForCheck("Trailing final.", final: true, owner: trailingSegment)
        check(voice.finalTranscript == "Committed final. Trailing final.", "post-release segment final joins prior committed final")

        owner = voice.seedRecognitionForCheck()
        voice.emitRecognitionForCheck(String(repeating: "a", count: 5_990), final: true, owner: owner)
        let boundedSegment = voice.currentRecognitionForCheck
        voice.emitRecognitionForCheck("would exceed the combined bound", final: true, owner: boundedSegment)
        check(voice.finalTranscript == nil && voice.message != nil && voice.recognitionResourcesReleasedForCheck,
              "combined final segments obey the existing 6000-character bound")

        owner = voice.seedRecognitionForCheck()
        voice.emitRecognitionForCheck("Earlier final.", final: true, owner: owner)
        let unseenSegment = voice.currentRecognitionForCheck
        voice.emitLevelForCheck(0.4, owner: unseenSegment)
        voice.stop()
        check(voice.isFinalizing && voice.finalTranscript == nil,
              "measured input in rotated segment waits even before first partial arrives")
        voice.emitRecognitionForCheck("Final arriving after release.", final: true, owner: unseenSegment)
        check(voice.finalTranscript == "Earlier final. Final arriving after release.",
              "unseen trailing speech final is preserved after physical release")

        owner = voice.seedRecognitionForCheck()
        voice.emitRecognitionForCheck("Only genuine final.", final: true, owner: owner)
        let emptyTail = voice.currentRecognitionForCheck
        voice.emitLevelForCheck(0.01, owner: emptyTail)
        voice.stop()
        voice.emitRecognitionForCheck(nil, error: true, owner: emptyTail)
        check(voice.finalTranscript == "Only genuine final." && voice.message == nil,
              "empty rotated tail cannot discard earlier genuine final")

        owner = voice.seedRecognitionForCheck(waitsForRelease: false)
        voice.emitRecognitionForCheck("in-app final", final: true, owner: owner)
        check(voice.finalTranscript == "in-app final" && !voice.isListening,
              "in-app natural final remains usable")

        owner = voice.seedRecognitionForCheck(waitsForRelease: false)
        voice.emitRecognitionForCheck("Please summarize my day", owner: owner)
        try? await Task.sleep(for: .seconds(1))
        voice.emitRecognitionForCheck("Please summarize my day", owner: owner)
        try? await Task.sleep(for: .milliseconds(1100))
        check(voice.isFinalizing && !voice.isListening,
              "repeated unchanged recognition callbacks do not delay automatic end of speech")
        voice.emitRecognitionForCheck("Please summarize my day", final: true, owner: owner)
        check(voice.finalTranscript == "Please summarize my day", "automatic stop submits the final transcript")

        owner = voice.seedRecognitionForCheck()
        voice.emitRecognitionForCheck("   ", final: true, owner: owner)
        voice.stop()
        check(voice.finalTranscript == nil && voice.finalizedSessionID == nil && voice.message != nil,
              "empty genuine final safely fails")

        owner = voice.seedRecognitionForCheck()
        voice.emitRecognitionForCheck("usable partial before Done", owner: owner)
        voice.stop()
        voice.emitRecognitionForCheck("partial accompanying error", error: true, owner: owner)
        // Done/release explicitly commits the user's latest usable capture.
        // Production intentionally falls back to that candidate if Speech's
        // final callback errors or misses its bounded finalization deadline.
        check(voice.finalTranscript == "usable partial before Done" && voice.finalizedSessionID == owner.sessionID
              && !voice.isFinalizing && voice.message == nil && voice.recognitionResourcesReleasedForCheck,
              "error after explicit Done finalizes the latest owned usable partial and releases resources")
        voice.emitRecognitionForCheck("late final after error", final: true, owner: owner)
        check(voice.finalTranscript == "usable partial before Done",
              "late final after error cannot replace the already accepted Done candidate")

        owner = voice.seedRecognitionForCheck()
        voice.emitRecognitionForCheck("uncommitted partial while listening", owner: owner)
        voice.emitRecognitionForCheck(nil, error: true, owner: owner)
        check(voice.finalTranscript == nil && voice.message != nil && voice.recognitionResourcesReleasedForCheck,
              "recognition error before explicit Done never submits an uncommitted partial")
        owner = voice.seedRecognitionForCheck()
        voice.stop()
        voice.emitRecognitionForCheck(nil, error: true, owner: owner)
        check(voice.finalTranscript == nil && voice.message != nil && voice.recognitionResourcesReleasedForCheck,
              "recognition error after empty Done cannot manufacture a transcript")

        owner = voice.seedRecognitionForCheck()
        voice.emitRecognitionForCheck("timeout partial", owner: owner)
        voice.stop()
        voice.stop()
        // Allow scheduler latency under parallel builds without extending the
        // production two-second deadline or hard-coding a timer wake-up order.
        let timeoutCheckDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while voice.isFinalizing && ContinuousClock.now < timeoutCheckDeadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        check(!voice.isFinalizing && voice.finalTranscript == "timeout partial"
              && voice.finalizedSessionID == owner.sessionID && voice.message == nil,
              "bounded deadline after explicit Done finalizes the latest owned usable partial")
        check(voice.recognitionResourcesReleasedForCheck, "timeout releases recognition request and deadline")
        voice.emitRecognitionForCheck("late final after timeout", final: true, owner: owner)
        check(voice.finalTranscript == "timeout partial", "late final after deadline cannot replace accepted Done candidate")

        owner = voice.seedRecognitionForCheck()
        voice.emitRecognitionForCheck("cancel partial", owner: owner)
        voice.stop()
        voice.cancel()
        voice.emitRecognitionForCheck("late final after cancel", final: true, owner: owner)
        check(voice.finalTranscript == nil && voice.partialTranscript.isEmpty && !voice.isFinalizing && assistant.state == .idle,
              "cancellation during finalization retires callbacks and clears presentation")

        owner = voice.seedRecognitionForCheck()
        voice.stop()
        // Reusing the public request ID must still revoke the old capture's
        // callbacks. This is stricter than only checking different request IDs.
        let replacement = voice.seedRecognitionForCheck(id: owner.sessionID)
        voice.emitRecognitionForCheck("stale prior final", final: true, owner: owner)
        check(voice.sessionID == replacement.sessionID && voice.isListening && voice.finalTranscript == nil,
              "reused request ID still rejects previous capture final callbacks")
        voice.emitLevelForCheck(0.75, owner: owner)
        check(voice.audioLevel == 0, "reused request ID still rejects stale audio callbacks")
        voice.emitLevelForCheck(0.6, owner: replacement)
        check(voice.audioLevel == 0.6, "current capture receives measured scalar")
        voice.emitLevelForCheck(0.4, owner: replacement)
        check(voice.audioLevel == 0.6, "mainactor level updates are throttled")
        voice.stop()
        voice.emitLevelForCheck(0.9, owner: replacement)
        check(voice.audioLevel == 0, "release zeros level and rejects queued level update")
        voice.cancel()

        let pendingStart = voice.seedPendingStartForCheck()
        check(voice.ownsPendingStartForCheck(pendingStart), "preparing recognition owns pending start")
        voice.stop()
        check(!voice.ownsPendingStartForCheck(pendingStart) && !voice.isListening && voice.finalTranscript == nil,
              "release revokes pending authorization start")
        await voice.start(sessionID: pendingStart, waitsForRelease: true)
        check(!voice.isListening && voice.finalTranscript == nil,
              "queued start after early release cannot start microphone")
        voice.cancel()
        let synthesizer = AVSpeechSynthesizer()
        let waitingUtterances = voice.seedSpeechForCheck(started: false)
        check(!voice.isSpeaking && assistant.state != .speaking,
              "queued output does not claim speaking before the native synthesis start")
        voice.speechSynthesizer(synthesizer, didStart: waitingUtterances[0])
        await Task.yield()
        check(voice.isSpeaking && assistant.state == .speaking,
              "owned native synthesis start publishes the real speaking state")
        voice.stopSpeech()
        voice.speechSynthesizer(synthesizer, didStart: waitingUtterances[1])
        await Task.yield()
        check(!voice.isSpeaking && assistant.state != .speaking,
              "a retired queued phrase cannot revive speaking")
        var utterances = voice.seedSpeechForCheck(then: .awaitingConfirmation)
        voice.speechSynthesizer(synthesizer, didStart: utterances[0])
        voice.speechSynthesizer(synthesizer, willSpeakRangeOfSpeechString: NSRange(location: 0, length: 5), utterance: utterances[0])
        await Task.yield()
        check(voice.isSpeaking && voice.speechProgress > 0 && voice.speechProgress < 1,
              "native synthesis start and word range publish bounded owned progress")
        voice.speechSynthesizer(synthesizer, didFinish: utterances[0])
        await Task.yield()
        check(assistant.state == .speaking, "first queued phrase cannot finish the whole response")
        voice.speechSynthesizer(synthesizer, didFinish: utterances[1])
        await Task.yield()
        check(assistant.state == .awaitingConfirmation && !voice.isSpeaking,
              "last owned phrase restores confirmation presentation")

        utterances = voice.seedSpeechForCheck(then: .awaitingConfirmation)
        voice.stopSpeech()
        voice.speechSynthesizer(synthesizer, didFinish: utterances[1])
        await Task.yield()
        check(assistant.state == .awaitingConfirmation && !voice.isSpeaking && voice.speechProgress == 0,
              "queue cancellation preserves confirmation and rejects delayed speech completion")
        utterances = voice.seedSpeechForCheck(preview: true)
        voice.speechSynthesizer(synthesizer, didFinish: utterances[0])
        voice.speechSynthesizer(synthesizer, didFinish: utterances[1])
        await Task.yield()
        check(!voice.isPreviewing && assistant.state == .awaitingConfirmation,
              "owned preview completion cannot complete or reset a confirmation")
        let briefing = UUID()
        utterances = voice.seedSpeechForCheck(briefing: briefing)
        voice.speechSynthesizer(synthesizer, didCancel: utterances[0])
        await Task.yield()
        check(voice.interruptedBriefingID == briefing && voice.completedBriefingID == nil && assistant.state == .idle,
              "native owned cancellation interrupts briefing without marking completion")
        voice.cancel()

        let answerA = voice.seedSpeechForCheck(then: .awaitingConfirmation)
        voice.speechSynthesizer(synthesizer, didStart: answerA[0])
        await Task.yield()
        let answerB = voice.seedSpeechForCheck()
        voice.speechSynthesizer(synthesizer, didStart: answerB[0])
        voice.speechSynthesizer(synthesizer, willSpeakRangeOfSpeechString: NSRange(location: 0, length: 5), utterance: answerB[0])
        await Task.yield()
        let answerBQueue = Set(answerB.map { ObjectIdentifier($0) })
        let answerBProgress = voice.speechProgress
        for stale in answerA {
            voice.speechSynthesizer(synthesizer, didStart: stale)
            voice.speechSynthesizer(synthesizer, willSpeakRangeOfSpeechString: NSRange(location: 0, length: 12), utterance: stale)
            voice.speechSynthesizer(synthesizer, didFinish: stale)
            voice.speechSynthesizer(synthesizer, didCancel: stale)
        }
        try? await Task.sleep(for: .milliseconds(10))
        check(voice.queuedSpeechIDsForCheck == answerBQueue
              && voice.activeSpeechIDForCheck == ObjectIdentifier(answerB[0])
              && voice.speechProgress == answerBProgress && voice.isSpeaking && assistant.state == .speaking,
              "rapid answer replacement rejects every stale A callback without changing B queue or presentation")

        let bargeInOwner = voice.seedRecognitionForCheck()
        check(voice.queuedSpeechIDsForCheck.isEmpty && !voice.isSpeaking && voice.isListening
              && assistant.state == .listening && voice.sessionID == bargeInOwner.sessionID,
              "barge-in retires the entire answer B queue before the new listening owner begins")
        for stale in answerB {
            voice.speechSynthesizer(synthesizer, didStart: stale)
            voice.speechSynthesizer(synthesizer, willSpeakRangeOfSpeechString: NSRange(location: 0, length: 12), utterance: stale)
            voice.speechSynthesizer(synthesizer, didFinish: stale)
            voice.speechSynthesizer(synthesizer, didCancel: stale)
        }
        try? await Task.sleep(for: .milliseconds(10))
        check(voice.queuedSpeechIDsForCheck.isEmpty && voice.activeSpeechIDForCheck == nil
              && !voice.isSpeaking && voice.speechProgress == 0 && voice.isListening
              && assistant.state == .listening && voice.sessionID == bargeInOwner.sessionID,
              "late B callbacks cannot resume stale speech or overwrite the newer listening owner")
        voice.cancel()

        let toggleDomain = "dev.suzzme.voice-toggle-acceptance.\(UUID())"
        guard let toggleDefaults = UserDefaults(suiteName: toggleDomain) else {
            check(false, "voice toggle checks require isolated preferences")
            exit(1)
        }
        defer { toggleDefaults.removePersistentDomain(forName: toggleDomain) }
        let toggleAssistant = AssistantStateController()
        let toggleVoice = VoiceSessionController(assistant: toggleAssistant, defaults: toggleDefaults)
        let pendingAnswer = toggleVoice.seedSpeechForCheck(then: .awaitingConfirmation)
        toggleVoice.speaksResponses = false
        check(toggleVoice.queuedSpeechIDsForCheck.isEmpty && toggleVoice.activeSpeechIDForCheck == nil
              && !toggleVoice.isSpeaking && toggleAssistant.state == .awaitingConfirmation,
              "disabling spoken responses retires queued real speech before didStart and preserves confirmation")
        for stale in pendingAnswer {
            toggleVoice.speechSynthesizer(synthesizer, didStart: stale)
            toggleVoice.speechSynthesizer(synthesizer, willSpeakRangeOfSpeechString: NSRange(location: 0, length: 5), utterance: stale)
            toggleVoice.speechSynthesizer(synthesizer, didFinish: stale)
            toggleVoice.speechSynthesizer(synthesizer, didCancel: stale)
        }
        try? await Task.sleep(for: .milliseconds(10))
        check(toggleVoice.queuedSpeechIDsForCheck.isEmpty && !toggleVoice.isSpeaking
              && toggleVoice.speechProgress == 0 && toggleAssistant.state == .awaitingConfirmation,
              "callbacks retired by the speech setting cannot restart audio or dismiss confirmation")
        let restoredToggle = VoiceSessionController(assistant: toggleAssistant, defaults: toggleDefaults)
        check(!restoredToggle.speaksResponses && toggleDefaults.object(forKey: "suzzme.voice.speaksResponses") as? Bool == false,
              "disabled spoken-response preference persists in the isolated domain across restart")

        toggleVoice.speaksResponses = true
        let toggleBriefing = UUID()
        _ = toggleVoice.seedSpeechForCheck(briefing: toggleBriefing)
        toggleVoice.speaksResponses = false
        check(toggleVoice.queuedSpeechIDsForCheck.isEmpty && toggleVoice.interruptedBriefingID == toggleBriefing
              && toggleVoice.completedBriefingID == nil && toggleAssistant.state == .idle,
              "disabling spoken responses interrupts the active Daily Summary without marking delivery complete")

        toggleVoice.speaksResponses = true
        let togglePreview = toggleVoice.seedSpeechForCheck(preview: true)
        let togglePreviewQueue = Set(togglePreview.map { ObjectIdentifier($0) })
        toggleVoice.speaksResponses = false
        check(toggleVoice.isPreviewing && toggleVoice.queuedSpeechIDsForCheck == togglePreviewQueue
              && toggleAssistant.state == .idle,
              "disabling response narration does not cancel an intentional voice audition")
        toggleVoice.stopPreview()

        toggleVoice.speaksResponses = true
        let toggleListening = toggleVoice.seedRecognitionForCheck()
        toggleVoice.speaksResponses = false
        check(toggleVoice.isListening && toggleVoice.sessionID == toggleListening.sessionID
              && toggleVoice.queuedSpeechIDsForCheck.isEmpty && toggleAssistant.state == .listening,
              "speech preference change does not cancel or replace the current listening owner")
        toggleVoice.cancel()

        owner = voice.seedRecognitionForCheck()
        voice.emitRecognitionForCheck("unfinished microphone input", owner: owner)
        voice.postEngineConfigurationForCheck(ownEngine: false)
        try? await Task.sleep(for: .milliseconds(10))
        check(voice.isListening && voice.message == nil,
              "unrelated audio engine configuration cannot retire Suzzme capture")
        voice.postEngineConfigurationForCheck()
        try? await Task.sleep(for: .milliseconds(10))
        check(!voice.isListening && voice.recognitionResourcesReleasedForCheck
              && voice.finalTranscript == nil && voice.partialTranscript == "unfinished microphone input"
              && voice.message == "The microphone changed while listening. Please try again." && assistant.state == .error,
              "stopped owned audio engine retires capture with a readable retry and never promotes partial")
        voice.emitRecognitionForCheck("late final after hardware change", final: true, owner: owner)
        check(voice.finalTranscript == nil && voice.recognitionResourcesReleasedForCheck,
              "hardware configuration failure rejects retired recognition callbacks")

        owner = voice.seedRecognitionForCheck()
        voice.emitRecognitionForCheck("intentional stop partial", owner: owner)
        voice.stop()
        voice.postEngineConfigurationForCheck()
        try? await Task.sleep(for: .milliseconds(10))
        check(voice.isFinalizing && voice.message == nil && assistant.state == .transcribing,
              "configuration notification after intentional Stop preserves genuine-final waiting")
        voice.emitRecognitionForCheck("genuine final after intentional stop", final: true, owner: owner)

        _ = voice.seedRecognitionForCheck()
        voice.postEngineConfigurationForCheck()
        let newerCapture = voice.seedRecognitionForCheck()
        do {
            // A real offline engine validates isRunning without opening an
            // input device or playing sound; notification delivery is synthetic.
            try voice.startOfflineEngineForCheck()
            try? await Task.sleep(for: .milliseconds(10))
            check(voice.isListening && voice.sessionID == newerCapture.sessionID && voice.message == nil,
                  "delayed old configuration callback cannot cancel a newer running engine")
            voice.stopOfflineEngineForCheck()
            voice.postEngineConfigurationForCheck()
            try? await Task.sleep(for: .milliseconds(10))
            check(!voice.isListening && voice.recognitionResourcesReleasedForCheck && voice.message != nil,
                  "later actual stopped-engine state still retires the current listening owner")
        } catch {
            check(false, "offline engine starts without microphone or playback for delayed-callback regression")
            voice.stopOfflineEngineForCheck()
        }
        voice.cancel()

        await checkMicrophoneEngineRecovery()
        await checkAudioInterruptionLifecycle()

        var microphoneStatus = VoiceSessionController.Permission.denied
        var speechStatus = VoiceSessionController.Permission.notDetermined
        var permissionOrder: [String] = []
        var permissionOwner = voice.seedPendingStartForCheck()
        let retiredPermissionOwner = permissionOwner
        voice.cancel()
        let currentPermissionOwner = voice.seedPendingStartForCheck()
        var authorization = await voice.authorizeForCheck(id: retiredPermissionOwner,
            microphoneStatus: { .notDetermined }, speechStatus: { .notDetermined },
            requestMicrophone: { permissionOrder.append("microphone") },
            requestSpeech: { permissionOrder.append("speech") })
        check(!authorization && permissionOrder.isEmpty && voice.ownsPendingStartForCheck(currentPermissionOwner)
              && voice.message == nil && assistant.state == .idle,
              "already cancelled authorization entry requests no permissions and preserves replacement state")
        let cancelledPermissionTask = Task { @MainActor in
            await voice.authorizeForCheck(id: currentPermissionOwner,
                microphoneStatus: { .notDetermined }, speechStatus: { .notDetermined },
                requestMicrophone: { permissionOrder.append("microphone") },
                requestSpeech: { permissionOrder.append("speech") })
        }
        cancelledPermissionTask.cancel()
        authorization = await cancelledPermissionTask.value
        check(!authorization && permissionOrder.isEmpty && voice.ownsPendingStartForCheck(currentPermissionOwner)
              && voice.message == nil && assistant.state == .idle,
              "cancelled task with current request ID cannot request permissions or alter its owner")
        permissionOwner = voice.seedPendingStartForCheck()
        authorization = await voice.authorizeForCheck(id: permissionOwner,
            microphoneStatus: { microphoneStatus }, speechStatus: { speechStatus },
            requestMicrophone: { permissionOrder.append("microphone") },
            requestSpeech: { permissionOrder.append("speech") })
        check(!authorization && permissionOrder.isEmpty && voice.message == "Microphone access is off.",
              "already denied microphone does not request unrelated Speech permission")

        microphoneStatus = .notDetermined
        permissionOrder = []
        permissionOwner = voice.seedPendingStartForCheck()
        authorization = await voice.authorizeForCheck(id: permissionOwner,
            microphoneStatus: { microphoneStatus }, speechStatus: { speechStatus },
            requestMicrophone: { permissionOrder.append("microphone"); microphoneStatus = .denied },
            requestSpeech: { permissionOrder.append("speech") })
        check(!authorization && permissionOrder == ["microphone"] && voice.message == "Microphone access is off.",
              "microphone denial from permission response ends authorization before Speech prompt")

        microphoneStatus = .notDetermined
        speechStatus = .notDetermined
        permissionOrder = []
        permissionOwner = voice.seedPendingStartForCheck()
        authorization = await voice.authorizeForCheck(id: permissionOwner,
            microphoneStatus: { microphoneStatus }, speechStatus: { speechStatus },
            requestMicrophone: { permissionOrder.append("microphone"); microphoneStatus = .authorized },
            requestSpeech: { permissionOrder.append("speech"); speechStatus = .authorized })
        check(authorization && permissionOrder == ["microphone", "speech"] && voice.ownsPendingStartForCheck(permissionOwner),
              "production authorization requests permissions in microphone-then-Speech order for the same owner")

        microphoneStatus = .authorized
        speechStatus = .notDetermined
        permissionOwner = voice.seedPendingStartForCheck()
        authorization = await voice.authorizeForCheck(id: permissionOwner,
            microphoneStatus: { microphoneStatus }, speechStatus: { speechStatus }, requestMicrophone: {},
            requestSpeech: { microphoneStatus = .denied; speechStatus = .authorized })
        check(!authorization && voice.message == "Microphone access is off." && !voice.ownsPendingStartForCheck(permissionOwner),
              "microphone revocation during Speech authorization is rechecked before capture")

        microphoneStatus = .notDetermined
        speechStatus = .notDetermined
        permissionOrder = []
        permissionOwner = voice.seedPendingStartForCheck()
        authorization = await voice.authorizeForCheck(id: permissionOwner,
            microphoneStatus: { microphoneStatus }, speechStatus: { speechStatus },
            requestMicrophone: { permissionOrder.append("microphone"); voice.cancel(); microphoneStatus = .authorized },
            requestSpeech: { permissionOrder.append("speech") })
        check(!authorization && permissionOrder == ["microphone"] && voice.message == nil && assistant.state == .idle,
              "cancelled microphone permission continuation cannot request Speech or revive capture")

        microphoneStatus = .authorized
        speechStatus = .notDetermined
        permissionOwner = voice.seedPendingStartForCheck()
        var replacementPermissionOwner: UUID?
        authorization = await voice.authorizeForCheck(id: permissionOwner,
            microphoneStatus: { microphoneStatus }, speechStatus: { speechStatus }, requestMicrophone: {},
            requestSpeech: { replacementPermissionOwner = voice.seedPendingStartForCheck(); speechStatus = .authorized })
        check(!authorization && replacementPermissionOwner.map { voice.ownsPendingStartForCheck($0) } == true
              && voice.message == nil,
              "superseded Speech permission continuation cannot fail or authorize a replacement session")

        microphoneStatus = .authorized
        speechStatus = .denied
        permissionOrder = []
        permissionOwner = voice.seedPendingStartForCheck()
        authorization = await voice.authorizeForCheck(id: permissionOwner,
            microphoneStatus: { microphoneStatus }, speechStatus: { speechStatus },
            requestMicrophone: { permissionOrder.append("microphone") },
            requestSpeech: { permissionOrder.append("speech") })
        check(!authorization && permissionOrder.isEmpty && voice.message == "Speech recognition access is off."
              && !voice.isListening,
              "denied Speech authorization remains a local readable failure without capture or repeat prompts")
        voice.cancel()

        print("Global voice acceptance: \(passed) passed / \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
