import Foundation
#if canImport(SuzzmeWatchedTransport)
import SuzzmeWatchedTransport
#endif

struct WatchedPinnedRequest: Sendable {
    let url: URL
    let address: WebApprovedAddress
    let etag: String?
    let lastModified: String?
    let timeout: TimeInterval
}

struct WatchedHTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: [String]]
    let data: Data

    func header(_ name: String) throws -> String? {
        let values = headers[name.lowercased()] ?? []
        guard values.count <= 1 else { throw WatchedLinkError.malformedContent }
        return values.first
    }
}

/// This seam tests orchestration; a fake implementation is never socket proof.
protocol WatchedHTTPTransport: Sendable {
    var isAvailable: Bool { get }
    func get(_ request: WatchedPinnedRequest) async throws -> WatchedHTTPResponse
}

private struct PinnedWatchedHTTPTransport: WatchedHTTPTransport {
    #if canImport(SuzzmeWatchedTransport)
    private let client = PinnedHTTPClient()
    #endif
    // Socket/TLS evidence alone cannot clear the unresolved DNS completeness gate.
    #if SUZZME_PINNED_WATCHED_TRANSPORT && canImport(SuzzmeWatchedTransport)
    var isAvailable: Bool { true }
    #else
    var isAvailable: Bool { false }
    #endif

    func get(_ request: WatchedPinnedRequest) async throws -> WatchedHTTPResponse {
        guard isAvailable else { throw WatchedLinkError.transportRestricted }
        // Type-check the real adapter in ordinary app builds while its runtime
        // availability remains off until the complete security contract is met.
        #if canImport(SuzzmeWatchedTransport)
        guard let host = request.url.host,
              let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false) else { throw WatchedLinkError.invalidURL }
        var target = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        if let query = components.percentEncodedQuery { target += "?" + query }
        do {
            let value = try await client.get(.init(hostname: host, numericIPAddress: request.address.numericHost,
                pathAndQuery: target, etag: request.etag, lastModified: request.lastModified, timeout: request.timeout))
            return .init(statusCode: value.statusCode, headers: value.headers, data: value.data)
        } catch is CancellationError { throw CancellationError() }
        catch let error as PinnedHTTPError {
            switch error {
            case .timeout: throw WatchedLinkError.timeout
            case .headerTooLarge, .bodyTooLarge: throw WatchedLinkError.responseTooLarge
            case .prohibitedAddress, .peerMismatch: throw WatchedLinkError.blockedHost
            case .invalidRequest: throw WatchedLinkError.invalidURL
            case .unsupportedResponse: throw WatchedLinkError.unsupportedContent
            case .malformedResponse: throw WatchedLinkError.malformedContent
            case .connectionFailed, .tlsVerificationFailed: throw WatchedLinkError.unavailable
            }
        } catch { throw WatchedLinkError.unavailable }
        #else
        throw WatchedLinkError.transportRestricted
        #endif
    }
}

/// DNS results are consumed as immutable numeric socket destinations. Each
/// redirect gets a new policy check, DNS answer and independently pinned socket.
struct BoundedWatchedLinkFetcher: WatchedLinkFetching {
    private let resolver: any WebHostResolving
    private let transport: any WatchedHTTPTransport
    private let totalTimeout: TimeInterval
    var isAvailable: Bool { transport.isAvailable }

    init(resolver: any WebHostResolving = SystemWebHostResolver()) {
        self.resolver = resolver; self.transport = PinnedWatchedHTTPTransport()
        self.totalTimeout = WatchedLinkLimits.timeout
    }

    init(resolver: any WebHostResolving, transport: any WatchedHTTPTransport,
         totalTimeout: TimeInterval = WatchedLinkLimits.timeout) {
        self.resolver = resolver; self.transport = transport
        // The injected-only seam can shorten the production bound for fixtures.
        self.totalTimeout = totalTimeout.isFinite && totalTimeout > 0
            ? min(totalTimeout, WatchedLinkLimits.timeout) : WatchedLinkLimits.timeout
    }

