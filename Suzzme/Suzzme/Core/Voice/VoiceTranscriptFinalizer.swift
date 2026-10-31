import Foundation

/// Keeps partial recognition updates out of SuzzmeCore and accepts one final utterance.
struct VoiceTranscriptFinalizer: Sendable {
    static let maximumCharacters = 6_000
    private(set) var hasFinalized = false
    private(set) var committedSegments: [String] = []
    var committedTranscript: String { committedSegments.joined(separator: " ") }

    mutating func reset() { hasFinalized = false; committedSegments.removeAll(keepingCapacity: true) }

    /// Only genuine finals enter this buffer. Partial text stays in the controller.
    mutating func appendFinalSegment(_ transcript: String) -> String? {
        guard !hasFinalized, committedSegments.count < 64 else { return nil }
        let value = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = committedSegments.isEmpty ? value : committedTranscript + " " + value
        guard !value.isEmpty, combined.count <= Self.maximumCharacters else { return nil }
        committedSegments.append(value)
        return combined
    }
    mutating func acceptFinal(_ transcript: String) -> String? {
        guard !hasFinalized else { return nil }
        hasFinalized = true
        let value = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.count > Self.maximumCharacters ? nil : value
    }
}
