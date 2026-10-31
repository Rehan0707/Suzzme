import Foundation
import Observation
import AVFoundation
import Speech
import NaturalLanguage
import os

@MainActor @Observable
final class VoiceSessionController: NSObject {
    /// Delivery preferences for the existing native synthesizer. These do not
    /// infer the user's emotions or create a separate assistant state machine.
    enum DeliveryStyle: String, CaseIterable, Identifiable {
        case warm, calm, natural
        var id: String { rawValue }
        var title: String {
            switch self { case .warm: "Warm"; case .calm: "Calm"; case .natural: "System" }
        }
        var description: String {
            switch self {
            case .warm: "Gentle expression and an easy conversational pace."
            case .calm: "Softer intonation, a little slower, with room between phrases."
            case .natural: "The selected Apple voice’s original delivery."
            }
        }
    }
    enum SpeechEngine: String, CaseIterable, Identifiable {
        case natural, apple, cloud
        var id: String { rawValue }
        var title: String {
            switch self { case .natural: "Natural · On-device"; case .apple: "Apple Voice"; case .cloud: "Suzzme Voice" }
        }
    }
    static var availableSpeechEngines: [SpeechEngine] {
        #if os(iOS)
        [.apple, .cloud]
        #else
        SpeechEngine.allCases
        #endif
    }
    var speechEngine: SpeechEngine {
        didSet {
            defaults.set(speechEngine.rawValue, forKey: "suzzme.voice.engine")
            if speechEngine != oldValue { stopSpeech() }
        }
    }
    var usesDeviceVoiceOnly: Bool {
        didSet {
            defaults.set(usesDeviceVoiceOnly, forKey: "suzzme.voice.deviceOnly")
            if usesDeviceVoiceOnly && speechEngine == .cloud { speechEngine = .apple }
        }
    }
    #if canImport(SuzzmeSpeechKit) && os(macOS)
    let naturalVoiceAssets = LocalVoiceAssets()
    #endif
    private let localSpeechRenderer: (@Sendable (String) async throws -> Data)?
    private var neuralTask: Task<Void, Never>?
    private var neuralOwnerID: UUID?
    private var speechPreparationRevision: UUID?
    private var neuralPlayer: AVAudioPlayer?
    private var neuralProgressTask: Task<Void, Never>?
    private(set) var isPreparingSpeech = false
    var naturalVoiceIsReady: Bool {
        if localSpeechRenderer != nil { return true }
        #if canImport(SuzzmeSpeechKit) && os(macOS)
        return naturalVoiceAssets.isReady
        #else
        return false
        #endif
    }
    enum Permission: Sendable { case notDetermined, authorized, denied, restricted, unavailable }
    private let assistant: AssistantStateController
    private var engine: AVAudioEngine
    private struct EngineConfiguration: Sendable {
        var identity: ObjectIdentifier
        var invalidated = false
    }
    // Only engine identity and invalidation cross the audio notification queue.
    private nonisolated let engineConfiguration: OSAllocatedUnfairLock<EngineConfiguration>
    private enum MicrophoneInputError: Error { case unavailable, changed }
    private let synthesizer = AVSpeechSynthesizer()
    private let recognizer = SFSpeechRecognizer()
    private var tapInstalled = false
    #if os(iOS)
    private var captureAudioSessionActive = false
    private var speechAudioSessionActive = false
    #endif
    private var startingSessionID: UUID?
    private var recognitionOwnerID: UUID?
    private var allowsSessionStart = true
    private var waitsForRelease = false
    private var pendingFinalTranscript: String?
    private var currentSegmentPartial = ""
    private var currentSegmentHasInput = false
    private var finalizationTask: Task<Void, Never>?
    private var pauseToFinishTask: Task<Void, Never>?
    private var lastAudioLevelUpdate: ContinuousClock.Instant?
    private var lastSpeechAudioAt: ContinuousClock.Instant?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var cloudRecognitionSession: (any SuzzmeStreamingTranscriptionSession)?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var activeSpeechUtteranceID: ObjectIdentifier?
    private struct SpeechSegment {
        let offset: Int
        let length: Int
        let isPreview: Bool
    }
    private var speechSegments: [ObjectIdentifier: SpeechSegment] = [:]
    private var speechLength = 0
    private var voiceInventoryRevision = UUID()
    /// Native synthesis lifecycle and word position; this is not audio amplitude.
    private(set) var isSpeaking = false
    private(set) var isPreviewing = false
    private(set) var speechProgress = 0.0
    private(set) var partialTranscript = ""
    private(set) var finalTranscript: String?
    private(set) var isListening = false
    private(set) var isFinalizing = false
    /// Measured microphone RMS, normalized to 0...1. No level is synthesized.
    private(set) var audioLevel = 0.0
    private(set) var message: String?
    private(set) var sessionID = UUID()
    private(set) var finalizedSessionID: UUID?
    private(set) var completedBriefingID: UUID?
    private(set) var interruptedBriefingID: UUID?
    private(set) var briefingLifecycleRevision = UUID()
    private var activeBriefingID: UUID?
    private var transcriptFinalizer = VoiceTranscriptFinalizer()
    private let defaults: UserDefaults
    var deliveryStyle: DeliveryStyle {
        didSet { defaults.set(deliveryStyle.rawValue, forKey: "suzzme.voice.delivery") }
    }
    private var voiceIdentifier: String {
        didSet { defaults.set(voiceIdentifier, forKey: "suzzme.voice.identifier") }
    }
    static let speechRateRange: ClosedRange<Float> = 0.38...0.62
    private var storedSpeechRate: Float
    var speechRate: Float {
        get { storedSpeechRate }
        set {
            storedSpeechRate = newValue.isFinite ? min(max(newValue, Self.speechRateRange.lowerBound), Self.speechRateRange.upperBound) : AVSpeechUtteranceDefaultSpeechRate
            defaults.set(storedSpeechRate, forKey: "suzzme.voice.rate")
        }
    }
    var automaticallyMatchesLanguage: Bool {
        didSet { defaults.set(automaticallyMatchesLanguage, forKey: "suzzme.voice.matchesLanguage") }
    }
    var speaksResponses: Bool {
        didSet {
            defaults.set(speaksResponses, forKey: "suzzme.voice.speaksResponses")
            // Retire queued answers even before native synthesis starts. An
            // explicitly requested voice preview remains independent of this.
            if !speaksResponses, speechSegments.values.contains(where: { !$0.isPreview }) || (neuralOwnerID != nil && !isPreviewing) {
                stopSpeech(interruptBriefing: true)
            }
        }
    }

