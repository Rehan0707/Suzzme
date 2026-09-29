import Foundation

struct ProactiveDeliveryRecord: Codable, Sendable, Equatable {
    let key: String
    let deliveredAt: Date
}

private struct ProactiveStoredState: Codable, Sendable {
    var schemaVersion = 1
    var preferences = ProactivePreferences()
    var briefings: [ProactiveBriefing] = []
    var opportunities: [SuzzmeOpportunity] = []
    var deliveries: [ProactiveDeliveryRecord] = []
    var dailyContext: DailyContextSnapshot?
}

actor ProactiveIntelligenceStore {
    private let fileURL: URL
    private let write: @Sendable (Data, URL) throws -> Void
    private var state = ProactiveStoredState()
    private var loaded = false
    private var generationID: UUID?

    init(fileURL: URL, write: @escaping @Sendable (Data, URL) throws -> Void = { try RecoverableJSONFile.write($0, to: $1) }) {
        self.fileURL = fileURL
        self.write = write
    }

    static func defaultURL() -> URL {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        return base.appendingPathComponent("Suzzme", isDirectory: true)
            .appendingPathComponent("proactive-intelligence-v1.json")
    }

    func preferences() throws -> ProactivePreferences {
        try loadIfNeeded()
        return state.preferences.validated()
    }

    func updatePreferences(_ value: ProactivePreferences) throws {
        try loadIfNeeded()
        state.preferences = value.validated()
        generationID = nil
        try persist()
    }

    func applySettings(_ plan: SuzzmeSettingsPlan, authorization: SuzzmeSettingsAuthorization) throws {
        try loadIfNeeded()
        try authorization.commit(plan) {
            switch (plan.capability, plan.value) {
            case let (.dailySummary, .enabled(value)): state.preferences.dailyBriefingEnabled = value
            case let (.dailySummary, .summaryTime(hour, minute, identifier)):
                state.preferences.briefingHour = hour; state.preferences.briefingMinute = minute
                state.preferences.timeZoneIdentifier = identifier
            case let (.timeCriticalIntelligence, .enabled(value)): state.preferences.timeCriticalEnabled = value
            case let (.preparedAssistance, .enabled(value)): state.preferences.preparedAssistanceEnabled = value
            default: throw SuzzmeSettingsCapabilityError.malformed
            }
            generationID = nil
            try persist()
        }
    }

    func beginGeneration() throws -> (UUID, ProactivePreferences) {
        try loadIfNeeded()
        let id = UUID()
        generationID = id
        return (id, state.preferences.validated())
    }

    func commit(_ snapshot: ProactiveSnapshot, generation: UUID, now: Date) throws {
        try loadIfNeeded()
        guard generationID == generation else { throw ProactiveError.staleGeneration }
        generationID = nil
        if let briefing = snapshot.briefing {
            state.briefings.insert(briefing, at: 0)
            state.briefings = Array(state.briefings.prefix(ProactiveLimits.storedBriefings))
        } else {
            // A completed generation with no supported content invalidates the
            // previous current briefing instead of presenting it as fresh.
            state.briefings.removeAll()
        }
        let dismissed = Dictionary(state.opportunities.filter { $0.state == .dismissed }.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        state.opportunities = snapshot.opportunities.map { value in
            var copy = value
            if dismissed[value.key] != nil { copy.state = .dismissed }
            return copy
        }
        state.opportunities = Array(state.opportunities.filter { $0.expiresAt > now }.prefix(ProactiveLimits.storedOpportunities))
        state.dailyContext = snapshot.dailyContext
        try cleanup(now: now, persistChanges: false)
        try persist()
    }

    func cancelGeneration() {
        generationID = nil
    }

    func current(now: Date) throws -> ProactiveSnapshot {
        try loadIfNeeded()
        try cleanup(now: now, persistChanges: true)
        let priorContextDay = state.dailyContext?.localDay
        let dailyContext = rolledDailyContext(now: now)
        if priorContextDay != state.dailyContext?.localDay { try persist() }
        var briefing = state.briefings.first
        if var value = briefing, now.timeIntervalSince(value.createdAt) > ProactiveLimits.briefingFreshness {
            value.deliveryState = .stale
            briefing = value
        }
        return .init(
            generatedAt: briefing?.createdAt ?? now,
            briefing: briefing,
            opportunities: state.opportunities.filter { $0.state == .active },
            timeCriticalItems: briefing?.items.filter { $0.delivery == .timeCritical } ?? [],
            dailyContext: dailyContext
        )
    }

    func canDeliver(key: String, now: Date) throws -> Bool {
        try loadIfNeeded()
        guard let prior = state.deliveries.first(where: { $0.key == key }) else { return true }
        return now.timeIntervalSince(prior.deliveredAt) >= ProactiveLimits.deliveryCooldown
    }

    func markDelivered(key: String, at date: Date) throws {
        try loadIfNeeded()
        state.deliveries.removeAll { $0.key == key }
        state.deliveries.insert(.init(key: key, deliveredAt: date), at: 0)
        state.deliveries = Array(state.deliveries.prefix(ProactiveLimits.deliveryRecords))
        try persist()
    }

    func markBriefingDelivered(id: UUID, partial: Bool) throws {
        try loadIfNeeded()
        guard let index = state.briefings.firstIndex(where: { $0.id == id }) else { return }
        state.briefings[index].deliveryState = partial ? .partiallyDelivered : .delivered
        try persist()
    }

    func dismissOpportunity(id: UUID) throws {
        try loadIfNeeded()
        guard let index = state.opportunities.firstIndex(where: { $0.id == id }) else { return }
        state.opportunities[index].state = .dismissed
        try persist()
    }

    func clearProactiveContent() throws {
        try loadIfNeeded()
        generationID = nil
        state.briefings.removeAll()
        state.opportunities.removeAll()
        state.deliveries.removeAll()
        state.dailyContext = nil
        try persist()
    }

    /// User-confirmed recovery of this store only, including its preferences.
    func reset() throws {
        generationID = nil
        let empty = ProactiveStoredState()
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try write(JSONEncoder().encode(empty), fileURL)
            state = empty; loaded = true
        } catch {
            state = ProactiveStoredState(); loaded = false
            throw ProactiveError.persistence
        }
    }

    private func rolledDailyContext(now: Date) -> DailyContextSnapshot? {
        guard let current = state.dailyContext else { return nil }
        var calendar = Calendar.current
        if let identifier = current.timeZoneIdentifier, let timeZone = TimeZone(identifier: identifier) { calendar.timeZone = timeZone }
        let today = calendar.startOfDay(for: now)
        guard !calendar.isDate(current.localDay, inSameDayAs: today) else { return current }
        let carried = current.entries.filter { entry in
            guard entry.state == .active || entry.state == .corrected else { return false }
            return (entry.effectiveUntil ?? entry.effectiveAt ?? .distantPast) >= today
        }
        let rolled = DailyContextSnapshot(
            localDay: today,
            generatedAt: now,
            entries: Array(carried.prefix(ProactiveLimits.dailyContextItems)),
            sourceLimitations: current.sourceLimitations,
            timeZoneIdentifier: current.timeZoneIdentifier
        )
        state.dailyContext = rolled
        return rolled
    }

    func deliveryCount() throws -> Int {
        try loadIfNeeded()
        return state.deliveries.count
    }

    func retainedCounts() throws -> (briefings: Int, opportunities: Int) {
        try loadIfNeeded()
        return (state.briefings.count, state.opportunities.count)
    }

    private func cleanup(now: Date, persistChanges: Bool) throws {
        let oldBriefingCount = state.briefings.count
        state.briefings.removeAll { now.timeIntervalSince($0.createdAt) > ProactiveLimits.opportunityRetention }
        let oldOpportunityCount = state.opportunities.count
        let oldDeliveryCount = state.deliveries.count
        state.opportunities = state.opportunities.compactMap { value in
            var copy = value
            if copy.expiresAt <= now { copy.state = .expired }
            return copy.state == .expired || copy.createdAt < now.addingTimeInterval(-ProactiveLimits.opportunityRetention) ? nil : copy
        }
        state.deliveries.removeAll { $0.deliveredAt < now.addingTimeInterval(-ProactiveLimits.opportunityRetention) }
        if persistChanges && (oldBriefingCount != state.briefings.count || oldOpportunityCount != state.opportunities.count || oldDeliveryCount != state.deliveries.count) {
            try persist()
        }
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        loaded = true
        do {
            guard let data = try RecoverableJSONFile.read(from: fileURL, validate: { _ = try Self.decode($0) }) else { return }
            let decoded = try Self.decode(data)
            state = decoded
            state.preferences = state.preferences.validated()
        } catch {
            loaded = false
            throw ProactiveError.persistence
        }
    }

    private static func decode(_ data: Data) throws -> ProactiveStoredState {
            guard PrivacyEngine().classify(String(decoding: data, as: UTF8.self)).policy != .neverProcess else { throw ProactiveError.persistence }
            let decoded = try JSONDecoder().decode(ProactiveStoredState.self, from: data)
            guard decoded.schemaVersion == 1,
                  decoded.briefings.count <= ProactiveLimits.storedBriefings,
                  decoded.briefings.flatMap(\.items).allSatisfy({ $0.sensitivity != .restricted }),
                  decoded.dailyContext?.entries.allSatisfy({ $0.sensitivity != .restricted }) ?? true,
                  decoded.opportunities.count <= ProactiveLimits.storedOpportunities,
                  decoded.deliveries.count <= ProactiveLimits.deliveryRecords,
                  Set(decoded.opportunities.map(\.key)).count == decoded.opportunities.count,
                  Set(decoded.briefings.map(\.id)).count == decoded.briefings.count,
                  Set(decoded.deliveries.map(\.key)).count == decoded.deliveries.count,
                  (decoded.dailyContext?.entries.count ?? 0) <= ProactiveLimits.dailyContextItems,
                  TimeZone(identifier: decoded.preferences.timeZoneIdentifier) != nil else { throw ProactiveError.persistence }
            return decoded
    }

    private func persist() throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(state)
            guard PrivacyEngine().classify(String(decoding: data, as: UTF8.self)).policy != .neverProcess,
                  state.briefings.flatMap(\.items).allSatisfy({ $0.sensitivity != .restricted }),
                  state.dailyContext?.entries.allSatisfy({ $0.sensitivity != .restricted }) ?? true else { throw ProactiveError.persistence }
            try write(data, fileURL)
        } catch {
            // A failed disk commit must never be observable as verified state.
            state = ProactiveStoredState(); loaded = false; generationID = nil
            throw ProactiveError.persistence
        }
    }
}
