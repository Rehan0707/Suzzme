import Foundation
import Observation
import AVFoundation
import Speech

@MainActor @Observable
final class VoiceSessionController: NSObject {
    enum Permission: Sendable { case notDetermined, authorized, denied, restricted, unavailable }
    private let assistant: AssistantStateController
    private let engine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private let recognizer = SFSpeechRecognizer()
    private var tapInstalled = false
    private var startingSessionID: UUID?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var activeSpeechUtteranceID: ObjectIdentifier?
    private(set) var partialTranscript = ""
    private(set) var finalTranscript: String?
    private(set) var isListening = false
    private(set) var message: String?
    private(set) var sessionID = UUID()
    private(set) var finalizedSessionID: UUID?
    private(set) var completedBriefingID: UUID?
    private(set) var interruptedBriefingID: UUID?
    private(set) var briefingLifecycleRevision = UUID()
    private var activeBriefingID: UUID?
    private var transcriptFinalizer = VoiceTranscriptFinalizer()
    private let defaults: UserDefaults
    private var voiceIdentifier: String {
        didSet { defaults.set(voiceIdentifier, forKey: "suzzme.voice.identifier") }
    }
    var speaksResponses: Bool {
        didSet { defaults.set(speaksResponses, forKey: "suzzme.voice.speaksResponses") }
    }

    init(assistant: AssistantStateController, defaults: UserDefaults = .standard) {
        self.assistant = assistant
        self.defaults = defaults
        self.voiceIdentifier = defaults.string(forKey: "suzzme.voice.identifier") ?? ""
        self.speaksResponses = defaults.object(forKey: "suzzme.voice.speaksResponses") as? Bool ?? true
        super.init()
        synthesizer.delegate = self
        #if os(iOS)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioInterruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        #endif
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    #if os(iOS)
    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard isListening else { return }
        cancel()
        message = "Listening stopped because audio was interrupted."
    }
    #endif

