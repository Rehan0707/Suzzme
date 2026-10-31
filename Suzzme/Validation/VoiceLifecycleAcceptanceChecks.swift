import Foundation
import AVFoundation

/// Lifecycle checks use the real controller without microphone capture or TTS.
/// Recognition accuracy, audible completion and barge-in remain hardware checks.
@main @MainActor struct VoiceLifecycleAcceptanceChecks {
    static var passed = 0
    static var failed = 0
    static func check(_ value: Bool, _ label: String) {
        print("\(value ? "PASS" : "FAIL") \(label)")
        if value { passed += 1 } else { failed += 1 }
    }
    static func main() async {
        let domain = "dev.suzzme.voice-acceptance.\(UUID())"
        guard let defaults = UserDefaults(suiteName: domain) else { exit(1) }
        defer { defaults.removePersistentDomain(forName: domain) }
        let assistant = AssistantStateController()
        let initialPresentation = assistant.revision
        assistant.transition(to: .idle)
        check(assistant.revision != initialPresentation,
              "repeated state transition still retires the previous presentation owner")
        assistant.complete(after: .milliseconds(20))
        let completedPresentation = assistant.revision
        assistant.transition(to: .listening)
        let listeningPresentation = assistant.revision
        try? await Task.sleep(for: .milliseconds(50))
        check(assistant.state == .listening && assistant.revision == listeningPresentation
              && listeningPresentation != completedPresentation,
              "retired success timer cannot reset a newer listening presentation")
        assistant.reset()
        check(assistant.state == .idle && assistant.message == nil && assistant.revision != listeningPresentation,
              "explicit reset clears semantics and retires the current presentation revision")
        let controller = VoiceSessionController(assistant: assistant, defaults: defaults)
        let installed = AVSpeechSynthesisVoice.speechVoices()
        let preferred = VoiceSessionController.preferredVoice(from: installed, locale: .current)
        check(controller.selectedVoiceIdentifier == preferred?.identifier, "unset voice resolves to the installed natural default")
        check(controller.availableVoices.allSatisfy { !$0.voiceTraits.contains(.isNoveltyVoice) }, "voice picker excludes novelty voices")
        check(preferred.map { !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) } ?? true,
              "automatic selection never chooses novelty or personal voices")
        check(VoiceSessionController.preferredVoice(from: [], locale: Locale(identifier: "en-US")) == nil,
              "empty installed inventory falls back safely")
        check(VoiceSessionController.preferredVoice(from: installed.reversed(), locale: .current)?.identifier == preferred?.identifier,
              "natural voice selection does not depend on inventory order")
        defaults.set("dev.suzzme.missing-voice", forKey: "suzzme.voice.identifier")
        let missingVoice = VoiceSessionController(assistant: assistant, defaults: defaults)
        check(missingVoice.selectedVoiceIdentifier == preferred?.identifier, "removed voice falls back to an installed natural voice")
        check(defaults.string(forKey: "suzzme.voice.identifier") == "dev.suzzme.missing-voice", "fallback preserves explicit preference")
        defaults.removeObject(forKey: "suzzme.voice.identifier")
        check(controller.usesAutomaticVoice && controller.speechRate == AVSpeechUtteranceDefaultSpeechRate,
              "Automatic uses the natural system rate without tuning")
        check(controller.availableVoices.allSatisfy { !$0.voiceTraits.contains(.isPersonalVoice) },
              "ordinary picker excludes personal voices requiring separate authorization")
        controller.speechRate = 0.6
        controller.automaticallyMatchesLanguage = false
        let storedPolicy = VoiceSessionController(assistant: assistant, defaults: defaults)
        check(storedPolicy.speechRate == 0.6 && !storedPolicy.automaticallyMatchesLanguage,
              "pace and automatic language policy persist")
        controller.speechRate = .nan
        check(controller.speechRate == AVSpeechUtteranceDefaultSpeechRate, "nonfinite pace restores natural default")
        controller.speechRate = 2
        check(controller.speechRate == VoiceSessionController.speechRateRange.upperBound, "pace clamps to useful native range")
        let speechText = "One complete sentence. " + String(repeating: "Another sentence with all words intact. ", count: 40)
        let chunks = VoiceSessionController.speechChunks(speechText)
        check(chunks.count > 1 && chunks.allSatisfy { $0.count <= 360 }, "completed answer divides into bounded speech phrases")
        check(chunks.joined(separator: " ").split(whereSeparator: { $0.isWhitespace }) == speechText.split(whereSeparator: { $0.isWhitespace }),
              "speech phrases preserve every completed-response word")
        controller.speaksResponses = false
        var identifiers = Set<UUID>()
        var clean = true
        for _ in 0..<100 {
            let identifier = controller.beginSession()
            identifiers.insert(identifier)
            assistant.transition(to: .understanding)
            controller.cancel()
            clean = clean && controller.sessionID != identifier && !controller.isListening
                && !controller.isFinalizing && controller.audioLevel == 0
                && controller.finalTranscript == nil && controller.finalizedSessionID == nil
                && controller.partialTranscript.isEmpty && assistant.state == .idle
        }
        check(identifiers.count == 100, "100 repeated sessions have unique ownership")
        check(clean, "100 cancellations retire ownership, clear transcripts and return idle")
        let retired = controller.beginSession()
        controller.cancel()
        await controller.start(sessionID: retired)
        check(!controller.isListening && assistant.state == .idle, "stale start cannot request recognition or revive cancelled session")
        controller.stop()
        check(controller.finalizedSessionID == nil && controller.finalTranscript == nil, "empty Stop cannot submit a transcript")
        controller.cancel()
        check(assistant.state == .idle, "cancel recovers safely after empty Stop")
        let releasedBeforeStart = controller.beginSession()
        controller.stop()
        await controller.start(sessionID: releasedBeforeStart, waitsForRelease: true)
        check(!controller.isListening && !controller.isFinalizing && controller.finalTranscript == nil,
              "release before async start cannot later open the microphone")
        controller.cancel()

