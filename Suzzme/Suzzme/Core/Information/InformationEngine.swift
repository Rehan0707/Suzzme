import Foundation

actor InformationEngine {
    private let registry: InformationSourceRegistry
    private let store: InformationStore
    private var running: [InformationSourceID: UUID] = [:]
    init(registry: InformationSourceRegistry, store: InformationStore) { self.registry = registry; self.store = store }

    func setEnabled(_ source: InformationSourceID, enabled: Bool) async throws {
        running.removeValue(forKey: source)
        try await store.setEnabled(source, enabled: enabled)
    }
    func cancel() async { running.removeAll(); await store.invalidate() }
    func refresh(source id: InformationSourceID? = nil, force: Bool = false, supersede: Bool = false, now: Date = .now) async throws {
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
                let batch = try await source.fetch(now: now, checkpoint: cycle.checkpoint)
                try Task.checkCancellation()
                let currentAuthorization = await source.authorization()
                guard currentAuthorization == .healthy else {
                    try await store.fail(cycle, state: .authorizationExpired)
                    if running[state.source] == owner { running.removeValue(forKey: state.source) }
                    continue
                }
                guard running[state.source] == owner else { throw InformationError.staleCycle }
                do { try await store.commit(batch, cycle: cycle, now: now) }
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
        return permitted
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