    init(assistant: AssistantStateController, defaults: UserDefaults = .standard, localSpeechRenderer: (@Sendable (String) async throws -> Data)? = nil) {
        self.assistant = assistant
        self.defaults = defaults
        self.localSpeechRenderer = localSpeechRenderer
        let deviceOnly = defaults.object(forKey: "suzzme.voice.deviceOnly") as? Bool ?? true
        self.usesDeviceVoiceOnly = deviceOnly
        let storedEngine = defaults.string(forKey: "suzzme.voice.engine").flatMap(SpeechEngine.init(rawValue:)) ?? .apple
        #if os(iOS)
        let selectedEngine = storedEngine == .natural ? SpeechEngine.apple : storedEngine
        #else
        let selectedEngine = storedEngine
        #endif
        self.speechEngine = deviceOnly && selectedEngine == .cloud ? .apple : selectedEngine
        self.deliveryStyle = defaults.string(forKey: "suzzme.voice.delivery").flatMap(DeliveryStyle.init(rawValue:)) ?? .warm
        let engine = AVAudioEngine()
        self.engine = engine
        self.engineConfiguration = OSAllocatedUnfairLock(initialState: EngineConfiguration(identity: ObjectIdentifier(engine)))
        self.voiceIdentifier = defaults.string(forKey: "suzzme.voice.identifier") ?? ""
        self.speaksResponses = defaults.object(forKey: "suzzme.voice.speaksResponses") as? Bool ?? true
        let storedRate = (defaults.object(forKey: "suzzme.voice.rate") as? NSNumber)?.floatValue ?? AVSpeechUtteranceDefaultSpeechRate
        self.storedSpeechRate = storedRate.isFinite ? min(max(storedRate, Self.speechRateRange.lowerBound), Self.speechRateRange.upperBound) : AVSpeechUtteranceDefaultSpeechRate
        self.automaticallyMatchesLanguage = defaults.object(forKey: "suzzme.voice.matchesLanguage") as? Bool ?? true
        super.init()
        synthesizer.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(availableVoicesChanged), name: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil)
        observeEngineConfiguration()
        #if os(iOS)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioInterruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        #endif
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc nonisolated private func availableVoicesChanged() {
        Task { @MainActor [weak self] in self?.voiceInventoryRevision = UUID() }
    }

    @objc nonisolated private func handleAudioEngineConfigurationChange(_ notification: Notification) {
        guard let changedEngine = notification.object as? AVAudioEngine else { return }
        let identity = ObjectIdentifier(changedEngine)
        guard invalidateEngine(identity: identity) else { return }
        // Hardware format changes stop AVAudioEngine on its internal queue.
        // Invalidate synchronously; rebuild on the next start, never here.
        // A delayed notification must not retire a newer, running capture or
        // a deliberately stopped capture that is waiting for a genuine final.
        Task { @MainActor [weak self] in
            guard let self, ObjectIdentifier(self.engine) == identity,
                  self.isListening, !self.engine.isRunning else { return }
            self.fail("The microphone changed while listening. Please try again.")
        }
    }

