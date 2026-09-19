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
    private var recognitionTask: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var activeSpeechUtteranceID: ObjectIdentifier?
    private(set) var partialTranscript = ""
    private(set) var finalTranscript: String?
    private(set) var isListening = false
    private(set) var message: String?
    private(set) var sessionID = UUID()
    private(set) var finalizedSessionID: UUID?
    private var transcriptFinalizer = VoiceTranscriptFinalizer()
    private var voiceIdentifier: String { get { UserDefaults.standard.string(forKey: "suzzme.voice.identifier") ?? "" } set { UserDefaults.standard.set(newValue, forKey: "suzzme.voice.identifier") } }
    var speaksResponses: Bool { get { UserDefaults.standard.object(forKey: "suzzme.voice.speaksResponses") as? Bool ?? true } set { UserDefaults.standard.set(newValue, forKey: "suzzme.voice.speaksResponses") } }

    init(assistant: AssistantStateController) {
        self.assistant = assistant
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

    func beginSession(id: UUID = UUID()) -> UUID {
        sessionID = id
        finalizedSessionID = nil
        stopSpeech()
        finalTranscript = nil; partialTranscript = ""; message = nil; transcriptFinalizer.reset()
        return sessionID
    }

    func start(sessionID: UUID) async {
        guard sessionID == self.sessionID else { return }
        guard await authorize(), sessionID == self.sessionID else { return }
        guard let recognizer, recognizer.isAvailable else { fail("Speech recognition isn’t available right now."); return }
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            self.request = request
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in request.append(buffer) }
            engine.prepare(); try engine.start()
            isListening = true; assistant.transition(to: .listening)
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self, sessionID] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.sessionID == sessionID else { return }
                    if let result { self.partialTranscript = result.bestTranscription.formattedString; if result.isFinal { self.finish(result.bestTranscription.formattedString) } }
                    if error != nil && self.isListening { self.fail("I couldn’t transcribe that.") }
                }
            }
        } catch { fail("I couldn’t start listening.") }
    }

    func stop() { finish(partialTranscript) }
    func cancel() {
        teardown()
        stopSpeech()
        partialTranscript = ""
        finalTranscript = nil
        finalizedSessionID = nil
        transcriptFinalizer.reset()
        assistant.reset()
    }
    func speak(_ text: String) {
        guard speaksResponses, !text.isEmpty else { return }
        stopSpeech(); assistant.transition(to: .speaking)
        let utterance = AVSpeechUtterance(string: text); utterance.rate = 0.47
        if let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) { utterance.voice = voice }
        activeSpeechUtteranceID = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }
    func stopSpeech() {
        activeSpeechUtteranceID = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }
    func selectVoice(_ voice: AVSpeechSynthesisVoice) { voiceIdentifier = voice.identifier }
    func preview(_ voice: AVSpeechSynthesisVoice) { stopSpeech(); let utterance = AVSpeechUtterance(string: "Hey, I’m Suzzme. I’m ready when you are."); utterance.voice = voice; utterance.rate = 0.47; synthesizer.speak(utterance) }

    private func authorize() async -> Bool {
        if microphonePermission == .notDetermined { _ = await AVAudioApplication.requestRecordPermission() }
        if speechPermission == .notDetermined { _ = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } } }
        guard microphonePermission == .authorized else { fail("Microphone access is off."); return false }
        guard speechPermission == .authorized else { fail("Speech recognition access is off."); return false }
        return true
    }
    private func finish(_ transcript: String) {
        guard !transcriptFinalizer.hasFinalized else { return }
        teardown()
        guard let text = transcriptFinalizer.acceptFinal(transcript) else { fail("I couldn’t hear anything."); return }
        finalTranscript = text; finalizedSessionID = sessionID; assistant.transition(to: .transcribing)
    }
    private func teardown() {
        if engine.isRunning { engine.stop() }; engine.inputNode.removeTap(onBus: 0)
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
            self.assistant.complete()
        }
    }
}
