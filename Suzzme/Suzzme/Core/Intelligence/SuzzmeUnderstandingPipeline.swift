import Foundation

struct SuzzmeUnderstandingResult: Sendable {
    let items: [SuzzmeItem]
    let reasons: [UUID: String]
    let skippedDuplicateCount: Int
    let capability: IntelligenceCapability

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

actor SuzzmeUnderstandingPipeline {
    private let primary: any SuzzmeIntelligenceService
    private let fallback: any SuzzmeIntelligenceService

    init(
        primary: any SuzzmeIntelligenceService = SuzzmeIntelligenceProvider.makePrimary(),
        fallback: any SuzzmeIntelligenceService = BasicIntelligenceService()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    func capability() async -> IntelligenceCapability { await primary.capability() }

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
        if capability.usesFoundationModels {
            do {
                extracted = try await primary.understand(text: normalized, referenceDate: referenceDate)
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
        return SuzzmeUnderstandingResult(items: items, reasons: reasons, skippedDuplicateCount: skipped, capability: capability)
    }
}

enum SuzzmeIntelligenceProvider {
    static func makePrimary() -> any SuzzmeIntelligenceService {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return AppleIntelligenceService()
        }
        #endif
        return BasicIntelligenceService()
    }
}
