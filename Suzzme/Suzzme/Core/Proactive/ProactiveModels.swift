import Foundation

enum ProactiveLimits {
    static let informationCandidates = 20
    static let liveContextCandidates = 16
    static let memoryEvidence = 12
    static let evidencePerItem = 4
    static let briefingItems = 8
    static let opportunities = 5
    static let storedBriefings = 3
    static let storedOpportunities = 12
    static let deliveryRecords = 64
    static let narrationCharacters = 900
    static let opportunityRetention: TimeInterval = 7 * 86_400
    static let deliveryCooldown: TimeInterval = 6 * 3_600
    static let briefingFreshness: TimeInterval = 2 * 3_600
    static let dailyContextItems = 24
    static let dailyContextLimitations = 4
}

enum DailyContextEntryState: String, Codable, Sendable {
    case active, completed, cancelled, corrected, superseded
}

/// A compact, replaceable view of today. This is deliberately a snapshot,
/// not an event log and not a second memory store.
struct DailyContextEntry: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let kind: ProactiveCandidateKind
    let title: String
    let summary: String
    let source: String
    let sourceReference: String
    let effectiveAt: Date?
    let effectiveUntil: Date?
    let entities: [String]
    let sensitivity: SuzzmeContextSensitivity
    let freshness: ProactiveCandidateFreshness
    let state: DailyContextEntryState
    let confidence: Double
    /// A proposal boundary only. The Daily Context layer never writes memory.
    let mayBeDurableCandidate: Bool
}

struct DailyContextSnapshot: Codable, Sendable, Equatable {
    let localDay: Date
    let generatedAt: Date
    let entries: [DailyContextEntry]
    let sourceLimitations: [String]
    let timeZoneIdentifier: String?

    init(localDay: Date, generatedAt: Date, entries: [DailyContextEntry], sourceLimitations: [String], timeZoneIdentifier: String? = nil) {
        self.localDay = localDay
        self.generatedAt = generatedAt
        self.entries = entries
        self.sourceLimitations = sourceLimitations
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    var activeEntries: [DailyContextEntry] {
        entries.filter { $0.state == .active || $0.state == .corrected }
    }
}

struct ProactivePreferences: Codable, Sendable, Equatable {
    var dailyBriefingEnabled = true
    var briefingHour = 8
    var briefingMinute = 0
    var timeZoneIdentifier = TimeZone.current.identifier
    var timeCriticalEnabled = false
    var preparedAssistanceEnabled = true

    func validated() -> Self {
        var copy = self
        copy.briefingHour = min(max(copy.briefingHour, 0), 23)
        copy.briefingMinute = min(max(copy.briefingMinute, 0), 59)
        if TimeZone(identifier: copy.timeZoneIdentifier) == nil {
            copy.timeZoneIdentifier = TimeZone.current.identifier
        }
        return copy
    }
}

enum ProactiveCandidateKind: String, Codable, Sendable {
    case schedule, scheduleChange, cancellation, reminder, deadline, commitment, information
}

enum ProactiveCandidateFreshness: String, Codable, Sendable {
    case current, future, stale, expired, superseded
}

struct ProactiveCandidate: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let kind: ProactiveCandidateKind
    let title: String
    let summary: String
    let source: String
    let sourceReference: String
    let effectiveAt: Date?
    let effectiveUntil: Date?
    let entities: [String]
    let sensitivity: SuzzmeContextSensitivity
    let freshness: ProactiveCandidateFreshness
    let isCompleted: Bool
    let sourceHealthy: Bool
    let confidence: Double

    init(
        id: String,
        kind: ProactiveCandidateKind,
        title: String,
        summary: String,
        source: String,
        sourceReference: String,
        effectiveAt: Date? = nil,
        effectiveUntil: Date? = nil,
        entities: [String] = [],
        sensitivity: SuzzmeContextSensitivity = .personal,
        freshness: ProactiveCandidateFreshness = .current,
        isCompleted: Bool = false,
        sourceHealthy: Bool = true,
        confidence: Double = 1
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.source = source
        self.sourceReference = sourceReference
        self.effectiveAt = effectiveAt
        self.effectiveUntil = effectiveUntil
        self.entities = Array(entities.prefix(5))
        self.sensitivity = sensitivity
        self.freshness = freshness
        self.isCompleted = isCompleted
        self.sourceHealthy = sourceHealthy
        self.confidence = min(max(confidence, 0), 1)
    }
}

enum RelevanceEvidenceKind: String, Codable, Sendable {
    case explicitPreference, project, commitment, person, schedule, reminder, temporal, sourceReliability
}

struct RelevanceEvidence: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let kind: RelevanceEvidenceKind
    let explanation: String
    let reference: String
}

enum PersonalRelevance: String, Codable, Sendable { case irrelevant, useful, strong }

struct RelevanceDecision: Codable, Sendable, Equatable {
    let candidateID: String
    let relevance: PersonalRelevance
    let evidence: [RelevanceEvidence]
    var explanation: String {
        evidence.map(\.explanation).joined(separator: " ")
    }
}

