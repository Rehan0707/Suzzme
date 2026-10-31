import Foundation
import Observation

enum ScreenAwarenessMode: String, CaseIterable, Sendable {
    case off, askWhenNeeded, onForVoice
    var title: String {
        switch self {
        case .off: "Off"
        case .askWhenNeeded: "Ask when needed"
        case .onForVoice: "On for screen-related voice requests"
        }
    }
}

@MainActor @Observable
final class ScreenAwarenessPreferences {
    private let defaults: UserDefaults
    var mode: ScreenAwarenessMode {
        didSet { defaults.set(mode.rawValue, forKey: Self.modeKey) }
    }
    var visualGuidance: Bool {
        didSet { defaults.set(visualGuidance, forKey: Self.guidanceKey) }
    }
    static let modeKey = "suzzme.screen.awareness"
    static let guidanceKey = "suzzme.screen.guidance"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Self.modeKey).flatMap(ScreenAwarenessMode.init(rawValue:)) ?? .askWhenNeeded
        visualGuidance = defaults.object(forKey: Self.guidanceKey) as? Bool ?? true
    }
}

enum ScreenContextPolicy {
    /// Screen relevance is explicit. Calendar/day queries never capture merely
    /// because voice capture is enabled. This is consent policy, not a model guess.
    static func isScreenQuestion(_ text: String) -> Bool {
        let value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return ScreenTextGuidance.requestedLabel(in: value) != nil
            || ["this screen", "my screen", "on screen", "on-screen", "looking at", "this error", "this window", "this dialog", "this button", "where do i click", "where do i fix", "point to"].contains(where: value.contains)
    }

    static func mayCapture(_ text: String, mode: ScreenAwarenessMode, isVoice: Bool, explicitlyAllowed: Bool) -> Bool {
        if isPersonalDayQuestion(text) && !isScreenQuestion(text) { return false }
        if explicitlyAllowed { return true }
        return isScreenQuestion(text) && mode == .onForVoice && isVoice
    }

    static func isPersonalDayQuestion(_ text: String) -> Bool {
        let value = text.lowercased()
        return ["what do i have today", "what do i have tomorrow", "what matters today", "what matters tomorrow", "my schedule", "daily summary", "summarize my day", "unfinished reminders", "overdue reminders"].contains(where: value.contains)
    }

    static func asksForGuidance(_ text: String) -> Bool {
        ["where", "point", "show me", "which button", "which setting"].contains(where: text.lowercased().contains)
    }
}

/// Deterministic guidance for an explicit literal label, independent of model vision.
/// OCR supplies geometry only; it never supplies instructions or chooses the target.
enum ScreenTextGuidance {
    static func answer(question: String, context: ScreenContext, wantsGuidance: Bool, now: Date = .now) -> SuzzmeScreenAnswer? {
        guard wantsGuidance, context.textRegionsComplete,
              context.isCurrent(requestID: context.requestID, now: now),
              let requested = requestedLabel(in: question) else { return nil }
        let target = normalized(requested).lowercased()
        // Count weak observations too: filtering confidence first could turn two
        // visible copies of a label into a falsely unique target.
        let matches = context.textRegions.filter { normalized($0.text).lowercased() == target }
        guard matches.count == 1, let match = matches.first, match.confidence >= 0.8 else { return nil }
        let label = normalized(match.text)
        let reference = SpatialReference(requestID: context.requestID, displayID: context.display.displayID,
            normalizedX: match.normalizedX + match.normalizedWidth / 2,
            normalizedY: match.normalizedY + match.normalizedHeight / 2,
            label: label, confidence: match.confidence)
        guard reference.isValid(for: context, requestID: context.requestID, now: now) else { return nil }
        return .init(text: "I found the visible label “\(label)”. I’m pointing to its text.", spatialReference: reference)
    }

    /// Parses the entire user utterance. This may select screen consent routing,
    /// but never authorizes capture. General questions such as “where is Paris” fail.
    static func requestedLabel(in question: String) -> String? {
        guard question.count <= 180, !question.contains(where: \.isNewline),
              !question.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespaces.contains($0)
              }) else { return nil }
        var body = normalized(question)
        if body.last == "?" || body.last == "." { body.removeLast(); body = normalized(body) }
        var hasScreenSuffix = false
        for suffix in [" on my screen", " on this screen"] where body.lowercased().hasSuffix(suffix) {
            body.removeLast(suffix.count)
            hasScreenSuffix = true
            break
        }
        let prefixes = ["point to ", "show me ", "where is "]
        guard let prefix = prefixes.first(where: { body.lowercased().hasPrefix($0) }) else { return nil }
        body.removeFirst(prefix.count)
        if body.lowercased().hasPrefix("the ") { body.removeFirst(4) }
        let hasButtonSuffix = body.lowercased().hasSuffix(" button")
        if hasButtonSuffix { body.removeLast(7) }
        guard prefix == "point to " || hasButtonSuffix || hasScreenSuffix else { return nil }
        body = normalized(body)

        let quotePairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'")]
        let isQuoted = quotePairs.contains { body.first == $0.0 && body.last == $0.1 && body.count >= 2 }
        if isQuoted {
            body.removeFirst()
            body.removeLast()
            body = normalized(body)
        } else {
            // An unquoted label contains words, not another instruction or clause.
            let clauseWords: Set<String> = ["and", "then", "also", "after", "before", "while", "but", "or", "please"]
            let words = body.lowercased().split(separator: " ").map(String.init)
            guard words.allSatisfy({ !clauseWords.contains($0) }) else { return nil }
            let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-'’&+"))
            guard body.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        }
        guard !body.isEmpty, body.count <= 80, !body.contains(where: \.isNewline),
              !body.contains("\""), !body.contains("“"), !body.contains("”"),
              PrivacyEngine().classify(body).policy != .neverProcess else { return nil }
        return body
    }

    private static func normalized(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

struct SuzzmeScreenAnswer: Sendable {
    let text: String
    var spatialReference: SpatialReference? = nil
    var usedOnDeviceModel = false
    var capabilityPending = false
}
