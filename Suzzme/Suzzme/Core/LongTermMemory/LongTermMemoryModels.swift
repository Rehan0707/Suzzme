import Foundation
import SwiftData

enum SuzzmeMemoryType: String, Codable, Sendable, CaseIterable { case person, project, commitment, preference, event, place, task, organization, topic }
enum SuzzmeMemoryImportance: String, Codable, Sendable { case normal, important, pinned }
enum SuzzmeMemoryProvenance: String, Codable, Sendable { case userExplicit, conversation, calendar, reminders, contacts }
enum SuzzmeMemoryRetention: String, Codable, Sendable { case durable, timeBound, userPinned }
enum SuzzmeMemoryRelation: String, Codable, Sendable { case involvedIn, attending, relatedTo, associatedWith, appliesTo }
enum SuzzmeMemorySemanticSlot: String, Codable, Sendable { case mainProject, meetingTimePreference }

enum LongTermMemoryMutation: Sendable {
    case remember(type: SuzzmeMemoryType, name: String, detail: String)
    case mainProject(String)
    case preference(name: String, slot: SuzzmeMemorySemanticSlot?)
    case temporalStay(place: String, referenceDate: Date, timeZoneIdentifier: String)
    case relationship(person: String, project: String)
    case forgetRelationship(person: String, project: String)
    case bulkForgetProject(UUID)
}

enum LongTermMemoryCommitResult: Sendable {
    case memory(SuzzmeMemoryRecord)
    case relationship(SuzzmeMemoryRecord, SuzzmeMemoryRecord)
    case relationshipForgotten(Bool)
    case bulkForgotten(Int)
}

@Model
final class StoredSuzzmeMemory {
    @Attribute(.unique) var id: UUID
    var typeRaw: String
    var name: String
    @Attribute(.unique) var normalizedName: String
    var detail: String
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date
    var confidence: Double
    var importanceRaw: String
    var provenanceRaw: String
    var retentionRaw: String
    var expiresAt: Date?
    var semanticSlotRaw: String?
    var isSuperseded: Bool
    init(type: SuzzmeMemoryType, name: String, detail: String, confidence: Double, importance: SuzzmeMemoryImportance, provenance: SuzzmeMemoryProvenance, retention: SuzzmeMemoryRetention = .durable, expiresAt: Date? = nil, semanticSlot: SuzzmeMemorySemanticSlot? = nil) {
        id = UUID(); typeRaw = type.rawValue; self.name = name; normalizedName = Self.normalize(name); self.detail = detail
        createdAt = .now; updatedAt = .now; lastUsedAt = .now; self.confidence = confidence; importanceRaw = importance.rawValue; provenanceRaw = provenance.rawValue; retentionRaw = retention.rawValue; self.expiresAt = expiresAt; semanticSlotRaw = semanticSlot?.rawValue; isSuperseded = false
    }
    var type: SuzzmeMemoryType { .init(rawValue: typeRaw) ?? .topic }
    var provenance: SuzzmeMemoryProvenance { .init(rawValue: provenanceRaw) ?? .conversation }
    var semanticSlot: SuzzmeMemorySemanticSlot? { semanticSlotRaw.flatMap(SuzzmeMemorySemanticSlot.init(rawValue:)) }
    func isActive(at date: Date = .now) -> Bool { !isSuperseded && (expiresAt.map { $0 > date } ?? true) }
    static func normalize(_ value: String) -> String { value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ") }
}

@Model
final class StoredSuzzmeMemoryRelationship {
    @Attribute(.unique) var id: UUID
    var sourceID: UUID
    var targetID: UUID
    var typeRaw: String
    var confidence: Double
    var provenanceRaw: String
    var createdAt: Date
    var updatedAt: Date
    init(sourceID: UUID, targetID: UUID, type: SuzzmeMemoryRelation, confidence: Double, provenance: SuzzmeMemoryProvenance) {
        id = UUID(); self.sourceID = sourceID; self.targetID = targetID; typeRaw = type.rawValue; self.confidence = confidence; provenanceRaw = provenance.rawValue; createdAt = .now; updatedAt = .now
    }
}