    func fetch(_ request: WatchedLinkFetchRequest) async throws -> WatchedLinkFetchResponse {
        try Task.checkCancellation()
        var current = try WebURLPolicy.validate(request.url)
        guard current == request.url else { throw WatchedLinkError.invalidURL }
        guard transport.isAvailable else { throw WatchedLinkError.transportRestricted }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(totalTimeout))
        var visited = Set<URL>()
        var etag = try safeConditional(request.etag), modified = try safeConditional(request.lastModified)
        for hop in 0...WatchedLinkLimits.redirects {
            try Task.checkCancellation()
            guard clock.now < deadline else { throw WatchedLinkError.timeout }
            guard visited.insert(current).inserted else { throw WatchedLinkError.redirectLimit }
            let dnsBudget = clock.now.duration(to: deadline)
            let dnsSeconds = Double(dnsBudget.components.seconds) + Double(dnsBudget.components.attoseconds) / 1e18
            guard dnsSeconds > 0 else { throw WatchedLinkError.timeout }
            let addresses = try await WebURLPolicy.approvedAddresses(for: current, resolver: resolver,
                timeout: min(WatchedLinkLimits.dnsTimeout, dnsSeconds))
            guard let selected = addresses.first(where: { $0.family == .ipv4 }) ?? addresses.first else { throw WatchedLinkError.blockedHost }
            try Task.checkCancellation()
            let remaining = clock.now.duration(to: deadline)
            let seconds = Double(remaining.components.seconds) + Double(remaining.components.attoseconds) / 1e18
            guard seconds > 0 else { throw WatchedLinkError.timeout }
            let response = try await transport.get(.init(url: current, address: selected, etag: etag, lastModified: modified, timeout: seconds))
            try Task.checkCancellation()
            guard clock.now < deadline else { throw WatchedLinkError.timeout }
            guard response.data.count <= WatchedLinkLimits.responseBytes else { throw WatchedLinkError.responseTooLarge }
            if [301, 302, 303, 307, 308].contains(response.statusCode) {
                guard hop < WatchedLinkLimits.redirects else { throw WatchedLinkError.redirectLimit }
                guard let location = try response.header("location"), !location.isEmpty,
                      location.utf8.count <= 2048, !location.contains("\\"),
                      !location.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                      let destination = URL(string: location, relativeTo: current)?.absoluteURL else { throw WatchedLinkError.invalidURL }
                current = try WebURLPolicy.validate(destination)
                // Validators identify an exact resource. They never cross a
                // redirect, even one that stays on the same origin.
                etag = nil; modified = nil
                continue
            }
            if response.statusCode == 404 { throw WatchedLinkError.notFound }
            if response.statusCode >= 500 { throw WatchedLinkError.serverError }
            guard response.statusCode == 200 || response.statusCode == 304 else { throw WatchedLinkError.unavailable }
            if response.statusCode == 304 {
                guard etag != nil || modified != nil, response.data.isEmpty else { throw WatchedLinkError.malformedContent }
            } else {
                guard let mime = try response.header("content-type")?.split(separator: ";", maxSplits: 1).first?
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    ["text/html", "text/plain", "application/xhtml+xml"].contains(mime) else { throw WatchedLinkError.unsupportedContent }
            }
            return .init(finalURL: current, statusCode: response.statusCode, mimeType: try response.header("content-type"),
                data: response.data, etag: try safeConditional(response.header("etag")), lastModified: try safeConditional(response.header("last-modified")))
        }
        throw WatchedLinkError.redirectLimit
    }

    private func safeConditional(_ value: String?) throws -> String? {
        guard let value else { return nil }
        guard value.utf8.count <= 512,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              PrivacyEngine().classify(value).policy != .neverProcess else { throw WatchedLinkError.invalidURL }
        return value
    }
}

