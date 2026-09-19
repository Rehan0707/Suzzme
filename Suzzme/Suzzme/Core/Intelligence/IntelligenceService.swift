import Foundation

protocol SuzzmeIntelligenceService: Sendable {
    func capability() async -> IntelligenceCapability
    func understand(text: String, referenceDate: Date) async throws -> [ExtractedSuzzmeItem]
    func summarize(text: String) async throws -> String
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

    var errorDescription: String? {
        switch self {
        case .emptyInput: "Paste something for Suzzme to understand."
        case .unavailable(let capability): capability.displayDescription
        case .invalidOutput: "Suzzme could not find useful information in that text."
        case .persistenceUnavailable: "Local storage is unavailable on this device."
        case .generationInProgress: "Suzzme is already understanding something."
        }
    }
}