        if let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1),
           let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096),
           let samples = buffer.floatChannelData?[0] {
            buffer.frameLength = 4_096
            samples.initialize(repeating: 0, count: 4_096)
            check(VoiceSessionController.normalizedAudioLevel(from: buffer) == 0,
                  "silent microphone samples have zero measured level")
            for index in 0..<4_096 { samples[index] = index.isMultiple(of: 2) ? 0.05 : -0.05 }
            check(abs(VoiceSessionController.normalizedAudioLevel(from: buffer) - 0.5) < 0.000_001,
                  "measured level uses RMS and bounded normalization")
            for index in 0..<4_096 { samples[index] = 1 }
            check(VoiceSessionController.normalizedAudioLevel(from: buffer) == 1,
                  "loud microphone samples clamp to the normalized maximum")
            for index in 0..<4_096 { samples[index] = .nan }
            check(VoiceSessionController.normalizedAudioLevel(from: buffer) == 0,
                  "nonfinite microphone samples never publish a nonfinite level")
            buffer.frameLength = 0
            check(VoiceSessionController.normalizedAudioLevel(from: buffer) == 0,
                  "empty microphone buffers have zero measured level")
        } else {
            check(false, "deterministic microphone sample buffer can be created")
        }
        controller.speak("Synthetic acceptance response.")
        check(assistant.state == .idle, "disabled voice never starts speech")
        let reopened = VoiceSessionController(assistant: assistant, defaults: defaults)
        check(!reopened.speaksResponses, "voice response setting persists across controller restart")
        if let voice = controller.availableVoices.first {
            controller.selectVoice(voice)
            let restored = VoiceSessionController(assistant: assistant, defaults: defaults)
            check(restored.selectedVoiceIdentifier == voice.identifier, "voice choice persists across controller restart")
        } else {
            print("PENDING no installed voice available for voice-choice persistence")
        }
        controller.selectAutomaticVoice()
        let automaticRestored = VoiceSessionController(assistant: assistant, defaults: defaults)
        check(automaticRestored.usesAutomaticVoice && automaticRestored.selectedVoiceIdentifier == preferred?.identifier,
              "Automatic reset persists and restores the best installed voice")
        assistant.transition(to: .listening)
        controller.speechSynthesizer(AVSpeechSynthesizer(), didFinish: AVSpeechUtterance(string: "Stale speech"))
        await Task.yield()
        check(assistant.state == .listening, "unowned TTS completion cannot overwrite listening")
        controller.cancel()
        await Task.yield()
        check(assistant.state == .idle && controller.completedBriefingID == nil, "late completion cannot mark cancelled briefing complete")
        print("Voice lifecycle acceptance: \(passed) passed / \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
