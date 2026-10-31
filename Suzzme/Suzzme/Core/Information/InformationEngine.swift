import Foundation
import CryptoKit

actor InformationEngine {
    private let registry: InformationSourceRegistry
    private let store: InformationStore
    private var running: [InformationSourceID: UUID] = [:]
    init(registry: InformationSourceRegistry, store: InformationStore) { self.registry = registry; self.store = store }

    func setEnabled(_ source: InformationSourceID, enabled: Bool) async throws {
        running.removeValue(forKey: source)
        try await store.setEnabled(source, enabled: enabled)
    }

    @discardableResult
    func importSelectedMessage(_ text: String, now: Date = .now) async throws -> SelectedMessageImportResult {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, content.count <= InformationLimits.selectedMessageCharacters else {
            throw InformationError.malformed
        }
        let owner = UUID()
        running[.messages] = owner
        defer {
            if running[.messages] == owner { running.removeValue(forKey: .messages) }
        }
        try await store.setEnabled(.messages, enabled: true)
        let cycle = try await store.begin(.messages, now: now)
        let observation = InformationObservation(
            externalID: "selected-message:" + SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined(),
            title: content,
            modifiedAt: now,
            kindHint: .generalUpdate
        )
        let batch = InformationBatch(
            observations: [observation],
            complete: false,
            window: DateInterval(start: now.addingTimeInterval(-86400), end: now)
        )
        do {
            try await store.commit(batch, cycle: cycle, now: now)
            let health = try await store.health(now: now).first { $0.source == .messages }
            return health?.accepted == 1 || health?.deduplicated == 1 ? .imported : .rejected
        } catch {
            try? await store.fail(cycle, state: .error)
            throw error
        }
    }
    func cancel(respectingTaskCancellation: Bool = false) async {
        guard !respectingTaskCancellation || !Task.isCancelled else { return }
        running.removeAll()
        await store.invalidate(respectingTaskCancellation: respectingTaskCancellation)
    }
    func refresh(source id: InformationSourceID? = nil, force: Bool = false, supersede: Bool = false, now: Date = .now, briefingCutoff: Date? = nil, briefingCalendar: Calendar = .current) async throws {
        let health = try await store.health(now: now)
        for state in health where state.enabled && (id == nil || state.source == id) {
            if running[state.source] != nil, !supersede { continue }
            if !force, let attempted = state.lastAttempt, now.timeIntervalSince(attempted) < InformationLimits.debounce { continue }
            let owner = UUID()
            running[state.source] = owner
            let cycle: InformationCycle
            do { cycle = try await store.begin(state.source, now: now) }
            catch {
                if running[state.source] == owner { running.removeValue(forKey: state.source) }
                if case InformationError.disabled = error { continue }
                throw error
            }
            guard running[state.source] == owner else {
                try await store.fail(cycle, state: .stale)
                continue
            }
            do {
                let source = try registry.source(state.source.rawValue)
                let authorization = await source.authorization()
                guard authorization == .healthy else {
                    try await store.fail(cycle, state: state.lastSuccess != nil && authorization == .permissionDenied ? .authorizationExpired : authorization)
                    if running[state.source] == owner { running.removeValue(forKey: state.source) }
                    continue
                }
                let batch: InformationBatch
                if let cutoff = briefingCutoff {
                    batch = try await source.fetchForBriefing(now: now, checkpoint: cycle.checkpoint, cutoff: cutoff, calendar: briefingCalendar)
                } else {
                    batch = try await source.fetch(now: now, checkpoint: cycle.checkpoint)
                }
                try Task.checkCancellation()
                let currentAuthorization = await source.authorization()
                guard currentAuthorization == .healthy else {
                    try await store.fail(cycle, state: .authorizationExpired)
                    if running[state.source] == owner { running.removeValue(forKey: state.source) }
                    continue
                }
                guard running[state.source] == owner else { throw InformationError.staleCycle }
                do {
                    try await store.commit(batch, cycle: cycle, now: now)
                    await source.didCommit(batch)
                }
                catch InformationError.staleCycle { throw InformationError.staleCycle }
                catch {
                    try await store.fail(cycle, state: .error)
                    if running[state.source] == owner { running.removeValue(forKey: state.source) }
                    throw InformationError.persistence
                }
            } catch is CancellationError {
                try await store.fail(cycle, state: .stale)
            } catch InformationError.staleCycle {
                // The newer cycle/disable operation owns health and checkpoints.
            } catch InformationError.persistence {
                throw InformationError.persistence
            } catch InformationError.unsupported {
                try await store.fail(cycle, state: .unsupported)
            } catch InformationError.authorizationRequired {
                try await store.fail(cycle, state: .permissionRequired)
            } catch InformationError.authorizationExpired {
                try await store.fail(cycle, state: .authorizationExpired)
            } catch InformationError.permissionDenied {
                try await store.fail(cycle, state: .permissionDenied)
            } catch {
                try await store.fail(cycle, state: .temporarilyUnavailable)
            }
            if running[state.source] == owner { running.removeValue(forKey: state.source) }
        }
        try await store.cleanup(now: now)
    }
    func retrieve(_ query: InformationQuery = .init(), now: Date = .now) async throws -> [InformationEvent] {
        // Read permission again; a stored healthy state is not authorization.
        for health in try await store.health(now: now) where health.enabled && query.sources.contains(health.source) {
            let source = try registry.source(health.source.rawValue)
            if await source.authorization() != .healthy {
                let cycle = try await store.begin(health.source, now: now)
                try await store.fail(cycle, state: .authorizationExpired)
            }
        }
        var permitted: [InformationEvent] = []
        for event in try await store.retrieve(query, now: now) {
            let source = try registry.source(event.source.rawValue)
            if await source.permits(event, now: now) { permitted.append(event) }
        }
        // EventKit remains authoritative for exact shared iCalendar identities.
        // Require matching UID, title, interval and all-day status; never merge on title alone.
        let native = permitted.filter { $0.source == .calendar }
        return permitted.filter { event in
            guard event.source == .connectedApps, event.entities.contains("googleCalendar"),
                  let uid = event.entities.first(where: { $0.hasPrefix("ical:") }) else { return true }
            return !native.contains { $0.entities.contains(uid) && $0.title == event.title
                && $0.effectiveAt == event.effectiveAt && $0.effectiveUntil == event.effectiveUntil
                && $0.isAllDay == event.isAllDay }
        }
    }
    /// Revalidate current source access while reading retained historical facts.
    func retrieveHistorical(_ query: InformationQuery, asOf date: Date, now: Date = .now) async throws -> [InformationEvent] {
        var permitted: [InformationEvent] = []
        for event in try await store.retrieve(query, now: date) {
            let source = try registry.source(event.source.rawValue)
            guard await source.authorization() == .healthy,
                  await source.permits(event, now: now) else { continue }
            permitted.append(event)
        }
        return permitted
    }
    func isAuthorized(_ source: InformationSourceID) async -> Bool {
        guard let adapter = try? registry.source(source.rawValue) else { return false }
        return await adapter.authorization() == .healthy
    }
    func removeObjects(source: InformationSourceID, prefix: String) async throws {
        running.removeValue(forKey: source)
        try await store.removeObjects(source: source, prefix: prefix)
    }
    func removeAllObjects(source: InformationSourceID) async throws {
        running.removeValue(forKey: source)
        try await store.removeAllObjects(source: source)
    }
    func health(now: Date = .now) async throws -> [InformationHealth] { try await store.health(now: now) }
    func prepareClear() async throws -> InformationClearReceipt { try await store.prepareClear() }
    func clear(_ receipt: InformationClearReceipt) async throws { try await store.clear(receipt) }
}
