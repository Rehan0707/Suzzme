import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Uses Apple's on-device system model when the OS and device report it ready.
/// The model receives only the current text; no conversation history is retained.
@available(iOS 26.0, macOS 26.0, *)
actor AppleIntelligenceService: SuzzmeIntelligenceService {
    private let model = SystemLanguageModel.default
    private let session = LanguageModelSession(
        instructions: """
        You analyze personal information. Extract only facts supported by the input.
        Return only useful events, tasks, deadlines, reminders, or information.
        Never invent a person, date, place, deadline, or commitment. Use a missing date phrase when no date is explicitly supported.
        """
    )
    private var generationIsInProgress = false

    func capability() async -> IntelligenceCapability {
        switch model.availability {
        case .available: .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: .unsupportedDevice
            case .appleIntelligenceNotEnabled: .appleIntelligenceDisabled
            case .modelNotReady: .modelNotReady
            @unknown default: .unsupportedDevice
            }
        }
    }

    func understand(text: String, referenceDate: Date = .now) async throws -> [ExtractedSuzzmeItem] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw SuzzmeIntelligenceError.emptyInput }
        guard await capability() == .available else { throw SuzzmeIntelligenceError.unavailable(await capability()) }
        try beginGeneration()
        defer { generationIsInProgress = false }

        let response = try await session.respond(
            to: """
            Reference date: \(referenceDate.formatted(date: .abbreviated, time: .shortened))
            Input: \(normalized)
            """,
            generating: [FoundationGeneratedItem].self,
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 550)
        )

        let items = response.content.compactMap { generated in
            let date = generated.datePhrase.flatMap { dateIfSupported($0, by: normalized, referenceDate: referenceDate) }
            return ExtractedSuzzmeItem(
                title: generated.title,
                summary: generated.summary,
                category: Self.category(from: generated.category),
                priority: Self.priority(from: generated.priority),
                dueDate: date,
                confidence: generated.confidence,
                reason: generated.reason
            )
        }
        guard !items.isEmpty else { throw SuzzmeIntelligenceError.invalidOutput }
        return items
    }

    func summarize(text: String) async throws -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw SuzzmeIntelligenceError.emptyInput }
        guard await capability() == .available else { throw SuzzmeIntelligenceError.unavailable(await capability()) }
        try beginGeneration()
        defer { generationIsInProgress = false }
        let response = try await session.respond(
            to: "Summarize this in one factual sentence, without adding facts: \(normalized)",
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 90)
        )
        return response.content
    }

    private static func category(from value: String) -> SuzzmeItem.Category {
        SuzzmeItem.Category(rawValue: value.lowercased()) ?? .information
    }

    private static func priority(from value: String) -> SuzzmeItem.Priority {
        switch value.lowercased() {
        case "critical", "urgent": .urgent
        case "high", "important": .important
        case "low": .low
        default: .normal
        }
    }

    private func beginGeneration() throws {
        guard !generationIsInProgress else { throw SuzzmeIntelligenceError.generationInProgress }
        generationIsInProgress = true
    }

    private func dateIfSupported(_ phrase: String, by source: String, referenceDate: Date) -> Date? {
        let source = source.lowercased()
        let phrase = phrase.lowercased()
        let anchors = ["today", "tomorrow", "tonight", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        guard anchors.contains(where: { phrase.contains($0) && source.contains($0) }) else { return nil }
        return SuzzmeDateParser.date(in: phrase, referenceDate: referenceDate)
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A single source-grounded Suzzme item.")
private struct FoundationGeneratedItem {
    @Guide(description: "A short factual title.") var title: String
    @Guide(description: "A concise factual summary.") var summary: String
    @Guide(description: "One of: task, event, deadline, opportunity, reminder, information.") var category: String
    @Guide(description: "One of: low, normal, high, critical.") var priority: String
    @Guide(description: "The stated date wording only, such as tomorrow at 5 PM. Omit if unsupported.") var datePhrase: String?
    @Guide(description: "A number from 0 through 1 based on evidence in the input.") var confidence: Double
    @Guide(description: "A brief explanation of the input evidence.") var reason: String
}
#endif
