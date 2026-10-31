import Foundation

struct SuzzmeUnderstandingResult: Sendable {
    let items: [SuzzmeItem]
    let reasons: [UUID: String]
    let skippedDuplicateCount: Int
    let capability: IntelligenceCapability
    let usedOnDeviceModel: Bool

    func reason(for item: SuzzmeItem) -> String { reasons[item.id] ?? "No extraction detail available." }
}

/// Stable enough for repeated identical content, without preserving raw text.
enum SuzzmeItemFingerprint {
    static func make(for item: SuzzmeItem) -> String {
        let title = item.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let day = item.dueDate.map { ISO8601DateFormatter().string(from: $0).prefix(10) } ?? "none"
        return "\(item.source.rawValue)|\(item.category.rawValue)|\(title)|\(day)"
    }
}

struct SuzzmeGroundedSummary: Sendable {
    let text: String
    let usedOnDeviceModel: Bool
}

actor SuzzmeUnderstandingPipeline {
    private let primary: any SuzzmeIntelligenceService
    private let fallback: any SuzzmeIntelligenceService

    init(
        primary: any SuzzmeIntelligenceService = SuzzmeIntelligenceProvider.makePrimary(),
        fallback: any SuzzmeIntelligenceService = SuzzmeIntelligenceProvider.makeFallback()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    func capability() async -> IntelligenceCapability { await primary.capability() }

    func selectKnowledge(from text: String) async throws -> SuzzmeKnowledgeSelection {
        try Task.checkCancellation()
        let capability = await primary.capability()
        guard capability.usesFoundationModels else { throw SuzzmeIntelligenceError.unavailable(capability) }
        let selection = try await primary.selectKnowledge(from: text)
        try Task.checkCancellation()
        return selection
    }

    func answerKnowledge(question: String, evidence: String) async throws -> SuzzmeKnowledgeReply? {
        try Task.checkCancellation()
        guard await primary.capability().usesFoundationModels else { return nil }
        let reply = try await primary.answerKnowledge(question: question, evidence: evidence)
        try Task.checkCancellation()
        return reply
    }

    func answerScreen(question: String, context: ScreenContext, wantsGuidance: Bool, personalFacts: String = "") async throws -> SuzzmeScreenAnswer {
        try Task.checkCancellation()
        // A literal, uniquely measured OCR label needs neither model vision nor
        // a generated coordinate. Screen content never chooses the target.
        if let answer = ScreenTextGuidance.answer(question: question, context: context, wantsGuidance: wantsGuidance) {
            return answer
        }
        if wantsGuidance, let label = ScreenTextGuidance.requestedLabel(in: question) {
            // Ambiguous, incomplete or weak OCR must not fall through to a
            // model-generated point for this same literal target.
            return .init(text: "I couldn’t locate one clear match for “\(label)” in this screen’s text. Try a more specific visible label.")
        }
        guard await primary.capability().usesFoundationModels else {
            return try await fallback.answerScreen(question: question, context: context, wantsGuidance: wantsGuidance)
        }
        do {
            return try await primary.answerScreen(question: question, context: context, wantsGuidance: wantsGuidance, personalFacts: personalFacts)
        } catch is CancellationError { throw CancellationError() }
        catch {
            return try await fallback.answerScreen(question: question, context: context, wantsGuidance: wantsGuidance)
        }
    }

    func answerQuestion(question: String, facts: String, conversation: String, screenUnderstanding: String? = nil) async throws -> String? {
        try Task.checkCancellation()
        guard await primary.capability().usesFoundationModels else { return nil }
        do {
            guard let result = try await primary.answerQuestion(question: question, facts: facts, conversation: conversation, screenUnderstanding: screenUnderstanding) else { return nil }
            try Task.checkCancellation()
            let answer = result.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty, answer.count <= 2_000,
                  PrivacyEngine().classify(answer).policy != .neverProcess else { return nil }
            return answer
        } catch is CancellationError {
            throw CancellationError()
        } catch SuzzmeIntelligenceError.generationInProgress {
            throw SuzzmeIntelligenceError.generationInProgress
        } catch {
            // A ready model that fails generation is different from an
            // unavailable model. Preserve that distinction for the UI instead
            // of silently presenting deterministic fallback as model output.
            throw SuzzmeIntelligenceError.generationFailed
        }
    }

    /// Email text is untrusted; the primary Apple model's extraction is
    /// source-grounded before it can contribute to the Daily Summary.
    func summarizeImportantEmail(_ text: String, referenceDate: Date = .now) async throws -> SuzzmeGroundedSummary {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw SuzzmeIntelligenceError.emptyInput }
        let capability = await primary.capability()
        guard capability.usesFoundationModels else { throw SuzzmeIntelligenceError.unavailable(capability) }
        let extracted = try await primary.understand(text: input, referenceDate: referenceDate)
        try Task.checkCancellation()
        guard let item = extracted.first(where: { ($0.priority == .important || $0.priority == .urgent) && $0.confidence >= 0.6 }) else {
            return .init(text: "", usedOnDeviceModel: true)
        }
        let summary = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty, PrivacyEngine().classify(summary).policy != .neverProcess else {
            throw SuzzmeIntelligenceError.invalidOutput
        }
        return .init(text: summary, usedOnDeviceModel: true)
    }

    func summarizeGroundedFacts(_ facts: String) async throws -> SuzzmeGroundedSummary {
        let normalized = facts.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw SuzzmeIntelligenceError.emptyInput }
        guard await primary.capability().usesFoundationModels else {
            return SuzzmeGroundedSummary(text: normalized, usedOnDeviceModel: false)
        }
        do {
            let summary = try await primary.summarize(text: normalized)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else { throw SuzzmeIntelligenceError.invalidOutput }
            return SuzzmeGroundedSummary(text: summary, usedOnDeviceModel: true)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return SuzzmeGroundedSummary(text: normalized, usedOnDeviceModel: false)
        }
    }

    func process(
        _ content: String,
        source: SuzzmeItem.Source = .manual,
        referenceDate: Date = .now,
        existingFingerprints: Set<String> = []
    ) async throws -> SuzzmeUnderstandingResult {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw SuzzmeIntelligenceError.emptyInput }

        let capability = await primary.capability()
        let extracted: [ExtractedSuzzmeItem]
        var usedOnDeviceModel = false
        if capability.usesFoundationModels {
            do {
                extracted = try await primary.understand(text: normalized, referenceDate: referenceDate)
                usedOnDeviceModel = true
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                extracted = try await fallback.understand(text: normalized, referenceDate: referenceDate)
            }
        } else {
            extracted = try await fallback.understand(text: normalized, referenceDate: referenceDate)
        }

        let candidates = extracted.map { $0.makeSuzzmeItem(source: source, createdAt: referenceDate) }
        let reasons = Dictionary(uniqueKeysWithValues: zip(candidates.map(\.id), extracted.map(\.reason)))
        var fingerprints = existingFingerprints
        var items: [SuzzmeItem] = []
        var skipped = 0
        for item in candidates {
            let fingerprint = SuzzmeItemFingerprint.make(for: item)
            if fingerprints.contains(fingerprint) {
                skipped += 1
            } else {
                fingerprints.insert(fingerprint)
                items.append(item)
            }
        }
        return SuzzmeUnderstandingResult(
            items: items,
            reasons: reasons,
            skippedDuplicateCount: skipped,
            capability: capability,
            usedOnDeviceModel: usedOnDeviceModel
        )
    }
}

enum SuzzmeIntelligenceProvider {
    static func makePrimary() -> any SuzzmeIntelligenceService {
        #if os(iOS)
        return CompanionOnlyIntelligenceService()
        #else
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return AppleIntelligenceService()
        }
        #endif
        return BasicIntelligenceService()
        #endif
    }

    static func makeFallback() -> any SuzzmeIntelligenceService {
        #if os(iOS)
        CompanionOnlyIntelligenceService()
        #else
        BasicIntelligenceService()
        #endif
    }
}

/// The phone receives prepared results. Alternate entry points cannot start
/// language-model generation or local extraction through this provider.
struct CompanionOnlyIntelligenceService: SuzzmeIntelligenceService {
    func capability() async -> IntelligenceCapability { .companionOnly }
    func understand(text: String, referenceDate: Date) async throws -> [ExtractedSuzzmeItem] {
        throw SuzzmeIntelligenceError.unavailable(.companionOnly)
    }
    func summarize(text: String) async throws -> String {
        throw SuzzmeIntelligenceError.unavailable(.companionOnly)
    }
}
