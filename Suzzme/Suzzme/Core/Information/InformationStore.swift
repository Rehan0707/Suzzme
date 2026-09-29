import Foundation
import SwiftData

@Model final class StoredInformationEvent {
    @Attribute(.unique) var id: UUID
    var source: String
    var externalID: String
    var kind: String
    var title: String
    var location: String
    var entities: [String]
    var sourceUpdatedAt: Date
    var observedAt: Date
    var effectiveAt: Date?
    var effectiveUntil: Date?
    var expiresAt: Date
    var sensitivity: String
    var fingerprint: String
    var objectState: String
    var supersedes: UUID?
    var isSuperseded: Bool
    var normalizationVersion: Int
    init(_ value: InformationEvent) {
        id = value.id; source = value.source.rawValue; externalID = value.externalID; kind = value.kind.rawValue
        title = value.title; location = value.location; entities = value.entities; sourceUpdatedAt = value.sourceUpdatedAt
        observedAt = value.observedAt; effectiveAt = value.effectiveAt; effectiveUntil = value.effectiveUntil; expiresAt = value.expiresAt
        sensitivity = value.sensitivity.rawValue; fingerprint = value.fingerprint; objectState = value.objectState.rawValue
        supersedes = value.supersedes; isSuperseded = value.isSuperseded; normalizationVersion = value.normalizationVersion
    }
    var value: InformationEvent? {
        guard let source = InformationSourceID(rawValue: source), let kind = InformationKind(rawValue: kind),
              let sensitivity = SuzzmeContextSensitivity(rawValue: sensitivity), sensitivity != .restricted,
              let state = InformationObjectState(rawValue: objectState), normalizationVersion == 1,
              !externalID.isEmpty, externalID.count <= 512, !title.isEmpty, title.count <= 240, location.count <= 180, entities.count <= 5,
              entities.allSatisfy({ $0.count <= 60 }), sourceUpdatedAt.timeIntervalSince1970.isFinite,
              [effectiveAt, effectiveUntil].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              PrivacyEngine().classify(([title, location, externalID] + entities).joined(separator: " ")).policy != .neverProcess,
              expiresAt.timeIntervalSince1970.isFinite, observedAt.timeIntervalSince1970.isFinite else { return nil }
        return .init(id: id, source: source, externalID: externalID, kind: kind, title: title, location: location, entities: entities,
                     sourceUpdatedAt: sourceUpdatedAt, observedAt: observedAt, effectiveAt: effectiveAt, effectiveUntil: effectiveUntil,
                     expiresAt: expiresAt, sensitivity: sensitivity, fingerprint: fingerprint, objectState: state,
                     supersedes: supersedes, isSuperseded: isSuperseded, normalizationVersion: normalizationVersion)
    }
}
@Model final class StoredInformationSource {
    @Attribute(.unique) var id: String
    var enabled = false
    var health = InformationHealthState.disabled.rawValue
    var lastAttempt: Date?
    var lastSuccess: Date?
    var checkpoint: Date?
    var considered = 0
    var accepted = 0
    var rejected = 0
    var deduplicated = 0
    var consolidated = 0
    var expired = 0
    var limited = false
    init(_ id: InformationSourceID) { self.id = id.rawValue }
}
struct InformationCycle: Sendable, Equatable {
    let id: UUID
    let source: InformationSourceID
    let checkpoint: Date?
}
struct InformationClearReceipt: Sendable {
    let id: UUID
    let count: Int
}

