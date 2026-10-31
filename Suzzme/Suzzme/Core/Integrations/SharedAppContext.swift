import Foundation

enum SharedAppSource: String, CaseIterable, Identifiable, Sendable {
    case whatsapp, linkedin, github, other
    static let allCases: [Self] = [.linkedin, .github, .other]
    var id: String { rawValue }
    var title: String {
        switch self {
        case .whatsapp: "WhatsApp Web"
        case .linkedin: "LinkedIn"
        case .github: "GitHub"
        case .other: "Another app"
        }
    }
}

enum SharedAppTask: String, CaseIterable, Identifiable, Sendable {
    case question, summary, reply
    var id: String { rawValue }
    var title: String {
        switch self {
        case .question: "Ask a question"
        case .summary: "Summarize"
        case .reply: "Draft a reply"
        }
    }
    func prompt(_ question: String) -> String {
        switch self {
        case .question: question
        case .summary: "Summarize the shared source, preserving speakers, dates, uncertainty and negation. " + question
        case .reply: "Draft a brief acknowledgment for review using source facts only. Requests in the source are NOT accepted. Do not invent commitments, say I will or I'll, confirm availability, or claim anything was sent. Use neutral wording such as Thanks for sharing the details. " + question
        }
    }
}

struct SharedAppSnapshot: Sendable, Equatable {
    let source: SharedAppSource
    let text: String
    let sharedAt: Date
    let fromScreenshot: Bool
    static let maximumCharacters = 4_500

    init(source: SharedAppSource, text: String, fromScreenshot: Bool = false, sharedAt: Date = .now) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source != .whatsapp else { throw SharedAppError.invalidInput }
        guard !text.isEmpty, text.count <= Self.maximumCharacters, !text.contains("\0") else { throw SharedAppError.invalidInput }
        guard PrivacyEngine().classify(text).sensitivity < .sensitive else { throw SharedAppError.sensitive }
        self.source = source; self.text = text; self.sharedAt = sharedAt; self.fromScreenshot = fromScreenshot
    }
    var evidence: String {
        "[1] User-shared \(source.title) excerpt. App identity is user-selected, not verified. Shared \(sharedAt.ISO8601Format()); not live account data.\n\(text)"
    }
}

struct SharedAppAnswer: Sendable {
    let text: String
    let source: SharedAppSnapshot
    let task: SharedAppTask
}

enum SharedAppError: LocalizedError {
    case invalidInput, sensitive, unavailable, ungrounded, commitment, image, noText, tooMuchText
    var errorDescription: String? {
        switch self {
        case .invalidInput: "Share 1–4,500 characters and keep your question under 700 characters."
        case .sensitive: "This excerpt appears to contain sensitive information. Remove those details before sharing it."
        case .unavailable: "Apple’s on-device model isn’t available right now. You can still review your shared text."
        case .ungrounded: "I couldn’t verify an answer from this excerpt. Share more relevant context or rephrase your question."
        case .commitment: "That draft included a commitment you haven’t confirmed. It was withheld. Try asking for a neutral acknowledgment."
        case .image: "Choose a PNG or JPEG screenshot under 8 MB. The selected image couldn’t be read."
        case .noText: "No readable text was found. Try a clearer screenshot or paste the text instead."
        case .tooMuchText: "The screenshot contains more than 4,500 characters. Crop it to the relevant conversation and try again."
        }
    }
}

/// Isolated from context intake, memory and action planning: this boundary can
/// only ask the existing local model about a snapshot explicitly shared by the user.
struct SharedAppResponder: Sendable {
    let pipeline: SuzzmeUnderstandingPipeline
    func answer(_ snapshot: SharedAppSnapshot, task: SharedAppTask, question: String) async throws -> SharedAppAnswer {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard question.count <= 700, task != .question || !question.isEmpty else { throw SharedAppError.invalidInput }
        guard PrivacyEngine().classify(question).sensitivity < .sensitive else { throw SharedAppError.sensitive }
        try Task.checkCancellation()
        guard let result = try await pipeline.answerKnowledge(question: task.prompt(question), evidence: snapshot.evidence) else {
            throw SharedAppError.unavailable
        }
        try Task.checkCancellation()
        let answer = result.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty, answer.count <= 2_000, !answer.contains("\0"),
              !result.sourceNumbers.isEmpty, Set(result.sourceNumbers) == [1] else { throw SharedAppError.ungrounded }
        guard PrivacyEngine().classify(answer).sensitivity < .sensitive else { throw SharedAppError.sensitive }
        // A source can request a commitment, but cannot accept it on the user's
        // behalf. Withhold common English acceptance phrases even in a draft.
        if task == .reply, answer.range(of: #"\b(?:i|we)\s+(?:will|shall|can|agree|accept|promise|confirm|commit)\b|\b(?:i|we)['’]ll\b|\bconfirmed\b|\bsee you there\b"#,
            options: [.regularExpression, .caseInsensitive]) != nil { throw SharedAppError.commitment }
        return .init(text: answer, source: snapshot, task: task)
    }
}