    var microphonePermission: Permission {
        switch AVAudioApplication.shared.recordPermission { case .undetermined: .notDetermined; case .granted: .authorized; case .denied: .denied; @unknown default: .unavailable }
    }
    var speechPermission: Permission {
        switch SFSpeechRecognizer.authorizationStatus() { case .notDetermined: .notDetermined; case .authorized: .authorized; case .denied: .denied; case .restricted: .restricted; @unknown default: .unavailable }
    }
    var availableVoices: [AVSpeechSynthesisVoice] { AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(Locale.current.language.languageCode?.identifier ?? "en") }.prefix(8).map { $0 } }
    var selectedVoiceIdentifier: String? { voiceIdentifier.isEmpty ? nil : voiceIdentifier }

    func beginSession(id: UUID = UUID()) -> UUID {
        teardown()
        startingSessionID = nil
        sessionID = id
        finalizedSessionID = nil
        stopSpeech(interruptBriefing: true)
        finalTranscript = nil; partialTranscript = ""; message = nil; transcriptFinalizer.reset()
        return sessionID
    }

    func start(sessionID: UUID) async {
        guard sessionID == self.sessionID, !isListening, startingSessionID != sessionID else { return }
        startingSessionID = sessionID
        defer { if startingSessionID == sessionID { startingSessionID = nil } }
        guard await authorize(sessionID: sessionID), sessionID == self.sessionID else { return }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { fail("On-device speech recognition isn’t available right now. You can type instead."); return }
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            self.request = request
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else {
                fail("No microphone input is available. You can type instead.")
                return
            }
            input.removeTap(onBus: 0)
            try Self.installRecognitionTap(on: input, format: format, request: request)
            tapInstalled = true
            engine.prepare(); try engine.start()
            isListening = true; assistant.transition(to: .listening)
            recognitionTask = Self.makeRecognitionTask(
                recognizer: recognizer,
                request: request,
                sessionID: sessionID,
                owner: self
            )
        } catch { fail("I couldn’t start listening.") }
    }

    /// AVAudioEngine invokes tap blocks on its realtime queue. Defining the
    /// block in a nonisolated helper prevents accidental MainActor inheritance.
    nonisolated private static func installRecognitionTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest
    ) throws {
        if #available(iOS 27.0, macOS 27.0, *) {
            try input.__installTap(onBus: 0, bufferSize: 1024, format: format, error: ()) { buffer, _ in
                request.append(buffer)
            }
        } else {
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
        }
    }

    /// Speech recognition callbacks also arrive on an arbitrary queue. Only
    /// the nested MainActor task may touch observable session state.
    nonisolated private static func makeRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        sessionID: UUID,
        owner: VoiceSessionController
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { [weak owner] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let hasError = error != nil
            Task { @MainActor in
                owner?.handleRecognition(
                    transcript: transcript,
                    isFinal: isFinal,
                    hasError: hasError,
                    sessionID: sessionID
                )
            }
        }
    }

    private func handleRecognition(
        transcript: String?,
        isFinal: Bool,
        hasError: Bool,
        sessionID: UUID
    ) {
        guard self.sessionID == sessionID else { return }
        if let transcript {
            guard transcript.count <= VoiceTranscriptFinalizer.maximumCharacters else {
                cancel()
                message = "That request was too long. Please try a shorter request."
                return
            }
            partialTranscript = transcript
            if isFinal { finish(transcript) }
        }
        if hasError && isListening { fail("I couldn’t transcribe that.") }
    }

    func stop() { finish(partialTranscript) }
    func cancel() {
        startingSessionID = nil
        sessionID = UUID() // Retire callbacks already queued by the recognition task.
        teardown()
        stopSpeech(interruptBriefing: true)
        partialTranscript = ""
        finalTranscript = nil
        finalizedSessionID = nil
        transcriptFinalizer.reset()
        assistant.reset()
    }
    private var stateAfterSpeech: SuzzmeAssistantState = .success

    func speak(_ text: String, then state: SuzzmeAssistantState = .success) {
        guard speaksResponses, !text.isEmpty else { return }
        stopSpeech(interruptBriefing: true); stateAfterSpeech = state; assistant.transition(to: .speaking)
        let utterance = AVSpeechUtterance(string: text); utterance.rate = 0.47
        if let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) { utterance.voice = voice }
        activeSpeechUtteranceID = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }

    func speakBriefing(_ text: String, id: UUID) {
        guard speaksResponses, !text.isEmpty else { return }
        stopSpeech(interruptBriefing: true)
        activeBriefingID = id
        stateAfterSpeech = .success
        assistant.transition(to: .speaking)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.47
        if let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) { utterance.voice = voice }
        activeSpeechUtteranceID = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }

    func stopSpeech(interruptBriefing: Bool = true) {
        if interruptBriefing, let activeBriefingID {
            interruptedBriefingID = activeBriefingID
            self.activeBriefingID = nil
            briefingLifecycleRevision = UUID()
        }
        activeSpeechUtteranceID = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }
    func acknowledgeBriefingLifecycle() {
        completedBriefingID = nil
        interruptedBriefingID = nil
    }
    func selectVoice(_ voice: AVSpeechSynthesisVoice) { voiceIdentifier = voice.identifier }
    func preview(_ voice: AVSpeechSynthesisVoice) { stopSpeech(); let utterance = AVSpeechUtterance(string: "Hey, I’m Suzzme. I’m ready when you are."); utterance.voice = voice; utterance.rate = 0.47; synthesizer.speak(utterance) }

    private func authorize(sessionID: UUID) async -> Bool {
        if microphonePermission == .notDetermined { _ = await AVAudioApplication.requestRecordPermission() }
        guard self.sessionID == sessionID, !Task.isCancelled else { return false }
        if speechPermission == .notDetermined { _ = await Self.requestSpeechAuthorization() }
        guard self.sessionID == sessionID, !Task.isCancelled else { return false }
        guard microphonePermission == .authorized else { fail("Microphone access is off."); return false }
        guard speechPermission == .authorized else { fail("Speech recognition access is off."); return false }
        return true
    }

    /// Speech invokes its authorization callback on an arbitrary queue. Keep
    /// that callback outside this MainActor-isolated type, then return to the
    /// caller's actor after the continuation resumes.
    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
    private func finish(_ transcript: String) {
        guard !transcriptFinalizer.hasFinalized else { return }
        teardown()
        guard let text = transcriptFinalizer.acceptFinal(transcript) else { fail("I couldn’t hear anything."); return }
        finalTranscript = text; finalizedSessionID = sessionID; assistant.transition(to: .transcribing)
    }
    private func teardown() {
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); request = nil; recognitionTask?.cancel(); recognitionTask = nil; isListening = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
    private func fail(_ text: String) { teardown(); message = text; assistant.fail(message: text) }
}

extension VoiceSessionController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.activeSpeechUtteranceID == utteranceID, self.assistant.state == .speaking else { return }
            self.activeSpeechUtteranceID = nil
            if let briefingID = self.activeBriefingID {
                self.completedBriefingID = briefingID
                self.activeBriefingID = nil
                self.briefingLifecycleRevision = UUID()
            }
            if self.stateAfterSpeech == .awaitingConfirmation { self.assistant.transition(to: .awaitingConfirmation) }
            else { self.assistant.complete() }
        }
    }
}