/// Dedicated Step 9 container; no memory models or EventKit executor are available here.
@ModelActor actor InformationStore {
    private var cycles: [InformationSourceID: UUID] = [:]
    private var clearReceipt: (InformationClearReceipt, Set<UUID>)?

    private func source(_ id: InformationSourceID) throws -> StoredInformationSource {
        let key = id.rawValue
        var query = FetchDescriptor<StoredInformationSource>(predicate: #Predicate { $0.id == key })
        query.fetchLimit = 1
        if let existing = try modelContext.fetch(query).first { return existing }
        let created = StoredInformationSource(id); modelContext.insert(created); return created
    }
    private func records() throws -> [StoredInformationEvent] {
        try modelContext.fetch(FetchDescriptor<StoredInformationEvent>())
    }
    func setEnabled(_ id: InformationSourceID, enabled: Bool) throws {
        cycles.removeValue(forKey: id)
        let state = try source(id); state.enabled = enabled
        state.health = (enabled ? InformationHealthState.stale : .disabled).rawValue
        do { try modelContext.save() } catch { modelContext.rollback(); throw error }
    }
    func begin(_ id: InformationSourceID, now: Date) throws -> InformationCycle {
        let state = try source(id)
        guard state.enabled else { throw InformationError.disabled }
        if let checkpoint = state.checkpoint, !checkpoint.timeIntervalSince1970.isFinite || checkpoint > now || checkpoint < now.addingTimeInterval(-InformationLimits.retention) { state.checkpoint = nil }
        let token = InformationCycle(id: UUID(), source: id, checkpoint: state.checkpoint)
        cycles[id] = token.id; state.lastAttempt = now; state.health = InformationHealthState.stale.rawValue
        try modelContext.save()
        return token
    }
    func invalidate() { cycles.removeAll() }
    func fail(_ cycle: InformationCycle, state health: InformationHealthState) throws {
        guard cycles[cycle.source] == cycle.id else { return }
        cycles.removeValue(forKey: cycle.source)
        let state = try source(cycle.source)
        guard state.enabled else { return }
        state.health = health.rawValue
        try modelContext.save()
    }
    func commit(_ batch: InformationBatch, cycle: InformationCycle, now: Date) throws {
        try Task.checkCancellation()
        let state = try source(cycle.source)
        guard state.enabled, cycles[cycle.source] == cycle.id else { throw InformationError.staleCycle }
        guard batch.window.start.timeIntervalSince1970.isFinite, batch.window.end.timeIntervalSince1970.isFinite,
              batch.window.duration <= 32 * 86400 else { throw InformationError.malformed }
        let candidates = Array(batch.observations.prefix(InformationLimits.intake))
        let complete = batch.complete && batch.observations.count <= InformationLimits.intake
        state.considered = candidates.count; state.accepted = 0; state.rejected = 0; state.deduplicated = 0; state.consolidated = 0
        state.limited = !complete
        var existing = try records()
        var seen: Set<String> = []
        var persisted = 0
        do {
            for raw in candidates {
                guard seen.insert(raw.externalID).inserted else { state.limited = true; continue }
                guard let normalized = InformationNormalizer.normalize(raw, source: cycle.source, now: now) else {
                    state.rejected += 1
                    // A newly restricted object must not leave an old interpretation current.
                    for row in existing where row.source == cycle.source.rawValue && row.externalID == raw.externalID { modelContext.delete(row) }
                    existing.removeAll { $0.source == cycle.source.rawValue && $0.externalID == raw.externalID }
                    continue
                }
                let previous = existing.filter { $0.source == cycle.source.rawValue && $0.externalID == raw.externalID && !$0.isSuperseded }.max { $0.sourceUpdatedAt < $1.sourceUpdatedAt }
                if let previous {
                    guard normalized.sourceUpdatedAt >= previous.sourceUpdatedAt || previous.fingerprint.hasSuffix(":absent") else { state.deduplicated += 1; continue }
                    if previous.fingerprint == normalized.fingerprint {
                        previous.observedAt = now
                        previous.sourceUpdatedAt = max(previous.sourceUpdatedAt, normalized.sourceUpdatedAt)
                        // Refresh must not extend retention indefinitely for past objects.
                        state.deduplicated += 1; continue
                    }
                }
                let row = StoredInformationEvent(normalized)
                if let previous {
                    previous.isSuperseded = true; row.supersedes = previous.id; state.consolidated += 1
                    if raw.state == .cancelled { row.kind = InformationKind.cancellation.rawValue }
                    else if previous.effectiveAt != row.effectiveAt || previous.effectiveUntil != row.effectiveUntil { row.kind = InformationKind.scheduleChange.rawValue }
                    else if previous.location != row.location { row.kind = InformationKind.locationChange.rawValue }
                }
                modelContext.insert(row); existing.append(row); state.accepted += 1; persisted += 1
            }
            // Only a complete successful snapshot within the same scope proves absence.
            if complete {
                for previous in existing where previous.source == cycle.source.rawValue && !previous.isSuperseded && previous.objectState != InformationObjectState.cancelled.rawValue && previous.objectState != InformationObjectState.absent.rawValue && !seen.contains(previous.externalID) {
                    guard let date = previous.effectiveAt, batch.window.contains(date) else { continue }
                    guard let old = previous.value else { continue }
                    previous.isSuperseded = true
                    guard persisted < InformationLimits.persistedPerCycle else { state.limited = true; continue }
                    let cancellation = InformationEvent(id: UUID(), source: old.source, externalID: old.externalID, kind: .generalUpdate, title: old.title, location: "", entities: [], sourceUpdatedAt: now, observedAt: now, effectiveAt: old.effectiveAt, effectiveUntil: old.effectiveUntil, expiresAt: now.addingTimeInterval(86400), sensitivity: old.sensitivity, fingerprint: old.fingerprint + ":absent", objectState: .absent, supersedes: old.id, isSuperseded: false, normalizationVersion: 1)
                    modelContext.insert(StoredInformationEvent(cancellation)); state.consolidated += 1; persisted += 1
                }
            }
            let validated = Set(batch.validatedExternalIDs.prefix(InformationLimits.records))
            for row in existing where row.source == cycle.source.rawValue && validated.contains(row.externalID) && !row.isSuperseded {
                row.observedAt = now
            }
            try prune(now: now)
            state.health = InformationHealthState.healthy.rawValue; state.lastSuccess = now; state.checkpoint = now
            try modelContext.save()
            cycles.removeValue(forKey: cycle.source); clearReceipt = nil
        } catch { modelContext.rollback(); throw error }
    }
    private func prune(now: Date) throws {
        let all = try records()
        var retained: [StoredInformationEvent] = []
        var versions: [String: Int] = [:]
        for row in all.sorted(by: {
            if $0.isSuperseded != $1.isSuperseded { return !$0.isSuperseded }
            if $0.observedAt != $1.observedAt { return $0.observedAt > $1.observedAt }
            return $0.sourceUpdatedAt > $1.sourceUpdatedAt
        }) {
            let key = row.source + ":" + row.externalID
            guard row.value != nil, row.expiresAt > now, now.timeIntervalSince(row.observedAt) <= InformationLimits.retention,
                  versions[key, default: 0] < InformationLimits.versions, retained.count < InformationLimits.records else {
                if let id = InformationSourceID(rawValue: row.source), row.expiresAt <= now { try source(id).expired += 1 }
                modelContext.delete(row); continue
            }
            versions[key, default: 0] += 1; retained.append(row)
        }
    }
    func cleanup(now: Date) throws { try prune(now: now); try modelContext.save() }
    func retrieve(_ query: InformationQuery = .init(), now: Date) throws -> [InformationEvent] {
        let allowed = try health(now: now).filter { $0.enabled && $0.state == .healthy }.map(\.source)
        return try records().compactMap(\.value).filter { event in
            guard allowed.contains(event.source), query.sources.contains(event.source), !event.isSuperseded,
                  event.freshness(at: now) != .expired, event.freshness(at: now) != .stale else { return false }
            if !query.includeFuture, event.freshness(at: now) == .future { return false }
            if let since = query.since, event.observedAt < since { return false }
            if let window = query.window, !window.contains(event.effectiveAt ?? event.observedAt) { return false }
            if let entity = query.entity, !event.entities.contains(where: { $0.localizedCaseInsensitiveCompare(entity) == .orderedSame }) { return false }
            return true
        }.sorted { $0.observedAt > $1.observedAt }.prefix(max(0, min(query.limit, InformationLimits.retrieval))).map { $0 }
    }
    func health(now: Date) throws -> [InformationHealth] {
        try InformationSourceID.allCases.map { id in
            let row = try source(id)
            var state = InformationHealthState(rawValue: row.health) ?? .error
            if state == .healthy, row.lastSuccess.map({ now.timeIntervalSince($0) > InformationLimits.freshness }) ?? true { state = .stale }
            return .init(source: id, enabled: row.enabled, state: row.enabled ? state : .disabled, lastAttempt: row.lastAttempt, lastSuccess: row.lastSuccess, checkpoint: row.checkpoint,
                         considered: row.considered, accepted: row.accepted, rejected: row.rejected, deduplicated: row.deduplicated, consolidated: row.consolidated, expired: row.expired, limited: row.limited)
        }
    }
    func removeObjects(source id: InformationSourceID, prefix: String) throws {
        guard !prefix.isEmpty else { throw InformationError.malformed }
        cycles.removeValue(forKey: id)
        do {
            for row in try records() where row.source == id.rawValue && row.externalID.hasPrefix(prefix) { modelContext.delete(row) }
            try modelContext.save(); clearReceipt = nil
        } catch { modelContext.rollback(); throw error }
    }
    /// Explicit source reset. A prefix is deliberately not used to express this scope.
    func removeAllObjects(source id: InformationSourceID) throws {
        cycles.removeValue(forKey: id)
        do {
            for row in try records() where row.source == id.rawValue { modelContext.delete(row) }
            let state = try source(id)
            state.checkpoint = nil; state.lastSuccess = nil
            state.health = (state.enabled ? InformationHealthState.stale : .disabled).rawValue
            try modelContext.save(); clearReceipt = nil
        } catch { modelContext.rollback(); throw error }
    }

    func prepareClear() throws -> InformationClearReceipt {
        let ids = Set(try records().map(\.id)); let receipt = InformationClearReceipt(id: UUID(), count: ids.count)
        clearReceipt = (receipt, ids); return receipt
    }
    func clear(_ receipt: InformationClearReceipt) throws {
        let all = try records()
        guard let prepared = clearReceipt, prepared.0.id == receipt.id, prepared.0.count == receipt.count, prepared.1 == Set(all.map(\.id)) else { throw InformationError.clearConfirmationRequired }
        cycles.removeAll()
        for row in all { modelContext.delete(row) }
        for id in InformationSourceID.allCases { let row = try source(id); row.checkpoint = nil; row.lastSuccess = nil; row.health = (row.enabled ? InformationHealthState.stale : .disabled).rawValue }
        do { try modelContext.save(); clearReceipt = nil } catch { modelContext.rollback(); throw error }
    }
}