    private func observeEngineConfiguration() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioEngineConfigurationChange(_:)),
            name: .AVAudioEngineConfigurationChange, object: engine)
    }

    @discardableResult
    nonisolated private func invalidateEngine(identity: ObjectIdentifier) -> Bool {
        engineConfiguration.withLock {
            guard $0.identity == identity else { return false }
            $0.invalidated = true
            return true
        }
    }

    private var engineIsInvalidated: Bool {
        let identity = ObjectIdentifier(engine)
        return engineConfiguration.withLock { $0.identity == identity && $0.invalidated }
    }

    private func replaceInvalidatedEngineIfNeeded() {
        guard engineIsInvalidated else { return }
        let previous = engine
        if tapInstalled { previous.inputNode.removeTap(onBus: 0); tapInstalled = false }
        if previous.isRunning { previous.stop() }
        NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: previous)
        let replacement = AVAudioEngine()
        engine = replacement
        let replacementIdentity = ObjectIdentifier(replacement)
        engineConfiguration.withLock { $0 = EngineConfiguration(identity: replacementIdentity) }
        observeEngineConfiguration()
    }

    /// Retry a stale bus once before opening capture. No new engine is made for
    /// healthy sessions, and an active recognition segment is never restarted.
    private func prepareCaptureEngine(validate: (AVAudioEngine) throws -> Void) throws {
        guard !isListening, !isFinalizing else { throw MicrophoneInputError.changed }
        replaceInvalidatedEngineIfNeeded()
        do { try validate(engine) }
        catch MicrophoneInputError.changed {
            invalidateEngine(identity: ObjectIdentifier(engine))
            replaceInvalidatedEngineIfNeeded()
            do { try validate(engine) }
            catch {
                invalidateEngine(identity: ObjectIdentifier(engine))
                throw error
            }
        }
    }

    private static func validateMicrophoneFormat(
        hardwareRate: Double, hardwareChannels: AVAudioChannelCount,
        busRate: Double, busChannels: AVAudioChannelCount
    ) throws {
        guard hardwareRate.isFinite, hardwareRate > 0, hardwareChannels > 0 else {
            throw MicrophoneInputError.unavailable
        }
        guard busRate.isFinite, busRate > 0, busChannels > 0,
              hardwareRate == busRate, hardwareChannels == busChannels else {
            throw MicrophoneInputError.changed
        }
    }

    private static func validatedMicrophoneFormat(of input: AVAudioInputNode) throws -> AVAudioFormat {
        let hardware = input.inputFormat(forBus: 0)
        let bus = input.outputFormat(forBus: 0)
        try validateMicrophoneFormat(hardwareRate: hardware.sampleRate, hardwareChannels: hardware.channelCount,
            busRate: bus.sampleRate, busChannels: bus.channelCount)
        return bus
    }

    #if os(iOS)
    @objc nonisolated private func handleAudioInterruption(_ notification: Notification) {
        let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
        Task { @MainActor [weak self] in
            self?.interruptAudio()
        }
    }
    #endif

    private func interruptAudio() {
        if isListening || isFinalizing || startingSessionID != nil {
            cancel()
            message = "Listening stopped because audio was interrupted."
        } else if neuralOwnerID != nil || !speechSegments.isEmpty {
            // The on-device renderer and player share the native queue's
            // interruption boundary, including generation before playback.
            stopSpeech()
            message = "Speech stopped because audio was interrupted."
        }
    }

    var microphonePermission: Permission {
        switch AVAudioApplication.shared.recordPermission { case .undetermined: .notDetermined; case .granted: .authorized; case .denied: .denied; @unknown default: .unavailable }
    }
    var speechPermission: Permission {
        switch SFSpeechRecognizer.authorizationStatus() { case .notDetermined: .notDetermined; case .authorized: .authorized; case .denied: .denied; case .restricted: .restricted; @unknown default: .unavailable }
    }
    var availableVoices: [AVSpeechSynthesisVoice] {
        _ = voiceInventoryRevision
        let installed = AVSpeechSynthesisVoice.speechVoices()
        var compatible = Self.rankedVoices(from: installed, locale: .current)
        if let selected = installed.first(where: { $0.identifier == voiceIdentifier }),
           Self.isOrdinaryVoice(selected), !compatible.contains(where: { $0.identifier == selected.identifier }) {
            compatible.append(selected)
        }
        return compatible
    }
    /// Explicit choices survive restart. Missing/download-removed voices fall back
    /// to the best installed ordinary voice without silently changing the preference.
    var selectedVoiceIdentifier: String? { resolvedVoice?.identifier }
    var usesAutomaticVoice: Bool { voiceIdentifier.isEmpty }
    var explicitVoiceIdentifier: String? { voiceIdentifier.isEmpty ? nil : voiceIdentifier }
    var voiceSelectionDescription: String {
        _ = voiceInventoryRevision
        guard let voice = resolvedVoice else { return "No compatible Apple voice is installed." }
        if !voiceIdentifier.isEmpty, voice.identifier != voiceIdentifier {
            return "Your selected voice is no longer installed. Suzzme is using \(voice.name) until it is available again."
        }
        return "\(usesAutomaticVoice ? "Automatic uses" : "Selected:") \(voice.name) · \(voice.language) · \(Self.qualityTitle(voice.quality))"
    }
    private static func qualityTitle(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality { case .premium: "Premium"; case .enhanced: "Enhanced"; default: "Default" }
    }

    private var resolvedVoice: AVSpeechSynthesisVoice? {
        if !voiceIdentifier.isEmpty, let selected = AVSpeechSynthesisVoice(identifier: voiceIdentifier), Self.isOrdinaryVoice(selected) {
            return selected
        }
        return Self.preferredVoice(from: AVSpeechSynthesisVoice.speechVoices(), locale: .current)
    }

    static func preferredVoice(from voices: [AVSpeechSynthesisVoice], locale: Locale) -> AVSpeechSynthesisVoice? {
        rankedVoices(from: voices, locale: locale).first
    }

    private static func isOrdinaryVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        !voice.voiceTraits.contains(.isNoveltyVoice) && !voice.voiceTraits.contains(.isPersonalVoice)
    }

    static func rankedVoices(from voices: [AVSpeechSynthesisVoice], locale: Locale) -> [AVSpeechSynthesisVoice] {
        let language = locale.language.languageCode?.identifier.lowercased() ?? "en"
        let localeTag = [language, locale.region?.identifier.lowercased()].compactMap { $0 }.joined(separator: "-")
        let systemIdentifier = AVSpeechSynthesisVoice(language: locale.identifier)?.identifier
        // Native regional defaults provide sensible ties among equal-quality
        // voices. Their names/providers are never used as a quality heuristic.
        let regionalDefaults = Set(voices.map(\.language).filter {
            $0.lowercased().split(separator: "-").first.map(String.init) == language
        }.compactMap { AVSpeechSynthesisVoice(language: $0)?.identifier })
        return voices.filter {
            $0.language.lowercased().split(separator: "-").first.map(String.init) == language
                && isOrdinaryVoice($0)
        }.sorted {
            if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
            let leftRegion = $0.language.lowercased() == localeTag
            let rightRegion = $1.language.lowercased() == localeTag
            if leftRegion != rightRegion { return leftRegion }
            let leftSystem = $0.identifier == systemIdentifier
            let rightSystem = $1.identifier == systemIdentifier
            if leftSystem != rightSystem { return leftSystem }
            let leftRegionalDefault = regionalDefaults.contains($0.identifier)
            let rightRegionalDefault = regionalDefaults.contains($1.identifier)
            if leftRegionalDefault != rightRegionalDefault { return leftRegionalDefault }
            return $0.identifier < $1.identifier
        }
    }

    func beginSession(id: UUID = UUID()) -> UUID {
        teardown()
        startingSessionID = nil
        sessionID = id
        allowsSessionStart = true
        finalizedSessionID = nil
        stopSpeech(interruptBriefing: true)
        finalTranscript = nil; partialTranscript = ""; message = nil; transcriptFinalizer.reset()
        return sessionID
    }

    func start(sessionID: UUID, waitsForRelease: Bool = false) async {
        guard sessionID == self.sessionID, allowsSessionStart, !isListening, !isFinalizing,
              startingSessionID != sessionID, !Task.isCancelled else { return }
        startingSessionID = sessionID
        pauseToFinishTask?.cancel(); pauseToFinishTask = nil
        self.waitsForRelease = waitsForRelease
        defer { if startingSessionID == sessionID { startingSessionID = nil } }
        if !usesDeviceVoiceOnly, speechEngine == .cloud {
            await startCloudRecognition(sessionID: sessionID)
            return
        }
        await startDeviceRecognition(sessionID: sessionID)
    }

    private func startDeviceRecognition(sessionID: UUID) async {
        guard await authorize(sessionID: sessionID), ownsStart(sessionID) else { return }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { fail("On-device speech recognition isn’t available right now. You can type instead."); return }
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            captureAudioSessionActive = true
            #endif
            try prepareCaptureEngine { _ = try Self.validatedMicrophoneFormat(of: $0.inputNode) }
            guard ownsStart(sessionID) else { teardown(); return }
            try startRecognitionSegment(recognizer: recognizer, input: engine.inputNode)
            guard ownsStart(sessionID) else { teardown(); return }
            engine.prepare(); try engine.start()
            guard ownsStart(sessionID) else { teardown(); return }
            if engineIsInvalidated {
                fail("The microphone changed while listening. Please try again.")
                return
            }
            lastAudioLevelUpdate = nil
            isListening = true; assistant.transition(to: .listening)

        } catch MicrophoneInputError.unavailable {
            fail("No microphone input is available. You can type instead.")
        } catch MicrophoneInputError.changed {
            invalidateEngine(identity: ObjectIdentifier(engine))
            fail("The microphone changed while listening. Please try again.")
        } catch {
            invalidateEngine(identity: ObjectIdentifier(engine))
            fail("I couldn’t start listening.")
        }
    }

    private func startCloudRecognition(sessionID: UUID) async {
        guard await authorizeMicrophone(sessionID: sessionID), ownsStart(sessionID) else { return }
        guard SuzzmeCloudVoice.isConfigured else { fail(SuzzmeCloudVoiceError.unavailable.localizedDescription); return }
        let recognitionID = UUID()
        do {
            #if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            captureAudioSessionActive = true
            #endif
            try prepareCaptureEngine { _ = try Self.validatedMicrophoneFormat(of: $0.inputNode) }
            let provider = AssemblyAIStreamingTranscriptionProvider()
            let session = try await provider.startStreamingSession(keyterms: ["Suzzme"], onTranscriptUpdate: { [weak self] transcript in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == sessionID, self.recognitionOwnerID == recognitionID else { return }
                    let changed = self.partialTranscript != transcript
                    self.partialTranscript = transcript
                    if changed { self.schedulePauseToFinish(transcript, sessionID: sessionID) }
                }
            }, onFinalTranscriptReady: { [weak self] transcript in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == sessionID, self.recognitionOwnerID == recognitionID else { return }
                    self.finish(transcript)
                }
            }, onError: { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == sessionID, self.recognitionOwnerID == recognitionID else { return }
                    self.fail("Cloud transcription disconnected. Please try again.")
                }
            })
            guard ownsStart(sessionID) else { session.cancel(); teardown(); return }
            recognitionOwnerID = recognitionID
            cloudRecognitionSession = session
            let format = try Self.validatedMicrophoneFormat(of: engine.inputNode)
            let tap: AVAudioNodeTapBlock = { [weak self, weak session] buffer, _ in
                session?.appendAudioBuffer(buffer)
                let level = Self.normalizedAudioLevel(from: buffer)
                Task { @MainActor [weak self] in self?.updateAudioLevel(level, sessionID: sessionID, recognitionID: recognitionID) }
            }
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format, block: tap)
            tapInstalled = true
            engine.prepare(); try engine.start()
            guard ownsStart(sessionID) else { teardown(); return }
            isListening = true
            assistant.transition(to: .listening)
        } catch {
            guard ownsStart(sessionID), !Task.isCancelled else { teardown(); return }
            recognitionOwnerID = nil
            cloudRecognitionSession?.cancel()
            cloudRecognitionSession = nil
            stopCapture()
            message = "Suzzme Voice is unavailable. Using on-device speech recognition."
            await startDeviceRecognition(sessionID: sessionID)
        }
    }

    private func authorizeMicrophone(sessionID: UUID) async -> Bool {
        guard ownsStart(sessionID) else { return false }
        if microphonePermission == .notDetermined { _ = await AVAudioApplication.requestRecordPermission() }
        guard ownsStart(sessionID) else { return false }
        guard microphonePermission == .authorized else { fail("Microphone access is off."); return false }
        return true
    }

    /// Rotate Speech requests while keeping the same audio engine and physical hold.
    private func startRecognitionSegment(recognizer: SFSpeechRecognizer, input: AVAudioInputNode) throws {
        guard !engineIsInvalidated else { throw MicrophoneInputError.changed }
        let format = try Self.validatedMicrophoneFormat(of: input)
        let next = Self.makeRecognitionRequest()
        let recognitionID = UUID()
        recognitionOwnerID = recognitionID
        request = next
        currentSegmentPartial = ""
        currentSegmentHasInput = false
        if tapInstalled { input.removeTap(onBus: 0); tapInstalled = false }
        try Self.installRecognitionTap(on: input, format: format, request: next, sessionID: sessionID, recognitionID: recognitionID, owner: self)
        tapInstalled = true
        recognitionTask = Self.makeRecognitionTask(recognizer: recognizer, request: next, sessionID: sessionID, recognitionID: recognitionID, owner: self)
    }

    private static func makeRecognitionRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = true
        return request
    }

    private func rotateRecognitionSegment() {
        let previousTask = recognitionTask
        recognitionOwnerID = nil
        request?.endAudio()
        previousTask?.cancel()
        recognitionTask = nil
        // Ownership rotates even if Speech has already released its task.
        let nextID = UUID()
        recognitionOwnerID = nextID
        request = Self.makeRecognitionRequest()
        currentSegmentPartial = ""
        currentSegmentHasInput = false
        guard previousTask != nil, let recognizer else { return }
        do {
            let input = engine.inputNode
            try startRecognitionSegment(recognizer: recognizer, input: input)
        } catch {
            invalidateEngine(identity: ObjectIdentifier(engine))
            fail("I couldn’t keep listening. Please try again.")
        }
    }

    /// AVAudioEngine invokes tap blocks on its realtime queue. Defining the
    /// block in a nonisolated helper prevents accidental MainActor inheritance.
    nonisolated private static func installRecognitionTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest,
        sessionID: UUID,
        recognitionID: UUID,
        owner: VoiceSessionController
    ) throws {
        // Only bookkeeping is shared. Never wait for a lock on the audio queue
        // or retain a PCM buffer in a task that will hop to the MainActor.
        let lastEmission = OSAllocatedUnfairLock(initialState: UInt64(0))
        let tap: AVAudioNodeTapBlock = { [weak owner] buffer, _ in
            request.append(buffer)
            let now = DispatchTime.now().uptimeNanoseconds
            let shouldEmit = lastEmission.withLockIfAvailable { previous in
                guard now >= previous, now - previous >= 70_000_000 else { return false }
                previous = now
                return true
            } ?? false
            guard shouldEmit else { return }
            let level = Self.normalizedAudioLevel(from: buffer)
            Task { @MainActor [weak owner] in
                owner?.updateAudioLevel(level, sessionID: sessionID, recognitionID: recognitionID)
            }
        }
        if #available(iOS 27.0, macOS 27.0, *) {
            try input.__installTap(onBus: 0, bufferSize: 1024, format: format, error: (), block: tap)
        } else {
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: tap)
        }
    }

    /// Bound work to at most 2,048 samples, even if an input supplies a larger
    /// buffer. Read samples on the tap queue and pass only the scalar level.
    nonisolated static func normalizedAudioLevel(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channels = buffer.floatChannelData, buffer.format.channelCount > 0 else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        let step = max(1, (frameCount + 2_047) / 2_048)
        var summedSquares = 0.0
        var sampleCount = 0
        for index in stride(from: 0, to: frameCount, by: step) {
            let sample = Double(channels[0][index])
            if sample.isFinite { summedSquares += sample * sample }
            sampleCount += 1
        }
        let rootMeanSquare = sqrt(summedSquares / Double(sampleCount))
        return min(max(rootMeanSquare * 10, 0), 1)
    }

    private func updateAudioLevel(_ level: Double, sessionID: UUID, recognitionID: UUID) {
        guard self.sessionID == sessionID, recognitionOwnerID == recognitionID, isListening else { return }
        if level > 0 { currentSegmentHasInput = true }
        let now = ContinuousClock.now
        if level >= 0.08 { lastSpeechAudioAt = now }
        if let lastAudioLevelUpdate, now - lastAudioLevelUpdate < .milliseconds(70) { return }
        lastAudioLevelUpdate = now
        audioLevel = level
    }

    /// Speech recognition callbacks also arrive on an arbitrary queue. Only
    /// the nested MainActor task may touch observable session state.
    nonisolated private static func makeRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        sessionID: UUID,
        recognitionID: UUID,
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
                    sessionID: sessionID,
                    recognitionID: recognitionID
                )
            }
        }
    }

    private func handleRecognition(
        transcript: String?,
        isFinal: Bool,
        hasError: Bool,
        sessionID: UUID,
        recognitionID: UUID
    ) {
        guard self.sessionID == sessionID, recognitionOwnerID == recognitionID,
              isListening || isFinalizing else { return }
        if hasError {
            if isFinalizing, let candidate = finalizationCandidate { finish(candidate) }
            else { fail("I couldn’t transcribe that. Please try again.") }
            return
        }
        if let transcript {
            let combined = pendingFinalTranscript.map { $0 + " " + transcript } ?? transcript
            guard combined.count <= VoiceTranscriptFinalizer.maximumCharacters else {
                fail("That request was too long. Please try a shorter request.")
                return
            }
            let changed = partialTranscript != combined
            currentSegmentPartial = transcript
            partialTranscript = combined
            if changed { schedulePauseToFinish(combined, sessionID: sessionID) }
            if isFinal {
                if waitsForRelease && isListening {
                    guard let committed = transcriptFinalizer.appendFinalSegment(transcript) else {
                        fail("I couldn’t finish that request. Please try again.")
                        return
                    }
                    pendingFinalTranscript = committed
                    partialTranscript = committed
                    rotateRecognitionSegment()
                } else { finish(combined) }
            }
        } else if isFinal {
            if isFinalizing, let candidate = finalizationCandidate { finish(candidate) }
            else { fail("I couldn’t hear anything. Please try again.") }
        }
    }

    private func schedulePauseToFinish(_ transcript: String, sessionID: UUID) {
        pauseToFinishTask?.cancel()
        guard !waitsForRelease, isListening, !isFinalizing,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pauseToFinishTask = Task { @MainActor [weak self] in
            let started = ContinuousClock.now
            do { try await Task.sleep(for: .seconds(1.8)) } catch { return }
            while let self, !Task.isCancelled, self.sessionID == sessionID,
                  self.isListening, !self.isFinalizing, !self.waitsForRelease,
                  self.partialTranscript == transcript {
                let now = ContinuousClock.now
                if let lastAudio = self.lastSpeechAudioAt, now - lastAudio < .milliseconds(700),
                   now - started < .seconds(4) {
                    do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                    continue
                }
                self.stop()
                return
            }
        }
    }

    /// Once the user explicitly ends recording, accept Speech's latest usable
    /// partial if its final callback is delayed or replaced by a task error.
    private var finalizationCandidate: String? {
        let candidate = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? pendingFinalTranscript : candidate
    }

    func stop() {
        pauseToFinishTask?.cancel(); pauseToFinishTask = nil
        // Releasing during permissions also closes a start that has not yet
        // entered its async body. It cannot start the microphone afterward.
        allowsSessionStart = false
        startingSessionID = nil
        guard !isFinalizing, !transcriptFinalizer.hasFinalized else { return }
        if let cloudRecognitionSession {
            guard isListening else { return }
            stopCapture()
            isFinalizing = true
            assistant.transition(to: .transcribing)
            cloudRecognitionSession.requestFinalTranscript()
            let ownerID = sessionID
            finalizationTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, self.sessionID == ownerID, self.isFinalizing else { return }
                let candidate = self.partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.isEmpty { self.fail("I couldn’t hear anything. Please try again.") }
                else { self.finish(candidate) }
            }
            return
        }
        guard isListening, request != nil, let recognitionID = recognitionOwnerID else {
            fail("I couldn’t hear anything. Please try again.")
            return
        }
        stopCapture()
        if let pendingFinalTranscript, currentSegmentPartial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !currentSegmentHasInput { finish(pendingFinalTranscript); return }
        isFinalizing = true
        assistant.transition(to: .transcribing)
        request?.endAudio()
        let ownerID = sessionID
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        finalizationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
            guard let self, !Task.isCancelled, self.sessionID == ownerID,
                  self.recognitionOwnerID == recognitionID, self.isFinalizing else { return }
            // The explicit Done/release is the user's signal that this partial
            // is complete enough to send if Speech never emits its final result.
            if let candidate = self.finalizationCandidate { self.finish(candidate) }
            else { self.fail("I couldn’t hear anything. Please try again.") }
        }
    }
    func cancel() {
        pauseToFinishTask?.cancel(); pauseToFinishTask = nil
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
    var canStartSpeech: Bool { !isListening && !isFinalizing && startingSessionID == nil }

    func speak(_ text: String, then state: SuzzmeAssistantState = .success, preserveFullText: Bool = false) {
        guard speaksResponses, canStartSpeech else { return }
        let spoken = Self.speechText(text, concise: !preserveFullText && state != .awaitingConfirmation)
        stopSpeech(interruptBriefing: true)
        guard !spoken.isEmpty else { finishReadableResponse(then: state); return }
        stateAfterSpeech = state
        // Consequential confirmations retain neutral delivery and every word.
        startSpeechOutput(spoken, preview: false, useNatural: state != .awaitingConfirmation,
            style: state == .awaitingConfirmation ? .natural : deliveryStyle)
    }

    func speakBriefing(_ text: String, id: UUID) {
        guard speaksResponses, canStartSpeech else { return }
        // Explicit “read summary” preserves the complete factual narration.
        let spoken = Self.speechText(text)
        stopSpeech(interruptBriefing: true)
        guard !spoken.isEmpty else { finishReadableResponse(then: .success); return }
        activeBriefingID = id
        stateAfterSpeech = .success
        startSpeechOutput(spoken, preview: false, useNatural: true)
    }

    private func finishReadableResponse(then state: SuzzmeAssistantState) {
        if state == .awaitingConfirmation { assistant.transition(to: .awaitingConfirmation) }
        else { assistant.complete() }
    }

    func stopSpeech(interruptBriefing: Bool = true) {
        let ownsPreparation = speechPreparationRevision == assistant.revision
        speechPreparationRevision = nil
        if interruptBriefing, let activeBriefingID {
            interruptedBriefingID = activeBriefingID
            self.activeBriefingID = nil
            briefingLifecycleRevision = UUID()
        }
        neuralOwnerID = nil
        neuralTask?.cancel()
        neuralTask = nil
        neuralProgressTask?.cancel()
        neuralProgressTask = nil
        neuralPlayer?.stop()
        neuralPlayer = nil
        isPreparingSpeech = false
        activeSpeechUtteranceID = nil
        speechSegments.removeAll()
        speechLength = 0
        isSpeaking = false
        isPreviewing = false
        speechProgress = 0
        // Cancel the native queue even before its first didStart callback.
        synthesizer.stopSpeaking(at: .immediate)
        if assistant.state == .speaking || ownsPreparation {
            assistant.transition(to: stateAfterSpeech == .awaitingConfirmation ? .awaitingConfirmation : .idle)
        }
        releaseSpeechOutput()
    }

    func stopPreview() { if isPreviewing { stopSpeech() } }

    func acknowledgeBriefingLifecycle() {
        completedBriefingID = nil
        interruptedBriefingID = nil
    }

    func selectVoice(_ voice: AVSpeechSynthesisVoice) {
        guard Self.isOrdinaryVoice(voice), AVSpeechSynthesisVoice.speechVoices().contains(where: { $0.identifier == voice.identifier }) else { return }
        voiceIdentifier = voice.identifier
    }
    func selectAutomaticVoice() { voiceIdentifier = "" }

    func preview(_ voice: AVSpeechSynthesisVoice) {
        startPreview(Self.previewText(language: voice.language), voice: voice)
    }

    func previewSelectedVoice() {
        if !usesDeviceVoiceOnly, speechEngine == .cloud, canStartSpeech {
            stopSpeech()
            startSpeechOutput(Self.previewText(language: "en"), preview: true, useNatural: false)
        } else if speechEngine == .natural, naturalVoiceIsReady, canStartSpeech {
            stopSpeech()
            startSpeechOutput(Self.previewText(language: "en"), preview: true, useNatural: true)
        } else if let voice = resolvedVoice { preview(voice) }
    }

    #if DEBUG
    static let auditionText = "Good morning. You have one important thing today. Your next class is at ten thirty, and you have two unfinished reminders."
    func audition(_ voice: AVSpeechSynthesisVoice) { startPreview(Self.auditionText, voice: voice) }
    #endif

    private func startPreview(_ text: String, voice: AVSpeechSynthesisVoice) {
        // A preview owns its queue but never becomes an assistant response.
        guard canStartSpeech, Self.isOrdinaryVoice(voice) else { return }
        stopSpeech()
        guard prepareSpeechOutput() else { return }
        isPreviewing = true
        enqueueSpeech(Self.speechText(text), voice: voice, preview: true)
    }

    /// Generation and playback retain the same controller and cancellation
    /// owner as native speech. Late buffers never revive a retired request.
    private func startSpeechOutput(_ text: String, preview: Bool, useNatural: Bool, style: DeliveryStyle? = nil) {
        // A response owns its preparation presentation until audible playback
        // begins. Cancelling it may settle that exact phase, never a newer one.
        speechPreparationRevision = preview ? nil : assistant.revision
        if !usesDeviceVoiceOnly, speechEngine == .cloud {
            startCloudSpeech(text, preview: preview, style: style)
            return
        }
        let selectedVoice = resolvedVoice(for: text)
        let language = selectedVoice?.language.split(separator: "-").first
        if useNatural, speechEngine == .natural, naturalVoiceIsReady,
           preview || (language == "en" && Self.isEnglishSpeech(text)) {
            let id = UUID()
            neuralOwnerID = id
            isPreparingSpeech = true
            isPreviewing = preview
            message = nil
            let renderer = localSpeechRenderer
            neuralTask = Task { @MainActor [weak self] in
                do {
                    let data: Data
                    if let renderer { data = try await renderer(text) }
                    else {
                        #if canImport(SuzzmeSpeechKit) && os(macOS)
                        data = try await LocalSpeechRenderer.shared.render(text)
                        #else
                        throw CancellationError()
                        #endif
                    }
                    guard let self, self.neuralOwnerID == id, !Task.isCancelled else { return }
                    guard preview || self.speaksResponses, self.canStartSpeech else { self.stopSpeech(); return }
                    guard self.prepareSpeechOutput() else {
                        self.stopSpeech()
                        if !preview { self.finishReadableResponse(then: self.stateAfterSpeech) }
                        return
                    }
                    let player = try AVAudioPlayer(data: data)
                    player.delegate = self
                    player.enableRate = true
                    let scale: Float = self.deliveryStyle == .calm ? 0.95 : 1
                    player.rate = min(max(self.speechRate / AVSpeechUtteranceDefaultSpeechRate * scale, 0.75), 1.25)
                    self.neuralPlayer = player
                    guard player.play() else { throw NSError(domain: "Suzzme.LocalSpeech", code: 1) }
                    self.isPreparingSpeech = false
                    self.speechPreparationRevision = nil
                    self.isSpeaking = !preview
                    if !preview { self.assistant.transition(to: .speaking) }
                    self.neuralProgressTask = Task { @MainActor [weak self] in
                        while !Task.isCancelled {
                            guard let self, self.neuralOwnerID == id, let player = self.neuralPlayer else { return }
                            // Playback time is measured, never treated as amplitude.
                            self.speechProgress = player.duration > 0 ? min(player.currentTime / player.duration, 1) : 0
                            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                        }
                    }
                } catch {
                    guard let self, self.neuralOwnerID == id, !Task.isCancelled else { return }
                    self.neuralOwnerID = nil
                    self.neuralTask = nil
                    self.neuralPlayer = nil
                    self.isPreparingSpeech = false
                    self.message = "Natural voice is unavailable. Using your Apple voice."
                    guard preview || self.speaksResponses, self.canStartSpeech else {
                        self.stopSpeech()
                        return
                    }
                    guard self.prepareSpeechOutput() else {
                        self.stopSpeech()
                        if !preview { self.finishReadableResponse(then: self.stateAfterSpeech) }
                        return
                    }
                    self.enqueueSpeech(text, voice: selectedVoice, preview: preview, style: style)
                }
            }
        } else if prepareSpeechOutput() {
            enqueueSpeech(text, voice: selectedVoice, preview: preview, style: style)
        } else {
            stopSpeech()
            if !preview { finishReadableResponse(then: stateAfterSpeech) }
        }
    }

    private func startCloudSpeech(_ text: String, preview: Bool, style: DeliveryStyle?) {
        let id = UUID()
        neuralOwnerID = id
        isPreparingSpeech = true
        isPreviewing = preview
        message = nil
        neuralTask = Task { @MainActor [weak self] in
            do {
                let data = try await SuzzmeCloudVoice.speech(text)
                guard let self, self.neuralOwnerID == id, !Task.isCancelled else { return }
                guard preview || self.speaksResponses, self.canStartSpeech else { self.stopSpeech(); return }
                guard self.prepareSpeechOutput() else { throw SuzzmeCloudVoiceError.unavailable }
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                self.neuralPlayer = player
                guard player.play() else { throw SuzzmeCloudVoiceError.invalidResponse }
                self.isPreparingSpeech = false
                self.speechPreparationRevision = nil
                self.isSpeaking = !preview
                if !preview { self.assistant.transition(to: .speaking) }
                self.neuralProgressTask = Task { @MainActor [weak self] in
                    while !Task.isCancelled {
                        guard let self, self.neuralOwnerID == id, let player = self.neuralPlayer else { return }
                        self.speechProgress = player.duration > 0 ? min(player.currentTime / player.duration, 1) : 0
                        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                    }
                }
            } catch {
                guard let self, self.neuralOwnerID == id, !Task.isCancelled else { return }
                // Keep this response's briefing and presentation ownership while
                // handing playback to the device voice. A cancelled cloud task
                // must never enqueue a late fallback.
                self.neuralOwnerID = nil
                self.neuralTask = nil
                self.neuralPlayer?.stop()
                self.neuralPlayer = nil
                self.isPreparingSpeech = false
                guard preview || self.speaksResponses, self.canStartSpeech else {
                    self.stopSpeech()
                    return
                }
                self.message = "Suzzme Voice is unavailable. Using your Apple voice."
                guard self.prepareSpeechOutput() else {
                    self.stopSpeech()
                    if !preview { self.finishReadableResponse(then: self.stateAfterSpeech) }
                    return
                }
                self.enqueueSpeech(text, voice: self.resolvedVoice(for: text), preview: preview, style: style)
            }
        }
    }

    private static func isEnglishSpeech(_ text: String) -> Bool {
        guard text.count >= 20 else { return true }
        let detector = NLLanguageRecognizer()
        detector.processString(text)
        return detector.dominantLanguage == .english
    }

    private func completeSpeech(preview: Bool) {
        speechPreparationRevision = nil
        isSpeaking = false
        isPreviewing = false
        speechProgress = 0
        releaseSpeechOutput()
        guard !preview, assistant.state == .speaking else { return }
        if let briefingID = activeBriefingID {
            completedBriefingID = briefingID
            activeBriefingID = nil
            briefingLifecycleRevision = UUID()
        }
        if stateAfterSpeech == .awaitingConfirmation { assistant.transition(to: .awaitingConfirmation) }
        else { assistant.complete() }
    }

    private func resolvedVoice(for text: String) -> AVSpeechSynthesisVoice? {
        if !voiceIdentifier.isEmpty { return resolvedVoice }
        guard automaticallyMatchesLanguage, text.count >= 20 else { return resolvedVoice }
        let detector = NLLanguageRecognizer()
        detector.processString(text)
        guard let candidate = detector.languageHypotheses(withMaximum: 1).first, candidate.value >= 0.7 else { return resolvedVoice }
        let detectedLanguage = candidate.key.rawValue
        let currentLanguage = Locale.current.language.languageCode?.identifier
        // Recognizing English must not discard the current regional accent.
        if detectedLanguage == currentLanguage { return resolvedVoice }
        let preferredLocale = Locale.preferredLanguages.map { Locale(identifier: $0) }.first {
            $0.language.languageCode?.identifier == detectedLanguage
        } ?? Locale(identifier: detectedLanguage)
        return Self.preferredVoice(from: AVSpeechSynthesisVoice.speechVoices(), locale: preferredLocale) ?? resolvedVoice
    }

    private static func previewText(language: String) -> String {
        switch language.split(separator: "-").first {
        case "hi": "नमस्ते, मैं सुज़मी हूँ। मैं आपकी बात सुनने के लिए तैयार हूँ।"
        case "es": "Hola, soy Suzzme. Estoy aquí cuando me necesites."
        case "fr": "Bonjour, je suis Suzzme. Je suis là quand vous avez besoin de moi."
        case "de": "Hallo, ich bin Suzzme. Ich bin bereit, wenn du mich brauchst."
        case "ja": "こんにちは、Suzzmeです。いつでもお話しください。"
        case "zh": "你好，我是Suzzme。你需要的时候，我就在这里。"
        default: "Hi, I’m Suzzme. Take your time — we can work through this together. What would you like to do next?"
        }
    }

    /// Formatting-only transformation: no model, new facts, guessed times or
    /// locations. Confirmations and explicit summary narration remain complete.
    static func speechText(_ text: String, concise: Bool = false) -> String {
        var value = text.replacingOccurrences(of: "(?s)```.*?```", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"!?\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: #"https?://[^\s<>]+"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?m)^\s*(?:#{1,6}\s+|>\s*|[-*•]\s+|\d+[.)]\s+)"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?m)^\s*\[x\]\s*"#, with: "Completed: ", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"(?m)^\s*\[ \]\s*"#, with: "Not completed: ", options: .regularExpression)
        value = value.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "").replacingOccurrences(of: "`", with: "")
        value = value.replacingOccurrences(of: #"(?<!\w)[*_]([^*_\n]+)[*_](?!\w)"#, with: "$1", options: .regularExpression)
        // Native parsing preserves the explicit instant; it never supplies a
        // missing zone/date. Display it using the same local calendar as UI.
        if let timestamps = try? NSRegularExpression(pattern: #"\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\b"#) {
            let formatter = ISO8601DateFormatter()
            for match in timestamps.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                guard let range = Range(match.range, in: value) else { continue }
                let raw = String(value[range])
                formatter.formatOptions = raw.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
                if let date = formatter.date(from: raw) { value.replaceSubrange(range, with: date.formatted(date: .abbreviated, time: .shortened)) }
            }
        }
        let lines = value.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
            !$0.isEmpty && $0.range(of: #"^\|?[\s:|\-]+\|?$"#, options: .regularExpression) == nil
                && $0.range(of: #"^(?:Source metadata:|Request ID:|Fingerprint:|Confidence:\s*(?:\d|low|high|unknown))"#, options: [.regularExpression, .caseInsensitive]) == nil
        }
        value = lines.map { line in
            let readable = line.hasPrefix("|") && line.hasSuffix("|")
                ? line.trimmingCharacters(in: CharacterSet(charactersIn: "| ")).replacingOccurrences(of: #"\s*\|\s*"#, with: ", ", options: .regularExpression) : line
            let timeline = readable.replacingOccurrences(of: #"^(\d{1,2}:\d{2}(?:\s*[AP]M)?)\s*[—–]\s*"#, with: "$1, ", options: [.regularExpression, .caseInsensitive])
            if let last = timeline.last, !".!?:;。！？".contains(last) { return timeline + "." }
            return timeline
        }.joined(separator: " ").replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        guard concise, value.count > 900 else { return value }
        var sentences: [String] = []
        value.enumerateSubstrings(in: value.startIndex..<value.endIndex, options: .bySentences) { sentence, _, _, stop in
            guard let sentence else { return }
            if sentences.count == 4 || (!sentences.isEmpty && sentences.joined(separator: " ").count + sentence.count > 900) { stop = true; return }
            sentences.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return sentences.isEmpty ? value : sentences.joined(separator: " ")
    }

    /// Queue complete, already validated text in bounded phrases. No model partial enters TTS.
    static func speechChunks(_ text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        func appendPhrase(_ phrase: String) {
            let value = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            if value.count <= 360 {
                if !current.isEmpty, current.count + value.count + 1 > 360 { chunks.append(current); current = "" }
                current += (current.isEmpty ? "" : " ") + value
                return
            }
            if !current.isEmpty { chunks.append(current); current = "" }
            for word in value.split(whereSeparator: { $0.isWhitespace }) {
                var remaining = word[...]
                while remaining.count > 360 {
                    if !current.isEmpty { chunks.append(current); current = "" }
                    chunks.append(String(remaining.prefix(360)))
                    remaining = remaining.dropFirst(360)
                }
                if !current.isEmpty, current.count + remaining.count + 1 > 360 { chunks.append(current); current = "" }
                if !remaining.isEmpty { current += (current.isEmpty ? "" : " ") + remaining }
            }
        }
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { sentence, _, _, _ in
            guard let sentence else { return }
            if sentence.count <= 360 { appendPhrase(sentence); return }
            // Native sentence detection may join lowercase sentences. Prefer
            // their explicit terminal punctuation before breaking at a word.
            let phrases = sentence.replacingOccurrences(of: #"(?<=[.!?。！？])\s+"#, with: "\u{001F}", options: .regularExpression)
                .components(separatedBy: "\u{001F}")
            for phrase in phrases { appendPhrase(phrase) }
        }
        if !current.isEmpty { chunks.append(current) }
        // Foundation may not recognize a sentence in a symbols-only string.
        if chunks.isEmpty { appendPhrase(text); if !current.isEmpty { chunks.append(current) } }
        return chunks
    }

    private func enqueueSpeech(_ text: String, voice: AVSpeechSynthesisVoice?, preview: Bool, style: DeliveryStyle? = nil) {
        let chunks = Self.speechChunks(text)
        speechLength = chunks.reduce(0) { $0 + $1.utf16.count }
        var offset = 0
        for (index, chunk) in chunks.enumerated() {
            let utterance = configuredUtterance(chunk, voice: voice, style: style,
                isFinalPhrase: index == chunks.count - 1)
            let id = ObjectIdentifier(utterance)
            speechSegments[id] = SpeechSegment(offset: offset, length: chunk.utf16.count, isPreview: preview)
            offset += chunk.utf16.count
            if activeSpeechUtteranceID == nil { activeSpeechUtteranceID = id }
            synthesizer.speak(utterance)
        }
    }

    private func configuredUtterance(_ text: String, voice: AVSpeechSynthesisVoice?, style: DeliveryStyle? = nil, isFinalPhrase: Bool = true) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        // Keep Apple's pronunciation and punctuation-driven intonation. Small
        // changes suit ordinary installed voices without a theatrical effect.
        let delivery = style ?? deliveryStyle
        let rateScale: Float = switch delivery { case .warm: 0.95; case .calm: 0.92; case .natural: 1 }
        utterance.rate = min(max(speechRate * rateScale, Self.speechRateRange.lowerBound), Self.speechRateRange.upperBound)
        utterance.pitchMultiplier = switch delivery { case .warm: 1.02; case .calm: 0.98; case .natural: 1 }
        if !isFinalPhrase {
            utterance.postUtteranceDelay = switch delivery { case .warm: 0.08; case .calm: 0.14; case .natural: 0 }
        }
        // No SSML or rewritten facts: word-progress ranges still map to the
        // displayed answer, and stop/barge-in owns the same native queue.
        return utterance
    }

    private func prepareSpeechOutput() -> Bool {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
            speechAudioSessionActive = true
        } catch {
            message = "Speech output is unavailable. You can still read Suzzme’s response."
            return false
        }
        #endif
        return true
    }

    private func releaseSpeechOutput() {
        #if os(iOS)
        guard speechAudioSessionActive, !isListening, !isFinalizing, startingSessionID == nil else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        speechAudioSessionActive = false
        #endif
    }

    private func authorize(sessionID: UUID) async -> Bool {
        await authorize(
            sessionID: sessionID,
            microphoneStatus: { self.microphonePermission },
            speechStatus: { self.speechPermission },
            requestMicrophone: { _ = await AVAudioApplication.requestRecordPermission() },
            requestSpeech: { _ = await Self.requestSpeechAuthorization() }
        )
    }

    /// Keep the ordering and ownership checks in one path; authorization
    /// providers supply system status without owning microphone capture.
    private func authorize(
        sessionID: UUID,
        microphoneStatus: () -> Permission,
        speechStatus: () -> Permission,
        requestMicrophone: () async -> Void,
        requestSpeech: () async -> Void
    ) async -> Bool {
        guard ownsStart(sessionID) else { return false }
        if microphoneStatus() == .notDetermined { await requestMicrophone() }
        guard ownsStart(sessionID) else { return false }
        guard microphoneStatus() == .authorized else { fail("Microphone access is off."); return false }
        if speechStatus() == .notDetermined { await requestSpeech() }
        guard ownsStart(sessionID) else { return false }
        // Permission may be revoked while the Speech sheet is awaiting input.
        guard microphoneStatus() == .authorized else { fail("Microphone access is off."); return false }
        guard speechStatus() == .authorized else { fail("Speech recognition access is off."); return false }
        return true
    }

    private func ownsStart(_ id: UUID) -> Bool {
        self.sessionID == id && startingSessionID == id && allowsSessionStart && !Task.isCancelled
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
        // Revoke ownership before cancellation can enqueue more callbacks.
        recognitionOwnerID = nil
        cloudRecognitionSession?.cancel()
        cloudRecognitionSession = nil
        startingSessionID = nil
        allowsSessionStart = false
        finalizationTask?.cancel(); finalizationTask = nil
        isFinalizing = false
        waitsForRelease = false
        pendingFinalTranscript = nil
        currentSegmentPartial = ""
        currentSegmentHasInput = false
        stopCapture()
        request?.endAudio(); request = nil; recognitionTask?.cancel(); recognitionTask = nil
    }
    private func stopCapture() {
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        isListening = false
        audioLevel = 0
        lastAudioLevelUpdate = nil
        lastSpeechAudioAt = nil
        #if os(iOS)
        if captureAudioSessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            captureAudioSessionActive = false
        }
        #endif
    }
    private func fail(_ text: String) { teardown(); message = text; assistant.fail(message: text) }
}

extension VoiceSessionController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, let segment = self.speechSegments[id] else { return }
            self.speechPreparationRevision = nil
            self.activeSpeechUtteranceID = id
            self.isPreviewing = segment.isPreview
            self.isSpeaking = !segment.isPreview
            if !segment.isPreview { self.assistant.transition(to: .speaking) }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let end = range.location + range.length
        Task { @MainActor [weak self] in
            guard let self, let segment = self.speechSegments[id], !segment.isPreview, self.speechLength > 0 else { return }
            self.speechProgress = max(self.speechProgress, min(Double(segment.offset + min(end, segment.length)) / Double(self.speechLength), 1))
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.speechSegments[id] != nil else { return }
            self.stopSpeech()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, let segment = self.speechSegments.removeValue(forKey: id) else { return }
            guard self.speechSegments.isEmpty else { return }
            self.activeSpeechUtteranceID = nil
            self.completeSpeech(preview: segment.isPreview)
        }
    }
}


extension VoiceSessionController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.neuralOwnerID != nil, let current = self.neuralPlayer,
                  ObjectIdentifier(current) == id else { return }
            let preview = self.isPreviewing
            self.neuralOwnerID = nil
            self.neuralPlayer = nil
            self.neuralTask = nil
            self.neuralProgressTask?.cancel()
            self.neuralProgressTask = nil
            if flag { self.completeSpeech(preview: preview) }
            else { self.stopSpeech() }
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.neuralPlayer, ObjectIdentifier(current) == id else { return }
            self.message = "Speech stopped. You can still read the response."
            self.stopSpeech()
        }
    }
}
