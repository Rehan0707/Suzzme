import Foundation
import CryptoKit

enum InformationSourceID: String, Codable, CaseIterable, Sendable, Identifiable {
    case calendar, reminders, gmail, messages, whatsapp, watchedWeb, connectedApps, localKnowledge
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gmail: "Gmail"
        case .messages: "Messages"
        case .whatsapp: "WhatsApp"
        case .watchedWeb: "Watched Links"
        case .connectedApps: "Connected apps"
        case .localKnowledge: "Local Knowledge"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        }
    }
}
enum SelectedMessageImportResult: Sendable, Equatable { case imported, rejected, unavailable }
enum InformationKind: String, Codable, Sendable { case eventUpdate, scheduleChange, locationChange, reminderChange, emailUpdate, cancellation, generalUpdate }
enum InformationObjectState: String, Codable, Sendable { case active, completed, cancelled, absent }
enum InformationFreshness: String, Sendable { case current, future, stale, expired, superseded }
enum InformationHealthState: String, Codable, Sendable {
    case disabled, healthy, permissionRequired, permissionDenied, authorizationExpired, temporarilyUnavailable, unsupported, stale, error
    var label: String {
        switch self {
        case .disabled: "Updates off"
        case .healthy: "Checked successfully"
        case .permissionRequired: "Permission needed"
        case .permissionDenied: "Access unavailable"
        case .authorizationExpired: "Access changed"
        case .temporarilyUnavailable: "Try again later"
        case .unsupported: "Not supported"
        case .stale: "Refresh needed"
        case .error: "Could not save updates"
        }
    }
}
enum InformationLimits {
    static let intake = 100
    static let content = 720
    static let persistedPerCycle = 200
    static let rawContent = 16384
    static let retrieval = 20
    static let records = 300
    static let versions = 3
    static let retention: TimeInterval = 30 * 86400
    static let freshness: TimeInterval = 6 * 3600
    static let debounce: TimeInterval = 60
    static let selectedMessageCharacters = 720
}
struct InformationObservation: Sendable {
    let externalID: String
    let title: String
    var privateNotes = ""
    var location = ""
    var entities: [String] = []
    let modifiedAt: Date
    var effectiveAt: Date?
    var effectiveUntil: Date?
    var state: InformationObjectState = .active
    var kindHint: InformationKind?
    var isAllDay: Bool?
}
struct InformationBatch: Sendable {
    let observations: [InformationObservation]
    /// False means absence must never be interpreted as deletion.
    let complete: Bool
    let window: DateInterval
    var validatedExternalIDs: [String] = []
    var coversUndated: Bool = false
    var coversOpenReminders: Bool = false
}
struct InformationEvent: Identifiable, Sendable, Equatable {
    let id: UUID
    let source: InformationSourceID
    let externalID: String
    let kind: InformationKind
    let title: String
    let location: String
    let entities: [String]
    let sourceUpdatedAt: Date
    let observedAt: Date
    let effectiveAt: Date?
    let effectiveUntil: Date?
    let expiresAt: Date
    let sensitivity: SuzzmeContextSensitivity
    let fingerprint: String
    let objectState: InformationObjectState
    let supersedes: UUID?
    let isSuperseded: Bool
    let normalizationVersion: Int
    var isAllDay: Bool? = nil

    func freshness(at now: Date) -> InformationFreshness {
        if isSuperseded { return .superseded }
        if expiresAt <= now { return .expired }
        if now.timeIntervalSince(observedAt) > InformationLimits.freshness { return .stale }
        if let effectiveAt, effectiveAt > now { return .future }
        return .current
    }
    var summary: String {
        if objectState == .absent { return "No longer present in the checked range: \(title)" }
        return switch kind {
        case .cancellation: "No longer active: \(title)"
        case .scheduleChange: "Schedule updated: \(title)"
        case .locationChange: "Location updated: \(title) — \(location)"
        case .reminderChange: objectState == .completed ? "Completed: \(title)" : "Reminder updated: \(title)"
        case .emailUpdate: title
        case .eventUpdate, .generalUpdate: title
        }
    }
}
struct InformationHealth: Identifiable, Sendable {
    let source: InformationSourceID
    let enabled: Bool
    let state: InformationHealthState
    let lastAttempt: Date?
    let lastSuccess: Date?
    let checkpoint: Date?
    let considered: Int
    let accepted: Int
    let rejected: Int
    let deduplicated: Int
    let consolidated: Int
    let expired: Int
    let limited: Bool
    var id: InformationSourceID { source }
}
struct InformationQuery: Sendable {
    var sources: Set<InformationSourceID> = Set(InformationSourceID.allCases)
    var since: Date?
    var window: DateInterval?
    var entity: String?
    var limit = InformationLimits.retrieval
    var includeFuture = true
}
enum InformationError: Error { case unsupported, disabled, staleCycle, unavailable, malformed, authorizationRequired, authorizationExpired, permissionDenied, clearConfirmationRequired, persistence }

