import Foundation

/// Keeps partial recognition updates out of SuzzmeCore and accepts one final utterance.
struct VoiceTranscriptFinalizer: Sendable {
    static let maximumCharacters = 6_000
    private(set) var hasFinalized = false
    mutating func reset() { hasFinalized = false }
    mutating func acceptFinal(_ transcript: String) -> String? {
        guard !hasFinalized else { return nil }
        hasFinalized = true
        let value = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.count > Self.maximumCharacters ? nil : value
    }
}
