import Foundation

protocol SuzzmeIntelligenceService: Sendable {
    func capability() async -> IntelligenceCapability
    func understand(text: String, referenceDate: Date) async throws -> [ExtractedSuzzmeItem]
    func summarize(text: String) async throws -> String
    func answerScreen(question: String, context: ScreenContext, wantsGuidance: Bool) async throws -> SuzzmeScreenAnswer
    func answerScreen(question: String, context: ScreenContext, wantsGuidance: Bool, personalFacts: String) async throws -> SuzzmeScreenAnswer
    /// Text-only, read-only answer. It has no tools, extraction or write authority.
    func answerQuestion(question: String, facts: String, conversation: String, screenUnderstanding: String?) async throws -> String?
    func selectKnowledge(from text: String) async throws -> SuzzmeKnowledgeSelection
    func answerKnowledge(question: String, evidence: String) async throws -> SuzzmeKnowledgeReply?
}

/// Typed, read-only results. Neither selection nor answering grants action authority.
struct SuzzmeKnowledgeSelection: Sendable {
    let keep: Bool
    let sensitive: Bool
    let excerpts: [String]
}

struct SuzzmeKnowledgeReply: Sendable {
    let answer: String
    let sourceNumbers: [Int]
}

extension SuzzmeIntelligenceService {
    func selectKnowledge(from text: String) async throws -> SuzzmeKnowledgeSelection {
        throw SuzzmeIntelligenceError.unavailable(await capability())
    }

    func answerKnowledge(question: String, evidence: String) async throws -> SuzzmeKnowledgeReply? { nil }

    func answerScreen(question: String, context: ScreenContext, wantsGuidance: Bool, personalFacts: String) async throws -> SuzzmeScreenAnswer {
        try await answerScreen(question: question, context: context, wantsGuidance: wantsGuidance)
    }

    func answerQuestion(question: String, facts: String, conversation: String, screenUnderstanding: String?) async throws -> String? {
        try Task.checkCancellation()
        return nil
    }

    /// The deterministic service cannot infer a visual meaning. It may quote
    /// bounded, checked structural text without pretending to understand pixels.
    func answerScreen(question: String, context: ScreenContext, wantsGuidance: Bool) async throws -> SuzzmeScreenAnswer {
        try Task.checkCancellation()
        let text = context.accessibilityText ?? context.recognizedText
        if let text, !text.isEmpty {
            return .init(text: "Visual understanding isn’t available on this device right now. The screen’s text includes: \(String(text.prefix(900)))", capabilityPending: true)
        }
        return .init(text: "I can capture this screen, but on-device visual understanding isn’t available on this device right now. You can describe what you need help with.", capabilityPending: true)
    }
}

/// Step 1's briefing boundary remains independent from the understanding pipeline.
protocol IntelligenceService: Sendable {
    func dailyBriefing(for date: Date, name: String) async throws -> DailyBriefing
}

enum SuzzmeIntelligenceError: LocalizedError, Sendable, Equatable {
    case emptyInput
    case unavailable(IntelligenceCapability)
    case invalidOutput
    case persistenceUnavailable
    case generationInProgress
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .emptyInput: "Paste something for Suzzme to understand."
        case .unavailable(let capability): capability.displayDescription
        case .invalidOutput: "Suzzme could not find useful information in that text."
        case .persistenceUnavailable: "Local storage is unavailable on this device."
        case .generationInProgress: "Suzzme is already understanding something."
        case .generationFailed: "Apple’s on-device model couldn’t complete that response. Please try again."
        }
    }
}
