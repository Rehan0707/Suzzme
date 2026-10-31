import Foundation

enum GmailScope {
    static let metadata = "https://www.googleapis.com/auth/gmail.metadata"
    static let readonly = "https://www.googleapis.com/auth/gmail.readonly"
}

enum GmailLimits {
    static let messagesPerRefresh = 30
    static let bodiesPerRefresh = 12
    static let responseBytes = 256 * 1024
    static let refreshSeconds: TimeInterval = 60
}

struct GmailBodySummary: Sendable {
    let text: String
    let usedOnDeviceModel: Bool
}

struct GmailInformationSource: InformationSource {
    let id = InformationSourceID.gmail
    let account: any GmailAuthorizationProviding
    var transport: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
        try await GmailHTTPTransport.send(request)
    }
    var canSummarize: @Sendable () async -> Bool = { false }
    var summarize: @Sendable (String) async throws -> GmailBodySummary = { _ in
        GmailBodySummary(text: "", usedOnDeviceModel: false)
    }

    func authorization() async -> InformationHealthState {
        guard let selection = await account.gmailSelection() else { return .permissionRequired }
        if selection.includeBodies {
            guard await account.gmailBodyAccess() else { return .permissionRequired }
        }
        return await account.authorization()
    }

    func fetch(now: Date, checkpoint: Date?) async throws -> InformationBatch {
        guard let selection = await account.gmailSelection() else { throw InformationError.authorizationRequired }
        let grant = try await account.accessGrant()
        let deadline = ContinuousClock.now.advanced(by: .seconds(GmailLimits.refreshSeconds))
        let window = DateInterval(start: now.addingTimeInterval(-7 * 86400), end: now)
        let canUseModel = selection.includeBodies ? await canSummarize() : false
        let useBodies = selection.includeBodies && canUseModel
        let references = try await listInboxMessages(grant: grant, selection: selection, deadline: deadline)
        var observations: [InformationObservation] = []
        var validatedIDs: [String] = []
        var bodyCandidates: [(index: Int, id: String, internalDate: String?)] = []

        for reference in references.prefix(GmailLimits.messagesPerRefresh) {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { break }
            let metadata: GmailMessageMetadataResponse?
            do { metadata = try await message(id: reference.id, full: false, grant: grant, deadline: deadline) }
            catch InformationError.unavailable where !observations.isEmpty { break }
            guard let metadata else { continue }
            validatedIDs.append(grant.accountNamespace + selection.prefix + metadata.id)
            guard let observation = metadata.observation(), window.contains(observation.modifiedAt) else { continue }
            observations.append(InformationObservation(
                externalID: grant.accountNamespace + selection.prefix + observation.externalID,
                title: observation.title, entities: observation.entities,
                modifiedAt: observation.modifiedAt, effectiveAt: observation.modifiedAt, kindHint: observation.kindHint
            ))
            if useBodies && bodyCandidates.count < GmailLimits.bodiesPerRefresh {
                bodyCandidates.append((observations.count - 1, reference.id, metadata.internalDate))
            }
        }

        // Keep the authorized header snapshot even if local generation exhausts
        // the refresh budget. Raw message bodies never enter the stored batch.
        for candidate in bodyCandidates {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { break }
            let full: GmailMessageMetadataResponse?
            do { full = try await message(id: candidate.id, full: true, grant: grant, deadline: deadline) }
            catch GmailAPIError.tooLarge { continue }
            catch InformationError.unavailable { break }
            guard let full, full.internalDate == candidate.internalDate,
                  let body = full.readableBody() else { continue }
            let header = observations[candidate.index]
            let input = "\(header.title)\n\(body)"
            guard PrivacyEngine().classify(input).policy != .neverProcess else { continue }
            do {
                let result = try await summarize(input)
                guard result.usedOnDeviceModel, !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      PrivacyEngine().classify(result.text).policy != .neverProcess,
                      result.text.range(of: #"(?i)(?:https?://|www\.|\b[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,})"#,
                          options: .regularExpression) == nil else { continue }
                observations[candidate.index] = InformationObservation(
                    externalID: header.externalID,
                    title: "Important email · " + String(result.text.prefix(210)),
                    entities: header.entities,
                    modifiedAt: header.modifiedAt, effectiveAt: header.modifiedAt,
                    kindHint: header.kindHint
                )
            } catch is CancellationError { throw CancellationError() }
            catch { /* Keep the authorized header; never persist the raw body. */ }
        }

        try await account.validate(grant)
        guard await account.gmailSelection() == selection else { throw InformationError.staleCycle }
        return InformationBatch(
            observations: observations,
            complete: false,
            window: window,
            validatedExternalIDs: validatedIDs
        )
    }

    func permits(_ event: InformationEvent, now: Date) async -> Bool {
        await account.permitsGmailEvent(event)
    }

    private func listInboxMessages(grant: GmailAccessGrant, selection: GmailSelection, deadline: ContinuousClock.Instant) async throws -> [GmailMessageReference] {
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")
        components?.queryItems = [
            URLQueryItem(name: "maxResults", value: String(GmailLimits.messagesPerRefresh)),
            URLQueryItem(name: "fields", value: "messages(id),nextPageToken")
        ] + selection.mode.labelIDs.map { URLQueryItem(name: "labelIds", value: $0) }
        guard let url = components?.url else { throw InformationError.malformed }
        let data = try await request(url: url, grant: grant, deadline: deadline)
        let references = try JSONDecoder().decode(GmailMessageListResponse.self, from: data).messages ?? []
        guard references.count <= GmailLimits.messagesPerRefresh,
              references.allSatisfy({ Self.validMessageID($0.id) }),
              Set(references.map(\.id)).count == references.count else { throw InformationError.malformed }
        return references
    }

    private func message(id: String, full: Bool, grant: GmailAccessGrant, deadline: ContinuousClock.Instant) async throws -> GmailMessageMetadataResponse? {
        guard var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)") else {
            throw InformationError.malformed
        }
        components.queryItems = [
            URLQueryItem(name: "format", value: full ? "full" : "metadata"),
            URLQueryItem(name: "fields", value: full ? "id,internalDate,labelIds,payload" : "id,internalDate,labelIds,payload(headers(name,value))")
        ] + (full ? [] : [URLQueryItem(name: "metadataHeaders", value: "From"),
                           URLQueryItem(name: "metadataHeaders", value: "Subject")])
        guard let url = components.url else { throw InformationError.malformed }
        do {
            let data = try await request(url: url, grant: grant, deadline: deadline)
            let message = try JSONDecoder().decode(GmailMessageMetadataResponse.self, from: data)
            guard message.id == id else { throw InformationError.malformed }
            return message
        } catch GmailAPIError.notFound {
            return nil
        }
    }

    private func request(url: URL, grant: GmailAccessGrant, deadline: ContinuousClock.Instant) async throws -> Data {
        try Task.checkCancellation()
        try await account.validate(grant)
        let remaining = ContinuousClock.now.duration(to: deadline).components
        let seconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
        guard seconds > 0 else { throw InformationError.unavailable }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = min(20, seconds)
        request.setValue("Bearer \(grant.token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        try await account.validate(grant)
        guard let response = response as? HTTPURLResponse else { throw InformationError.unavailable }
        guard response.url == url else { throw InformationError.malformed }
        guard data.count <= GmailLimits.responseBytes else { throw GmailAPIError.tooLarge }
        switch response.statusCode {
        case 200...299: return data
        case 401:
            await account.invalidate(grant, state: .authorizationExpired)
            throw InformationError.authorizationExpired
        case 403:
            await account.invalidate(grant, state: .permissionDenied)
            throw InformationError.permissionDenied
        case 404: throw GmailAPIError.notFound
        default: throw InformationError.unavailable
        }
    }

    private static func validMessageID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
}

