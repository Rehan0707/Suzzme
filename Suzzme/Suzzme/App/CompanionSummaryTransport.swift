import Foundation

enum CompanionSummaryOwnership {
    static func permits(currentUID: String?, ownerUID: String?) -> Bool {
        guard let currentUID, !currentUID.isEmpty, let ownerUID else { return false }
        return currentUID == ownerUID
    }
}

enum CompanionSummaryStoreError: LocalizedError {
    case configuration, unavailable, invalidResponse, noAccount

    var errorDescription: String? {
        switch self {
        case .configuration: "Mac summary sharing is not configured in this build."
        case .unavailable: "Suzzme could not reach your shared summary. Try again later."
        case .invalidResponse: "The shared summary could not be read safely."
        case .noAccount: "Sign in to the same Suzzme account on both devices."
        }
    }
}

/// Each request retains one account's token and UID. The database independently
/// verifies that token and restricts every operation to its own account.
struct CompanionSummaryTransport {
    let projectURL: URL
    let publishableKey: String
    let uid: String
    let token: String
    var session: URLSession = .shared

    func load() async throws -> Data {
        try await perform(method: "GET", query: [
            URLQueryItem(name: "select", value: "firebase_uid,payload"),
            URLQueryItem(name: "firebase_uid", value: "eq.\(uid)"),
            URLQueryItem(name: "limit", value: "1")
        ])
    }

    func publish<Payload: Encodable>(_ payload: Payload, publishedAt: Date = .now) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(PublishRow(firebase_uid: uid, payload: payload, published_at: publishedAt))
        guard data.count <= 32_768 else { throw CompanionSummaryStoreError.invalidResponse }
        _ = try await perform(method: "POST", query: [URLQueryItem(name: "on_conflict", value: "firebase_uid")], body: data)
    }

    func remove() async throws {
        _ = try await perform(method: "DELETE", query: [URLQueryItem(name: "firebase_uid", value: "eq.\(uid)")])
    }

    private func perform(method: String, query: [URLQueryItem], body: Data? = nil) async throws -> Data {
        guard projectURL.scheme == "https", projectURL.host != nil,
              !publishableKey.isEmpty, !uid.isEmpty, !token.isEmpty else {
            throw CompanionSummaryStoreError.configuration
        }
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/companion_summaries"), resolvingAgainstBaseURL: false)
        components?.queryItems = query
        guard let url = components?.url else { throw CompanionSummaryStoreError.configuration }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        }
        do {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw CompanionSummaryStoreError.unavailable
            }
            guard data.count <= 65_536 else { throw CompanionSummaryStoreError.invalidResponse }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CompanionSummaryStoreError {
            throw error
        } catch {
            throw CompanionSummaryStoreError.unavailable
        }
    }

    private struct PublishRow<Payload: Encodable>: Encodable {
        let firebase_uid: String
        let payload: Payload
        let published_at: Date
    }
}

/// A removal waits for any earlier upload, so an in-flight upload cannot
/// resurrect the summary after sharing is turned off.
@MainActor final class CompanionSummaryMutationQueue {
    private var tail: Task<Void, Never>?
    private var owner: UUID?

    func run(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = tail
        let id = UUID()
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        owner = id
        tail = task
        await task.value
        if owner == id { owner = nil; tail = nil }
    }
}
