import Foundation

private final class WatchedLinkRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) { completionHandler(nil) }
}

struct BoundedWatchedLinkFetcher: WatchedLinkFetching {
    private let resolver: any WebHostResolving
    init(resolver: any WebHostResolving = SystemWebHostResolver()) { self.resolver = resolver }

    func fetch(_ request: WatchedLinkFetchRequest) async throws -> WatchedLinkFetchResponse {
        var current = try WebURLPolicy.validate(request.url)
        var redirects = 0
        while true {
            try Task.checkCancellation()
            try await WebURLPolicy.validateResolvedAddresses(for: current, resolver: resolver)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = WatchedLinkLimits.timeout
            configuration.timeoutIntervalForResource = WatchedLinkLimits.timeout
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: configuration, delegate: WatchedLinkRedirectDelegate(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            var urlRequest = URLRequest(url: current, timeoutInterval: WatchedLinkLimits.timeout)
            urlRequest.httpMethod = "GET"
            urlRequest.setValue("text/html,text/plain;q=0.9", forHTTPHeaderField: "Accept")
            urlRequest.setValue("bytes=0-\(WatchedLinkLimits.responseBytes)", forHTTPHeaderField: "Range")
            if redirects == 0 {
                if let etag = request.etag { urlRequest.setValue(etag, forHTTPHeaderField: "If-None-Match") }
                if let modified = request.lastModified { urlRequest.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
            }
            do {
                let (bytes, response) = try await session.bytes(for: urlRequest)
                guard let http = response as? HTTPURLResponse else { throw WatchedLinkError.unavailable }
                if 300..<400 ~= http.statusCode, let location = http.value(forHTTPHeaderField: "Location"), let redirected = URL(string: location, relativeTo: current)?.absoluteURL {
                    redirects += 1
                    guard redirects <= WatchedLinkLimits.redirects else { throw WatchedLinkError.redirectLimit }
                    current = try WebURLPolicy.validate(redirected)
                    continue
                }
                if http.statusCode == 304 { return .init(finalURL: current, statusCode: 304, mimeType: http.mimeType, data: Data(), etag: request.etag, lastModified: request.lastModified) }
                if http.statusCode == 404 { throw WatchedLinkError.notFound }
                if http.statusCode >= 500 { throw WatchedLinkError.serverError }
                guard 200..<300 ~= http.statusCode else { throw WatchedLinkError.unavailable }
                if http.expectedContentLength > Int64(WatchedLinkLimits.responseBytes) { throw WatchedLinkError.responseTooLarge }
                var data = Data(); data.reserveCapacity(min(max(0, Int(http.expectedContentLength)), WatchedLinkLimits.responseBytes))
                for try await byte in bytes {
                    guard data.count < WatchedLinkLimits.responseBytes else { throw WatchedLinkError.responseTooLarge }
                    data.append(byte)
                }
                return .init(finalURL: current, statusCode: http.statusCode, mimeType: http.mimeType, data: data, etag: http.value(forHTTPHeaderField: "ETag"), lastModified: http.value(forHTTPHeaderField: "Last-Modified"))
            } catch let error as WatchedLinkError { throw error }
            catch let error as URLError where error.code == .cancelled { throw CancellationError() }
            catch let error as URLError where error.code == .timedOut { throw WatchedLinkError.timeout }
            catch is CancellationError { throw CancellationError() }
            catch { throw WatchedLinkError.unavailable }
        }
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
        guard let records = try? await store.records() else { return false }
        return records.contains { record in
            record.enabled && [.changed, .unchanged].contains(record.state)
                && record.lastSuccess.map { now.timeIntervalSince($0) <= InformationLimits.freshness } == true
                && record.changes.contains { event.externalID == "\(record.sourceIdentity)#\($0.id)" }
        }
    }

    func authorization() async -> InformationHealthState {
        guard let values = try? await store.records(), values.contains(where: { $0.enabled }) else { return .disabled }
        return .healthy
    }

    func fetch(now: Date, checkpoint: Date?) async throws -> InformationBatch {
        let records = try await store.records().filter(\.enabled)
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
        let finalRecords = try await store.records().filter(\.enabled)
        if finalRecords.contains(where: { [.offline, .error, .blocked, .unavailable, .stale].contains($0.state) }) || attempted > succeeded {
            throw WatchedLinkError.unavailable
        }
        // A prior partial batch may not have reached Step 9. Replay only
        // uncheckpointed semantics; unchanged successful intake stays empty.
        let emitted = Set(observations.map(\.externalID))
        for record in finalRecords where (record.lastMeaningfulChange ?? .distantPast) > (checkpoint ?? .distantPast) {
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
