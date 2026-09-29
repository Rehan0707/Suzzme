import Foundation

private struct WatchedLinkStoredState: Codable, Sendable {
    var schemaVersion = 1
    var links: [WatchedLinkRecord] = []
}

actor WatchedLinkStore {
    private let fileURL: URL
    private let write: @Sendable (Data, URL) throws -> Void
    private var state = WatchedLinkStoredState()
    private var loaded = false
    private var committed = WatchedLinkStoredState()
    private var generations: [UUID: UUID] = [:]

    init(fileURL: URL, write: @escaping @Sendable (Data, URL) throws -> Void = { try RecoverableJSONFile.write($0, to: $1) }) {
        self.fileURL = fileURL
        self.write = write
    }

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Suzzme", isDirectory: true).appendingPathComponent("watched-links-v1.json")
    }

    func records(now: Date = .now) throws -> [WatchedLinkRecord] {
        try load()
        var changed = false
        for index in state.links.indices {
            let prior = state.links[index].changes.count
            state.links[index].changes.removeAll { now.timeIntervalSince($0.observedAt) > WatchedLinkLimits.changeRetention }
            if prior != state.links[index].changes.count { changed = true }
        }
        if changed { try persist() }
        return state.links.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    func add(name: String, url: String, enabled: Bool = true) throws -> WatchedLinkRecord {
        try load()
        let canonical = try WebURLPolicy.validate(url)
        if let existing = state.links.first(where: { $0.canonicalURL == canonical }) { return existing }
        guard state.links.count < WatchedLinkLimits.links else { throw WatchedLinkError.limitExceeded }
        guard PrivacyEngine().classify(name).policy != .neverProcess else { throw WatchedLinkError.restrictedContent }
        let cleanName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let record = WatchedLinkRecord(
            id: UUID(), name: cleanName.isEmpty ? (canonical.host ?? "Website") : cleanName,
            canonicalURL: canonical, enabled: enabled, state: enabled ? .ready : .disabled,
            etag: nil, lastModifiedHeader: nil, fingerprint: nil, lastAttempt: nil,
            lastSuccess: nil, lastMeaningfulChange: nil, consecutiveFailures: 0,
            nextEligibleRefresh: nil, pageTitle: nil, changes: []
        )
        state.links.append(record); try persist(); return record
    }

    func setEnabled(_ id: UUID, enabled: Bool) throws {
        try load(); guard let index = state.links.firstIndex(where: { $0.id == id }) else { return }
        generations.removeValue(forKey: id)
        state.links[index].enabled = enabled
        state.links[index].state = enabled ? .ready : .disabled
        if enabled { state.links[index].nextEligibleRefresh = nil }
        try persist()
    }

    func remove(_ id: UUID) throws {
        try load(); generations.removeValue(forKey: id); state.links.removeAll { $0.id == id }; try persist()
    }

    func requestRefresh(_ id: UUID) throws {
        try load(); guard let index = state.links.firstIndex(where: { $0.id == id }), state.links[index].enabled else { throw WatchedLinkError.disabled }
        generations.removeValue(forKey: id)
        state.links[index].nextEligibleRefresh = nil
        try persist()
    }

    func begin(_ id: UUID, now: Date, force: Bool) throws -> WatchedLinkRefresh? {
        try load(); guard let index = state.links.firstIndex(where: { $0.id == id }) else { return nil }
        guard state.links[index].enabled else { throw WatchedLinkError.disabled }
        if generations[id] != nil && !force { return nil }
        if !force, let next = state.links[index].nextEligibleRefresh, next > now { return nil }
        let generation = UUID(); generations[id] = generation
        state.links[index].lastAttempt = now; state.links[index].state = .refreshing
        try persist(); return .init(generation: generation, record: state.links[index])
    }

    func commit(_ id: UUID, generation: UUID, response: WatchedLinkFetchResponse, extraction: WebPageExtraction?, now: Date) throws -> Bool {
        try load(); guard generations[id] == generation, let index = state.links.firstIndex(where: { $0.id == id }), state.links[index].enabled else { throw WatchedLinkError.staleRefresh }
        try Task.checkCancellation()
        if let extraction {
            let content = ([extraction.title] + extraction.changes.flatMap { [$0.title, $0.detail, $0.location ?? ""] }).joined(separator: " ")
            guard PrivacyEngine().classify(content).policy != .neverProcess else { throw WatchedLinkError.restrictedContent }
        }
        generations.removeValue(forKey: id)
        var record = state.links[index]
        record.lastSuccess = now; record.consecutiveFailures = 0
        record.nextEligibleRefresh = now.addingTimeInterval(WatchedLinkLimits.minimumRefreshInterval)
        record.etag = safeHeader(response.etag) ?? record.etag
        record.lastModifiedHeader = safeHeader(response.lastModified) ?? record.lastModifiedHeader
        guard let extraction else { record.state = .unchanged; state.links[index] = record; try persist(); return false }
        let changed = record.fingerprint != extraction.fingerprint
        record.fingerprint = extraction.fingerprint; record.pageTitle = extraction.title
        record.changes = Array(extraction.changes.prefix(WatchedLinkLimits.sections))
        record.state = changed ? .changed : .unchanged
        if changed { record.lastMeaningfulChange = now }
        state.links[index] = record; try persist(); return changed
    }

    func fail(_ id: UUID, generation: UUID, error: WatchedLinkError, now: Date) throws {
        try load(); guard generations[id] == generation, let index = state.links.firstIndex(where: { $0.id == id }) else { return }
        generations.removeValue(forKey: id)
        state.links[index].consecutiveFailures = min(state.links[index].consecutiveFailures + 1, 64)
        if error == .restrictedContent {
            state.links[index].changes = []; state.links[index].pageTitle = nil
            state.links[index].fingerprint = nil; state.links[index].etag = nil
            state.links[index].lastModifiedHeader = nil
        }
        let failures = state.links[index].consecutiveFailures
        let delay = min(WatchedLinkLimits.maximumBackoff, WatchedLinkLimits.minimumRefreshInterval * pow(2, Double(min(failures, 6))))
        state.links[index].nextEligibleRefresh = now.addingTimeInterval(delay)
        state.links[index].state = switch error { case .blockedHost, .unsupportedScheme: .blocked; case .timeout, .unavailable: .offline; default: .error }
        try persist()
    }

    func cancel(_ id: UUID, generation: UUID) throws {
        try load()
        guard generations[id] == generation else { return }
        generations.removeValue(forKey: id)
        if let index = state.links.firstIndex(where: { $0.id == id }) {
            state.links[index].state = state.links[index].enabled ? .stale : .disabled
            try persist()
        }
    }

    func cancelAll() {
        // An unopened store has no in-flight work. Never overwrite unread data.
        guard loaded else { return }
        generations.removeAll()
        for index in state.links.indices where state.links[index].state == .refreshing {
            state.links[index].state = .stale
        }
        try? persist()
    }

    /// Explicit destructive recovery; an invalid/unknown file is never reset on load.
    func reset() throws {
        generations.removeAll()
        let empty = WatchedLinkStoredState()
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try write(JSONEncoder().encode(empty), fileURL)
            state = empty; committed = empty; loaded = true
        } catch {
            // Replacement may already be committed even when the recovery copy
            // or caller completion fails. Re-read disk before exposing state.
            state = WatchedLinkStoredState(); committed = state; loaded = false
            throw WatchedLinkError.persistence
        }
    }

    private func safeHeader(_ value: String?) -> String? {
        guard let value, value.utf8.count <= 512, !value.contains("\r"), !value.contains("\n"),
              PrivacyEngine().classify(value).policy != .neverProcess else { return nil }
        return value
    }

    private func load() throws {
        guard !loaded else { return }; loaded = true
        do {
            guard let data = try RecoverableJSONFile.read(from: fileURL, validate: { _ = try Self.decode($0) }) else { return }
            let decoded = try Self.decode(data)
            state = decoded; committed = decoded
            try persist()
        } catch { loaded = false; throw WatchedLinkError.persistence }
    }

    private static func decode(_ data: Data) throws -> WatchedLinkStoredState {
            var decoded = try JSONDecoder().decode(WatchedLinkStoredState.self, from: data)
            guard decoded.schemaVersion == 1, decoded.links.count <= WatchedLinkLimits.links else { throw WatchedLinkError.persistence }
            guard Set(decoded.links.map(\.id)).count == decoded.links.count,
                  Set(decoded.links.map(\.canonicalURL)).count == decoded.links.count else { throw WatchedLinkError.persistence }
            for index in decoded.links.indices {
                let record = decoded.links[index]
                guard (try? WebURLPolicy.validate(record.canonicalURL)) == record.canonicalURL,
                      record.name.count <= 80, record.changes.count <= WatchedLinkLimits.sections,
                      record.consecutiveFailures >= 0, record.consecutiveFailures <= 64,
                      Set(record.changes.map(\.id)).count == record.changes.count,
                      record.changes.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 128 && $0.title.count <= 160 && $0.detail.count <= 480 })
                else { throw WatchedLinkError.persistence }
                let content = ([record.name, record.pageTitle ?? ""] + record.changes.flatMap { [$0.title, $0.detail, $0.location ?? ""] }).joined(separator: " ")
                if PrivacyEngine().classify(content).policy == .neverProcess {
                    decoded.links[index].name = record.canonicalURL.host ?? "Website"
                    decoded.links[index].pageTitle = nil; decoded.links[index].changes = []
                    decoded.links[index].fingerprint = nil; decoded.links[index].etag = nil
                    decoded.links[index].lastModifiedHeader = nil; decoded.links[index].state = .stale
                }
                if record.state == .refreshing { decoded.links[index].state = record.enabled ? .stale : .disabled }
            }
            return decoded
    }

    private func persist() throws {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try write(JSONEncoder().encode(state), fileURL)
            committed = state
        } catch {
            state = committed; loaded = false; generations.removeAll()
            throw WatchedLinkError.persistence
        }
    }
}