/// Native, fixed-origin metadata reads. No cookies, cache, redirects or cloud inference.
/// Stream limits apply before decoding, rather than after an unbounded allocation.
enum GmailHTTPTransport {
    static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard permits(request) else { throw InformationError.malformed }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: GmailRedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard response.url == request.url, let http = response as? HTTPURLResponse,
              !(300...399).contains(http.statusCode),
              response.expectedContentLength <= Int64(GmailLimits.responseBytes) else { throw GmailAPIError.tooLarge }
        // Error bodies are unnecessary and may contain private upstream details.
        guard (200...299).contains(http.statusCode) else { return (Data(), response) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < GmailLimits.responseBytes else { throw GmailAPIError.tooLarge }
            data.append(byte)
        }
        return (data, response)
    }

    static func permits(_ request: URLRequest) -> Bool {
        guard request.httpMethod == "GET", request.httpBody == nil,
              let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == "gmail.googleapis.com", parts.port == nil,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              let authorization = request.value(forHTTPHeaderField: "Authorization"),
              authorization.hasPrefix("Bearer "), authorization.count > 7 else { return false }
        let root = "/gmail/v1/users/me/messages"
        if parts.path == root { return true }
        let prefix = root + "/"
        guard parts.path.hasPrefix(prefix) else { return false }
        let id = parts.path.dropFirst(prefix.count)
        return !id.isEmpty && id.utf8.count <= 128 && id.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
}

private final class GmailRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private enum GmailAPIError: Error {
    case notFound, tooLarge
}