enum TemporalUsefulness: String, Codable, Sendable {
    case obsolete, canWait, beforeNextBriefing, immediate
}

enum ProactiveDeliveryClassification: String, Codable, Sendable {
    case ignore, brief, timeCritical
}

enum ProactiveBriefingState: String, Codable, Sendable {
    case notPrepared, preparing, ready, delivered, partiallyDelivered, stale
}

enum ProactiveBriefingSectionKind: String, Codable, Sendable, CaseIterable {
    case opening, today, changes, needsAttention, later

    var title: String {
        switch self {
        case .opening: "Overview"
        case .today: "Today"
        case .changes: "Changes"
        case .needsAttention: "Needs Attention"
        case .later: "Later"
        }
    }
}

struct ProactiveBriefingItem: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let candidateID: String
    let kind: ProactiveCandidateKind
    let summary: String
    let whyRelevant: String
    let effectiveTime: Date?
    let sourceEvidence: [String]
    let relatedEntities: [String]
    let freshness: ProactiveCandidateFreshness
    let confidence: Double
    let sensitivity: SuzzmeContextSensitivity
    let delivery: ProactiveDeliveryClassification
}

struct ProactiveBriefingSection: Identifiable, Codable, Sendable, Equatable {
    let kind: ProactiveBriefingSectionKind
    let items: [ProactiveBriefingItem]
    var id: ProactiveBriefingSectionKind { kind }
}

struct ProactiveBriefing: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let createdAt: Date
    let coverageWindow: DateInterval
    let informationCutoff: Date
    let sections: [ProactiveBriefingSection]
    let sourceEvidence: [String]
    let liveContextEvidence: [String]
    let memoryEvidence: [String]
    let healthLimitations: [String]
    let narration: String
    var deliveryState: ProactiveBriefingState

    var items: [ProactiveBriefingItem] { sections.flatMap(\.items) }
    var isPartial: Bool { !healthLimitations.isEmpty }
}

enum SuzzmeOpportunityKind: String, Codable, Sendable { case deadline, conflict, meaningfulChange, preparation }
enum SuzzmeOpportunityState: String, Codable, Sendable { case active, dismissed, expired, superseded }
enum ProactiveCapabilityPreview: String, Codable, Sendable { case reminders, calendar }
enum ProactiveRiskPreview: String, Codable, Sendable { case reviewOnly, consequentialChange, destructiveChange }

struct PreparedAssistanceProposal: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let summary: String
    let suggestedRequest: String
    let requiredCapabilities: [ProactiveCapabilityPreview]
    let risk: ProactiveRiskPreview
    let expiresAt: Date
}

struct SuzzmeOpportunity: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let key: String
    let kind: SuzzmeOpportunityKind
    let createdAt: Date
    let expiresAt: Date
    let summary: String
    let reason: String
    let supportingInformation: [String]
    let supportingMemory: [String]
    let supportingLiveContext: [String]
    let possibleAssistance: PreparedAssistanceProposal?
    let requiredCapabilities: [ProactiveCapabilityPreview]
    let riskPreview: ProactiveRiskPreview
    let freshness: ProactiveCandidateFreshness
    let confidence: Double
    var state: SuzzmeOpportunityState
}

struct ProactiveHealthLimitation: Codable, Sendable, Equatable {
    let source: String
    let message: String
}

struct ProactiveInput: Sendable {
    let candidates: [ProactiveCandidate]
    let memories: [SuzzmeMemoryRecord]
    let healthLimitations: [ProactiveHealthLimitation]
    let generatedAt: Date

    init(candidates: [ProactiveCandidate], memories: [SuzzmeMemoryRecord] = [], healthLimitations: [ProactiveHealthLimitation] = [], generatedAt: Date = .now) {
        self.candidates = Array(candidates.prefix(ProactiveLimits.informationCandidates + ProactiveLimits.liveContextCandidates))
        self.memories = Array(memories.prefix(ProactiveLimits.memoryEvidence))
        self.healthLimitations = Array(healthLimitations.prefix(4))
        self.generatedAt = generatedAt
    }
}

struct ProactiveSnapshot: Codable, Sendable, Equatable {
    let generatedAt: Date
    let briefing: ProactiveBriefing?
    let opportunities: [SuzzmeOpportunity]
    let timeCriticalItems: [ProactiveBriefingItem]
    let dailyContext: DailyContextSnapshot?

    init(
        generatedAt: Date,
        briefing: ProactiveBriefing?,
        opportunities: [SuzzmeOpportunity],
        timeCriticalItems: [ProactiveBriefingItem],
        dailyContext: DailyContextSnapshot? = nil
    ) {
        self.generatedAt = generatedAt
        self.briefing = briefing
        self.opportunities = opportunities
        self.timeCriticalItems = timeCriticalItems
        self.dailyContext = dailyContext
    }
}

enum ProactiveError: Error, Sendable {
    case staleGeneration, disabled, invalidState, persistence
}
