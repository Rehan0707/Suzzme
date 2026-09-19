import Foundation
import SwiftData

/// Test-only implementations can suspend here. The production store has no
/// barrier, but the post-suspension authorization check remains part of the
/// production commit boundary.
protocol LongTermMemoryCommitBarrier: Sendable {
    func wait(requestID: UUID) async
}

struct SuzzmeMemoryRecord: Identifiable, Sendable, Hashable {
    let id: UUID
    let type: SuzzmeMemoryType
    let name: String
    let normalizedName: String
    let detail: String
    let provenance: SuzzmeMemoryProvenance
    let expiresAt: Date?
    let semanticSlot: SuzzmeMemorySemanticSlot?
    let isSuperseded: Bool

    func isActive(at date: Date = .now) -> Bool {
        !isSuperseded && (expiresAt.map { $0 > date } ?? true)
    }
}

@ModelActor
actor LongTermMemoryStore {
    private let maximumActiveMemories = 500
    private var authorizedRequestID: UUID?
    private var commitBarrier: (any LongTermMemoryCommitBarrier)? = nil

    init(modelContainer: ModelContainer, commitBarrier: (any LongTermMemoryCommitBarrier)? = nil) {
        let modelContext = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
        self.modelContainer = modelContainer
        self.commitBarrier = commitBarrier
    }

    func authorize(_ requestID: UUID) {
        authorizedRequestID = requestID
    }

    func revoke(_ requestID: UUID) {
        guard authorizedRequestID == requestID else { return }
        authorizedRequestID = nil
    }

    func isEnabled() -> Bool {
        UserDefaults.standard.object(forKey: "suzzme.personalMemory.enabled") as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "suzzme.personalMemory.enabled")
    }

    /// This is the only durable-mutation entry point used by SuzzmeCore.
    /// Authorization and the synchronous ModelContext mutation share this actor turn.
    func commit(_ mutation: LongTermMemoryMutation, requestID: UUID) async throws -> LongTermMemoryCommitResult {
        // A test barrier proves that a request superseded or cancelled while
        // suspended here cannot pass the final authorization check below.
        if let commitBarrier { await commitBarrier.wait(requestID: requestID) }
        try Task.checkCancellation()
        guard authorizedRequestID == requestID else { throw LongTermMemoryError.unauthorizedCommit }
        guard isEnabled() else { throw LongTermMemoryError.disabled }
        switch mutation {
        case let .remember(type, name, detail):
            return .memory(try remember(type: type, name: name, detail: detail))
        case let .mainProject(name):
            return .memory(try rememberMainProject(name))
        case let .preference(name, slot):
            return .memory(try rememberPreference(name: name, slot: slot))
        case let .temporalStay(place, referenceDate, timeZoneIdentifier):
            return .memory(try rememberTemporalStay(place: place, now: referenceDate, timeZoneIdentifier: timeZoneIdentifier))
        case let .relationship(person, project):
            let records = try rememberRelationship(person: person, project: project)
            return .relationship(records.0, records.1)
        case let .forgetRelationship(person, project):
            return .relationshipForgotten(try forgetRelationship(person: person, project: project))
        case let .bulkForgetProject(id):
            return .bulkForgotten(try forgetProjectScope(id: id))
        }
    }

    func memories(limit: Int = 500, now: Date = .now) throws -> [SuzzmeMemoryRecord] {
        guard isEnabled() else { return [] }
        var descriptor = FetchDescriptor<StoredSuzzmeMemory>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = min(limit, maximumActiveMemories)
        return try modelContext.fetch(descriptor).map(Self.record).filter { $0.isActive(at: now) }
    }

    func allMemories(now: Date = .now) throws -> [SuzzmeMemoryRecord] {
        guard isEnabled() else { return [] }
        return try modelContext.fetch(FetchDescriptor<StoredSuzzmeMemory>()).map(Self.record).filter { $0.isActive(at: now) }
    }

    private func model(type: SuzzmeMemoryType, name: String, now: Date = .now) throws -> StoredSuzzmeMemory? {
        let normalized = StoredSuzzmeMemory.normalize(name)
        return try modelContext.fetch(FetchDescriptor<StoredSuzzmeMemory>()).first {
            $0.type == type && $0.normalizedName == normalized && $0.isActive(at: now)
        }
    }

    private func model(id: UUID) throws -> StoredSuzzmeMemory? {
        try modelContext.fetch(FetchDescriptor<StoredSuzzmeMemory>()).first { $0.id == id }
    }

    private func upsertUnsaved(
        type: SuzzmeMemoryType,
        name: String,
        detail: String,
        semanticSlot: SuzzmeMemorySemanticSlot? = nil,
        retention: SuzzmeMemoryRetention = .userPinned,
        expiresAt: Date? = nil,
        now: Date = .now
    ) throws -> StoredSuzzmeMemory {
        if let existing = try model(type: type, name: name, now: now) {
            existing.detail = detail
            existing.updatedAt = now
            existing.lastUsedAt = now
            if let semanticSlot { existing.semanticSlotRaw = semanticSlot.rawValue }
            return existing
        }
        let memory = StoredSuzzmeMemory(
            type: type,
            name: name,
            detail: detail,
            confidence: 0.95,
            importance: retention == .userPinned ? .pinned : .normal,
            provenance: .userExplicit,
            retention: retention,
            expiresAt: expiresAt,
            semanticSlot: semanticSlot
        )
        modelContext.insert(memory)
        return memory
    }

    func remember(type: SuzzmeMemoryType, name: String, detail: String) throws -> SuzzmeMemoryRecord {
        let memory = try upsertUnsaved(type: type, name: name, detail: detail)
        try modelContext.save()
        return Self.record(memory)
    }

    func rememberPreference(name: String, slot: SuzzmeMemorySemanticSlot?, now: Date = .now) throws -> SuzzmeMemoryRecord {
        if let slot {
            let normalized = StoredSuzzmeMemory.normalize(name)
            let conflicts = try modelContext.fetch(FetchDescriptor<StoredSuzzmeMemory>()).filter {
                $0.type == .preference && $0.semanticSlotRaw == slot.rawValue && $0.normalizedName != normalized && $0.isActive(at: now)
            }
            conflicts.forEach { $0.isSuperseded = true; $0.updatedAt = now }
        }
        let detail = slot == .meetingTimePreference ? "Meeting time preference" : "Your preference"
        let memory = try upsertUnsaved(type: .preference, name: name, detail: detail, semanticSlot: slot, now: now)
        try modelContext.save()
        return Self.record(memory)
    }

    func rememberTemporalStay(
        place: String,
        now: Date = .now,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) throws -> SuzzmeMemoryRecord {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let day = calendar.startOfDay(for: now)
        let nextMonday = calendar.nextDate(after: day, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) ?? calendar.date(byAdding: .day, value: 2, to: day)!
        let memory = try upsertUnsaved(
            type: .place,
            name: place,
            detail: "Staying in \(place) this weekend",
            retention: .timeBound,
            expiresAt: nextMonday,
            now: now
        )
        try modelContext.save()
        return Self.record(memory)
    }

    func resolvePerson(_ value: String, now: Date = .now) throws -> PersonResolution {
        let people = try memories(now: now).filter { $0.type == .person }
        let key = StoredSuzzmeMemory.normalize(value)
        if let exact = people.first(where: { $0.normalizedName == key }) { return .resolved(exact) }
        let matches = people.filter { $0.normalizedName.split(separator: " ").first == Substring(key) }
        return matches.count == 1 ? .resolved(matches[0]) : matches.isEmpty ? .missing : .ambiguous
    }

    func rememberMainProject(_ name: String) throws -> SuzzmeMemoryRecord {
        let prior = try modelContext.fetch(FetchDescriptor<StoredSuzzmeMemory>()).filter {
            $0.type == .project && $0.semanticSlotRaw == SuzzmeMemorySemanticSlot.mainProject.rawValue && $0.isActive()
        }
        prior.forEach(modelContext.delete)
        let memory = try upsertUnsaved(type: .project, name: name, detail: "Your main project", semanticSlot: .mainProject)
        try modelContext.save()
        return Self.record(memory)
    }

    func related(to query: String, now: Date = .now) throws -> [SuzzmeMemoryRecord] {
        let all = try memories(limit: 500, now: now)
        let terms = Set(StoredSuzzmeMemory.normalize(query).split(separator: " ").map(String.init))
        let matched = all.filter { record in
            terms.contains(record.normalizedName) ||
                terms.contains(where: { record.normalizedName.split(separator: " ").contains(Substring($0)) }) ||
                terms.contains(where: { record.detail.lowercased().contains($0) })
        }
        let ids = Set(matched.map(\.id))
        guard !ids.isEmpty else { return [] }
        let edges = try modelContext.fetch(FetchDescriptor<StoredSuzzmeMemoryRelationship>()).filter {
            ids.contains($0.sourceID) || ids.contains($0.targetID)
        }
        let relatedIDs = Set(edges.flatMap { [$0.sourceID, $0.targetID] })
        return all.filter { relatedIDs.contains($0.id) }.prefix(12).map { $0 }
    }

    func rememberRelationship(person: String, project: String) throws -> (SuzzmeMemoryRecord, SuzzmeMemoryRecord) {
        let personModel: StoredSuzzmeMemory
        switch try resolvePerson(person) {
        case let .resolved(record):
            guard let model = try model(id: record.id) else { throw LongTermMemoryError.missingEntity }
            personModel = model
        case .missing:
            personModel = try upsertUnsaved(type: .person, name: person, detail: "Helps you with \(project)")
        case .ambiguous:
            throw LongTermMemoryError.ambiguousPerson
        }
        let projectModel = try upsertUnsaved(type: .project, name: project, detail: "Your project")
        guard personModel.id != projectModel.id else { throw LongTermMemoryError.invalidRelationship }
        let edges = try modelContext.fetch(FetchDescriptor<StoredSuzzmeMemoryRelationship>())
        if !edges.contains(where: { $0.sourceID == personModel.id && $0.targetID == projectModel.id && $0.typeRaw == SuzzmeMemoryRelation.involvedIn.rawValue }) {
            modelContext.insert(StoredSuzzmeMemoryRelationship(sourceID: personModel.id, targetID: projectModel.id, type: .involvedIn, confidence: 0.95, provenance: .userExplicit))
        }
        try modelContext.save()
        return (Self.record(personModel), Self.record(projectModel))
    }

    func forgetRelationship(person: String, project: String) throws -> Bool {
        guard let person = try model(type: .person, name: person), let project = try model(type: .project, name: project) else { return false }
        let edges = try modelContext.fetch(FetchDescriptor<StoredSuzzmeMemoryRelationship>()).filter {
            $0.sourceID == person.id && $0.targetID == project.id && $0.typeRaw == SuzzmeMemoryRelation.involvedIn.rawValue
        }
        guard !edges.isEmpty else { return false }
        edges.forEach(modelContext.delete)
        try modelContext.save()
        return true
    }

    func projectID(named project: String) throws -> UUID? {
        try model(type: .project, name: project)?.id
    }

    func forgetProjectScope(id: UUID) throws -> Int {
        guard let target = try model(id: id), target.type == .project else { return 0 }
        let targetID = target.id
        let edges = try modelContext.fetch(FetchDescriptor<StoredSuzzmeMemoryRelationship>()).filter { $0.sourceID == targetID || $0.targetID == targetID }
        edges.forEach(modelContext.delete)
        modelContext.delete(target)
        try modelContext.save()
        return 1
    }

    func delete(id: UUID) throws {
        guard let memory = try model(id: id) else { return }
        let edges = try modelContext.fetch(FetchDescriptor<StoredSuzzmeMemoryRelationship>())
        edges.filter { $0.sourceID == id || $0.targetID == id }.forEach(modelContext.delete)
        modelContext.delete(memory)
        try modelContext.save()
    }

    func clear() throws {
        try modelContext.delete(model: StoredSuzzmeMemoryRelationship.self)
        try modelContext.delete(model: StoredSuzzmeMemory.self)
        try modelContext.save()
    }

    private static func record(_ memory: StoredSuzzmeMemory) -> SuzzmeMemoryRecord {
        .init(
            id: memory.id,
            type: memory.type,
            name: memory.name,
            normalizedName: memory.normalizedName,
            detail: memory.detail,
            provenance: memory.provenance,
            expiresAt: memory.expiresAt,
            semanticSlot: memory.semanticSlot,
            isSuperseded: memory.isSuperseded
        )
    }
}

enum LongTermMemoryError: LocalizedError, Sendable {
    case invalidRelationship, ambiguousPerson, missingEntity, unauthorizedCommit, disabled

    var errorDescription: String? {
        switch self {
        case .invalidRelationship: "Suzzme can’t create that memory relationship."
        case .ambiguousPerson: "Suzzme needs clarification before linking that person."
        case .missingEntity: "That memory is no longer available."
        case .unauthorizedCommit: "That request is no longer allowed to change Suzzme Memory."
        case .disabled: "Personal memory is turned off."
        }
    }
}

enum PersonResolution: Sendable { case resolved(SuzzmeMemoryRecord), missing, ambiguous }
