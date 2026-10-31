import Foundation
import AVFoundation

// Appended to a temporary controller copy. No test hooks ship; no audio plays.
extension VoiceSessionController {
    fileprivate func voiceForQualityCheck(_ text: String) -> AVSpeechSynthesisVoice? { resolvedVoice(for: text) }
    fileprivate func utteranceForQualityCheck(_ text: String) -> AVSpeechUtterance { configuredUtterance(text, voice: resolvedVoice) }
    fileprivate func deliveryForQualityCheck(_ text: String, style: DeliveryStyle? = nil, final: Bool = true) -> AVSpeechUtterance {
        configuredUtterance(text, voice: resolvedVoice, style: style, isFinalPhrase: final)
    }
    fileprivate func completeSpeechForQualityCheck() { completeSpeech(preview: false) }
    fileprivate var hasQueuedSpeechForQualityCheck: Bool { neuralOwnerID != nil || !speechSegments.isEmpty || neuralPlayer != nil }
    fileprivate func failedOutputForQualityCheck(confirmation: Bool) { finishReadableResponse(then: confirmation ? .awaitingConfirmation : .success) }
}

private actor HeldLocalSpeech {
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

@main @MainActor struct VoiceQualityChecks {
    static var passed = 0
    static var failed = 0
    static func check(_ value: Bool, _ label: String) {
        print("\(value ? "PASS" : "FAIL") \(label)")
        if value { passed += 1 } else { failed += 1 }
    }
    static func main() async throws {
        let domain = "dev.suzzme.voice-quality.\(UUID())"
        guard let defaults = UserDefaults(suiteName: domain) else { exit(1) }
        defer { defaults.removePersistentDomain(forName: domain) }
        let assistant = AssistantStateController()
        let voice = VoiceSessionController(assistant: assistant, defaults: defaults)
        check(voice.deliveryStyle == .warm, "new voice settings start with restrained warm delivery")
        let installed = AVSpeechSynthesisVoice.speechVoices()
        let ranked = VoiceSessionController.rankedVoices(from: installed, locale: .current)
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        check(ranked.allSatisfy { $0.language.split(separator: "-").first.map(String.init) == language }, "quality never outranks correct response language")
        check(VoiceSessionController.rankedVoices(from: installed.reversed(), locale: .current).map(\.identifier) == ranked.map(\.identifier), "ranking deterministic regardless of inventory order")
        check(zip(ranked, ranked.dropFirst()).allSatisfy { $0.quality.rawValue >= $1.quality.rawValue }, "compatible quality order Premium Enhanced Standard")
        check(ranked.allSatisfy { !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }, "ordinary automatic voices exclude novelty and personal traits")
        let sameLanguageText = "Good morning. You have one important thing today. Your next class is at ten thirty, and you have two unfinished reminders."
        if language == "en" {
            check(voice.voiceForQualityCheck(sameLanguageText)?.identifier == voice.selectedVoiceIdentifier, "English production answer retains Settings regional voice")
        }
        if let chosen = ranked.last {
            voice.selectVoice(chosen)
            check(voice.voiceForQualityCheck(sameLanguageText)?.identifier == chosen.identifier, "explicit voice beats automatic ranking and language detection")
            let reopened = VoiceSessionController(assistant: assistant, defaults: defaults)
            check(reopened.explicitVoiceIdentifier == chosen.identifier, "audition choice persists after controller restart")
        }
        voice.selectAutomaticVoice()
        voice.deliveryStyle = .natural
        let utterance = voice.utteranceForQualityCheck(sameLanguageText)
        check(utterance.rate == AVSpeechUtteranceDefaultSpeechRate && utterance.pitchMultiplier == 1 && utterance.volume == 1, "production and preview factory preserves natural rate pitch volume")
        check(utterance.preUtteranceDelay == 0 && utterance.postUtteranceDelay == 0, "no artificial pre or post pauses")
        check(utterance.voice?.identifier == voice.selectedVoiceIdentifier, "production factory uses the resolved installed voice")
        voice.deliveryStyle = .warm
        let warm = voice.deliveryForQualityCheck(sameLanguageText, final: false)
        check(warm.rate < utterance.rate && warm.pitchMultiplier == 1.02 && warm.volume == 1,
            "warm delivery adds restrained expression without reducing audibility")
        check(warm.preUtteranceDelay == 0 && warm.postUtteranceDelay == 0.08,
            "warm delivery starts immediately and breathes only between chunks")
        let calm = voice.deliveryForQualityCheck(sameLanguageText, style: .calm, final: false)
        check(calm.rate < warm.rate && calm.pitchMultiplier == 0.98 && calm.postUtteranceDelay == 0.14,
            "calm delivery gives softer intonation and more room between phrases")
        let finalPhrase = voice.deliveryForQualityCheck(sameLanguageText)
        check(finalPhrase.postUtteranceDelay == 0, "final phrase never adds an artificial completion delay")
        let confirmationDelivery = voice.deliveryForQualityCheck(sameLanguageText, style: .natural)
        check(confirmationDelivery.rate == utterance.rate && confirmationDelivery.pitchMultiplier == 1 && confirmationDelivery.postUtteranceDelay == 0,
            "confirmation delivery can preserve the native neutral factory")
        check([warm,calm,finalPhrase,confirmationDelivery].allSatisfy { $0.speechString == sameLanguageText && $0.voice?.identifier == utterance.voice?.identifier },
            "expression preserves every fact, word range and explicit installed voice")
        voice.deliveryStyle = .calm
        let restoredDelivery = VoiceSessionController(assistant: assistant, defaults: defaults)
        check(restoredDelivery.deliveryStyle == .calm, "delivery preference survives restart")
        voice.speechRate = VoiceSessionController.speechRateRange.lowerBound
        check(voice.deliveryForQualityCheck(sameLanguageText).rate >= VoiceSessionController.speechRateRange.lowerBound,
            "expression respects the existing supported rate bounds")
        voice.speechRate = AVSpeechUtteranceDefaultSpeechRate
        voice.deliveryStyle = .natural
        if let selected = utterance.voice { print("Installed runtime voice: \(selected.name) / \(selected.language) / quality \(selected.quality.rawValue)") }
        let formatted = "# Tomorrow\n• **10:30** — AI class\n• 7:00 — Finish assignment\n[Details](https://example.com/private)\nhttps://example.com/raw"
        let spoken = VoiceSessionController.speechText(formatted)
        check(!spoken.contains("https") && !spoken.contains("**") && !spoken.contains("•") && !spoken.contains("#"), "markdown bullets and links never read literally")
        check(spoken.contains("10:30, AI class") && spoken.contains("7:00, Finish assignment") && spoken.contains("Details"), "timeline and link labels retain stated facts without guessed meridiem")
        let table = VoiceSessionController.speechText("| Time | Task |\n| --- | --- |\n| 10:30 | *AI class* |\nConfidence: 0.92\nRequest ID: private-id")
        check(table.contains("10:30, AI class") && !table.contains("|") && !table.contains("private-id") && !table.contains("0.92"), "table facts stay readable while internal metadata is omitted")
        check(VoiceSessionController.speechText("```swift\nfatalError()\n```https://example.com") .isEmpty, "code and URL only output has no spoken payload")
        check(VoiceSessionController.speechText("- [x] Submit report\n- [ ] Call club").contains("Completed: Submit report") && VoiceSessionController.speechText("- [ ] Call club").contains("Not completed: Call club"), "checkbox completion meaning survives formatting cleanup")
        let timestamp = VoiceSessionController.speechText("Meeting: 2026-10-06T10:30:00Z")
        check(!timestamp.contains("T10:30") && timestamp.contains("Meeting:"), "explicit ISO instant uses readable native local formatting")
        let long = (1...40).map { "Fact \($0) is stated in this complete sentence." }.joined(separator: " ")
        let concise = VoiceSessionController.speechText(long, concise: true)
        check(concise.count < long.count && concise.contains("Fact 1") && !concise.contains("Fact 40"), "ordinary long answer uses a concise factual prefix")
        check(VoiceSessionController.speechText(long).contains("Fact 40"), "explicit summary and confirmation modes retain complete narration")
        let confirmation = "Delete three reminders from Work tomorrow? This cannot be undone."
        check(VoiceSessionController.speechText(confirmation) == confirmation, "confirmation facts risks and quantity remain intact")
        let sentence = String(repeating: "word ", count: 60) + "."
        let chunks = VoiceSessionController.speechChunks(sentence + " " + sentence)
        check(chunks.count == 2 && chunks[0] == sentence.trimmingCharacters(in: .whitespaces), "bounded complete sentences stay intact across native utterances")
        check(VoiceSessionController.speechChunks(String(repeating: "x", count: 1200)).allSatisfy { $0.count <= 360 }, "oversized single token cannot defeat queue chunk bound")
        assistant.transition(to: .understanding)
        voice.failedOutputForQualityCheck(confirmation: false)
        check(assistant.state == .success, "failed audio preparation still completes readable response")
        voice.failedOutputForQualityCheck(confirmation: true)
        check(assistant.state == .awaitingConfirmation, "failed audio preparation preserves explicit confirmation")
        check(voice.speechEngine == .apple, "existing Apple voice remains selected until natural voice is chosen")
        voice.speechEngine = .natural
        check(VoiceSessionController(assistant: assistant, defaults: defaults).speechEngine == .natural,
            "natural engine choice persists without replacing Apple voice preference")
        for scenario in ["stop", "responses-off", "preview-stop", "engine-change"] {
            let held = HeldLocalSpeech()
            let pending = VoiceSessionController(assistant: assistant, defaults: defaults, localSpeechRenderer: { await held.render($0) })
            pending.speaksResponses = true
            pending.speechEngine = .natural
            if scenario == "preview-stop" { pending.previewSelectedVoice() }
            else { pending.speak("This is a complete English answer that stays on this device.") }
            for _ in 0..<100 { if await held.started { break }; try await Task.sleep(for: .milliseconds(1)) }
            check(pending.isPreparingSpeech && !pending.isSpeaking && pending.hasQueuedSpeechForQualityCheck,
                "\(scenario): generation is pending without claiming audible playback")
            switch scenario {
            case "responses-off": pending.speaksResponses = false
            case "preview-stop":
                pending.speaksResponses = false
                check(pending.isPreviewing, "explicit preview survives disabling response narration")
                pending.stopPreview()
            case "engine-change": pending.speechEngine = .apple
            default: pending.stopSpeech()
            }
            await held.release()
            for _ in 0..<100 { if await held.returned { break }; try await Task.sleep(for: .milliseconds(1)) }
            for _ in 0..<5 { await Task.yield() }
            check(!pending.isPreparingSpeech && !pending.isSpeaking && !pending.isPreviewing && !pending.hasQueuedSpeechForQualityCheck,
                "\(scenario): late audio cannot revive a retired queue or native fallback")
            pending.cancel()
        }
        assistant.transition(to: .understanding)
        voice.completeSpeechForQualityCheck()
        check(assistant.state == .understanding, "a completed speech callback cannot overwrite a newer understanding state")
        voice.cancel()
        print("Voice quality checks: \(passed) passed / \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