protocol InformationSource: Sendable {
    var id: InformationSourceID { get }
    func authorization() async -> InformationHealthState
    func fetch(now: Date, checkpoint: Date?) async throws -> InformationBatch
    func fetchForBriefing(now: Date, checkpoint: Date?, cutoff: Date, calendar: Calendar) async throws -> InformationBatch
    func owns(_ event: InformationEvent) async -> Bool
    func permits(_ event: InformationEvent, now: Date) async -> Bool
    func didCommit(_ batch: InformationBatch) async
}
extension InformationSource {
    func fetchForBriefing(now: Date, checkpoint: Date?, cutoff: Date, calendar: Calendar) async throws -> InformationBatch {
        try await fetch(now: now, checkpoint: checkpoint)
    }
    func owns(_ event: InformationEvent) async -> Bool { false }
    func permits(_ event: InformationEvent, now: Date) async -> Bool { true }
    func didCommit(_ batch: InformationBatch) async {}
}
struct InformationSourceRegistry: Sendable {
    private let sources: [InformationSourceID: any InformationSource]
    init(_ sources: [any InformationSource]) {
        self.sources = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    func source(_ id: String) throws -> any InformationSource {
        guard let key = InformationSourceID(rawValue: id), let source = sources[key] else { throw InformationError.unsupported }
        return source
    }
}

enum InformationNormalizer {
    static func normalize(_ observation: InformationObservation, source: InformationSourceID, now: Date) -> InformationEvent? {
        let text = ([observation.title, observation.privateNotes, observation.location, observation.externalID] + observation.entities).joined(separator: " ")
        guard text.count <= InformationLimits.rawContent, !observation.externalID.isEmpty, observation.externalID.count <= 512,
              observation.modifiedAt.timeIntervalSince1970.isFinite, observation.modifiedAt <= now.addingTimeInterval(300),
              [observation.effectiveAt, observation.effectiveUntil].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }) else { return nil }
        let decision = PrivacyEngine().classify(text)
        guard decision.policy != .neverProcess else { return nil }
        let titleLimit = source == .messages ? InformationLimits.selectedMessageCharacters : 240
        let title = String(observation.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(titleLimit))
        guard !title.isEmpty else { return nil }
        if let start = observation.effectiveAt, let end = observation.effectiveUntil, end < start { return nil }
        let location = String(observation.location.prefix(180))
        let entities = observation.entities.prefix(5).map { String($0.prefix(60)) }.sorted()
        var semantics = [source.rawValue, observation.externalID, title, location, entities.joined(separator: "|"), observation.state.rawValue,
                         observation.effectiveAt.map { String($0.timeIntervalSince1970) } ?? "", observation.effectiveUntil.map { String($0.timeIntervalSince1970) } ?? ""]
        // Preserve legacy fingerprints when no authoritative all-day metadata exists.
        if let isAllDay = observation.isAllDay { semantics.append("allDay:\(isAllDay)") }
        // Length-prefixed fields avoid concatenation collisions.
        let key = semantics.map { "\($0.utf8.count):\($0)" }.joined()
        let fingerprint = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let expiry = min(now.addingTimeInterval(InformationLimits.retention), max(now.addingTimeInterval(86400), (observation.effectiveUntil ?? observation.effectiveAt ?? now.addingTimeInterval(6 * 86400)).addingTimeInterval(86400)))
        let kind = observation.state == .cancelled ? InformationKind.cancellation
            : observation.kindHint ?? (source == .calendar ? .eventUpdate : source == .reminders ? .reminderChange : .generalUpdate)
        return .init(id: UUID(), source: source, externalID: observation.externalID, kind: kind,
                     title: title, location: location, entities: entities, sourceUpdatedAt: observation.modifiedAt, observedAt: now,
                     effectiveAt: observation.effectiveAt, effectiveUntil: observation.effectiveUntil, expiresAt: expiry,
                     sensitivity: max(.personal, decision.sensitivity), fingerprint: fingerprint, objectState: observation.state,
                     supersedes: nil, isSuperseded: false, normalizationVersion: 1, isAllDay: observation.isAllDay)
    }
}