actor WatchedWebInformationSource: InformationSource {
    nonisolated let id: InformationSourceID = .watchedWeb
    private let store: WatchedLinkStore
    private let fetcher: any WatchedLinkFetching

    init(store: WatchedLinkStore, fetcher: any WatchedLinkFetching = BoundedWatchedLinkFetcher()) {
        self.store = store; self.fetcher = fetcher
    }

    func permits(_ event: InformationEvent, now: Date) async -> Bool {
        guard fetcher.isAvailable, let records = try? await store.records() else { return false }
        return records.contains { record in
            record.permitsFetching && [.changed, .unchanged].contains(record.state)
                && record.lastSuccess.map { now.timeIntervalSince($0) <= InformationLimits.freshness } == true
                && record.changes.contains { event.externalID == "\(record.sourceIdentity)#\($0.id)" }
        }
    }

    func authorization() async -> InformationHealthState {
        guard fetcher.isAvailable else { return .unsupported }
        guard let values = try? await store.records(), values.contains(where: \.permitsFetching) else { return .disabled }
        return .healthy
    }

    func fetch(now: Date, checkpoint: Date?) async throws -> InformationBatch {
        guard fetcher.isAvailable else { throw WatchedLinkError.transportRestricted }
        let records = try await store.records().filter(\.permitsFetching)
        var observations: [InformationObservation] = []
        var attempted = 0, succeeded = 0
        for record in records.prefix(WatchedLinkLimits.links) {
            try Task.checkCancellation()
            guard let refresh = try await store.begin(record.id, now: now, force: false) else { continue }
            attempted += 1
            do {
                let response = try await fetcher.fetch(.init(url: record.canonicalURL, etag: record.etag, lastModified: record.lastModifiedHeader))
                let validatedFinalURL = try WebURLPolicy.validate(response.finalURL)
                guard response.finalURL == validatedFinalURL else { throw WatchedLinkError.blockedHost }
                let extraction = response.statusCode == 304 ? nil : try WebContentExtractor.extract(data: response.data, mimeType: response.mimeType, now: now)
                let changed = try await store.commit(record.id, generation: refresh.generation, response: response, extraction: extraction, now: now)
                succeeded += 1
                guard changed, let extraction else { continue }
                observations += extraction.changes.map { change in
                    InformationObservation(
                        externalID: "\(record.sourceIdentity)#\(change.id)",
                        title: change.title,
                        privateNotes: change.detail,
                        location: change.location ?? "",
                        entities: [record.name],
                        modifiedAt: change.observedAt,
                        effectiveAt: change.effectiveAt,
                        effectiveUntil: change.effectiveUntil,
                        state: change.kind == .cancellation ? .cancelled : .active,
                        kindHint: informationKind(change.kind)
                    )
                }
            } catch is CancellationError {
                try? await store.cancel(record.id, generation: refresh.generation)
                throw CancellationError()
            }
            catch let error as WatchedLinkError {
                try? await store.fail(record.id, generation: refresh.generation, error: error, now: now)
            } catch {
                try? await store.fail(record.id, generation: refresh.generation, error: .unavailable, now: now)
            }
        }
        let finalRecords = try await store.records().filter(\.permitsFetching)
        if finalRecords.contains(where: { [.offline, .error, .blocked, .unavailable, .stale].contains($0.state) }) || attempted > succeeded {
            throw WatchedLinkError.unavailable
        }
        // A prior partial batch may not have reached Step 9. Replay only
        // uncheckpointed semantics; unchanged successful intake stays empty.
        let emitted = Set(observations.map(\.externalID))
        for record in finalRecords where [.changed, .unchanged].contains(record.state)
            && record.lastSuccess.map({ now.timeIntervalSince($0) <= InformationLimits.freshness }) == true
            && (record.lastMeaningfulChange ?? .distantPast) > (checkpoint ?? .distantPast) {
            observations += record.changes.filter { !emitted.contains("\(record.sourceIdentity)#\($0.id)") }.map { change in
                InformationObservation(externalID: "\(record.sourceIdentity)#\(change.id)", title: change.title,
                    privateNotes: change.detail, location: change.location ?? "", entities: [record.name],
                    modifiedAt: change.observedAt, effectiveAt: change.effectiveAt, effectiveUntil: change.effectiveUntil,
                    state: change.kind == .cancellation ? .cancelled : .active, kindHint: informationKind(change.kind))
            }
        }
        let validated = finalRecords.filter { record in
            [.changed, .unchanged].contains(record.state) && record.lastSuccess.map { now.timeIntervalSince($0) <= InformationLimits.freshness } == true
        }.flatMap { record in record.changes.map { "\(record.sourceIdentity)#\($0.id)" } }
        return .init(observations: Array(observations.prefix(InformationLimits.intake)), complete: false,
                     window: DateInterval(start: checkpoint ?? now.addingTimeInterval(-InformationLimits.retention), end: now),
                     validatedExternalIDs: validated)
    }

    private func informationKind(_ kind: WatchedLinkChangeKind) -> InformationKind {
        switch kind {
        case .cancellation: .cancellation
        case .locationChange: .locationChange
        case .correction, .timetable: .scheduleChange
        case .deadline, .general: .generalUpdate
        }
    }
}
