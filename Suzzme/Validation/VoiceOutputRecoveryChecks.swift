// Compiled with the real controller in a temporary file so private queue ownership
// can be checked. The cloud fixture fails locally; no account, network, or microphone
// is used. Recovery briefly queues a synthetic utterance with the installed Apple voice.
import Foundation

enum SuzzmeCloudVoiceError: Error { case unavailable, invalidResponse }
@MainActor enum SuzzmeCloudVoice {
    static var isConfigured = true
    static var hold = false
    static var pending: CheckedContinuation<Data, any Error>?
    static func speech(_ text: String) async throws -> Data {
        if hold {
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        throw SuzzmeCloudVoiceError.unavailable
    }
    static func temporaryTranscriptionToken() async throws -> String {
        throw SuzzmeCloudVoiceError.unavailable
    }
}

extension VoiceSessionController {
    fileprivate var nativeQueued: Bool { !speechSegments.isEmpty }
    fileprivate var briefingOwner: UUID? { activeBriefingID }
    fileprivate var outputTask: Task<Void, Never>? { neuralTask }
    fileprivate var speechCharacters: Int { speechLength }
}

@main @MainActor struct VoiceRecoveryChecks {
    static var count = 0
    static func check(_ condition: Bool, _ label: String) {
        guard condition else { fatalError("FAIL: \(label)") }
        count += 1
        print("PASS: \(label)")
    }
    static func main() async {
        let name = "dev.suzzme.voice-recovery.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "suzzme.voice.deviceOnly")
        defaults.set("cloud", forKey: "suzzme.voice.engine")
        let assistant = AssistantStateController()
        let initial = VoiceSessionController(assistant: assistant, defaults: defaults)
        check(initial.speechEngine == .cloud, "explicitly selected cloud mode remains available")
        initial.speechEngine = .apple
        let restored = VoiceSessionController(assistant: assistant, defaults: defaults)
        check(restored.speechEngine == .apple, "saved Apple choice overrides gateway configuration")
        initial.speechEngine = .natural
        check(VoiceSessionController(assistant: assistant, defaults: defaults).speechEngine == .natural,
              "saved on-device voice survives restart")
        defaults.removeObject(forKey: "suzzme.voice.engine")
        SuzzmeCloudVoice.isConfigured = false
        check(VoiceSessionController(assistant: assistant, defaults: defaults).speechEngine == .apple,
              "unconfigured gateway defaults to device voice")
        SuzzmeCloudVoice.isConfigured = true
        defaults.set("cloud", forKey: "suzzme.voice.engine")
        let voice = VoiceSessionController(assistant: assistant, defaults: defaults)
        let briefingID = UUID()
        assistant.transition(to: .understanding)
        voice.speakBriefing("Voice recovery check.", id: briefingID)
        await voice.outputTask?.value
        check(voice.nativeQueued, "failed cloud generation queues device speech")
        check(!voice.isPreparingSpeech, "failed cloud generation leaves preparation")
        check(voice.briefingOwner == briefingID && voice.interruptedBriefingID == nil,
              "fallback retains briefing ownership")
        check(voice.speechEngine == .cloud, "temporary fallback preserves selected engine")
        check(voice.message == "Suzzme Voice is unavailable. Using your Apple voice.",
              "fallback explains recovery without exposing service errors")
        voice.stopSpeech()
        check(!voice.nativeQueued && voice.briefingOwner == nil,
              "stop cancels recovered native speech and briefing")

        let narration = "Your meeting is at nine. Your deadline is at noon. Your appointment is at four."
        voice.speak(narration, preserveFullText: true)
        await voice.outputTask?.value
        check(voice.nativeQueued && voice.speechCharacters == narration.utf16.count,
              "summary playback retains every sentence rather than shortening the prepared result")
        voice.stopSpeech()

        SuzzmeCloudVoice.hold = true
        assistant.transition(to: .understanding)
        voice.speak("Cancelled recovery check.")
        let cancelledTask = voice.outputTask
        for _ in 0..<100 where SuzzmeCloudVoice.pending == nil { await Task.yield() }
        check(SuzzmeCloudVoice.pending != nil, "cloud request reaches suspension")
        voice.stopSpeech()
        SuzzmeCloudVoice.pending?.resume(throwing: SuzzmeCloudVoiceError.unavailable)
        SuzzmeCloudVoice.pending = nil
        await cancelledTask?.value
        check(!voice.nativeQueued && !voice.isPreparingSpeech && !voice.isSpeaking,
              "late cloud failure cannot revive cancelled speech")

        assistant.transition(to: .understanding)
        voice.speak("Muted recovery check.")
        let mutedTask = voice.outputTask
        for _ in 0..<100 where SuzzmeCloudVoice.pending == nil { await Task.yield() }
        check(SuzzmeCloudVoice.pending != nil, "second cloud request reaches suspension")
        voice.speaksResponses = false
        SuzzmeCloudVoice.pending?.resume(throwing: SuzzmeCloudVoiceError.unavailable)
        SuzzmeCloudVoice.pending = nil
        await mutedTask?.value
        check(!voice.nativeQueued && !voice.isPreparingSpeech,
              "turning spoken responses off prevents a late fallback")
        print("Voice recovery: \(count) checks passed")
    }
}
