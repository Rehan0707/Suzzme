import Foundation
import FirebaseAuth

/// Account-owned schedule. Revision prevents a stale device overwriting a newer choice.
struct CompanionAccountPreferences: Codable, Sendable, Equatable {
    let firebase_uid: String
    var daily_enabled: Bool
    var urgent_enabled: Bool
    var hour: Int
    var minute: Int
    var time_zone: String
    let revision: Int

    var isValid: Bool {
        !firebase_uid.isEmpty && revision > 0 && (0...23).contains(hour)
            && (0...59).contains(minute) && TimeZone(identifier: time_zone) != nil
    }
}

struct CompanionDeviceRegistration: Encodable, Sendable, Equatable {
    let p_installation_id: UUID
    let p_device_token: String?
    let p_start_token: String?
    let p_activity_token: String?
    let p_activity_id: String?
    let p_environment: String
    let p_routine: Bool
    let p_urgent: Bool
}

@MainActor enum CompanionAccountDeliveryStore {
    static func loadPreferences(expectedUID: String) async throws -> CompanionAccountPreferences? {
        let data = try await request(path: "companion_preferences", method: "GET", uid: expectedUID,
            query: [.init(name: "firebase_uid", value: "eq.\(expectedUID)"), .init(name: "limit", value: "1")])
        let rows = try JSONDecoder().decode([CompanionAccountPreferences].self, from: data)
        guard rows.count <= 1, rows.allSatisfy({ $0.firebase_uid == expectedUID && $0.isValid }) else {
            throw CompanionSummaryStoreError.invalidResponse
        }
        return rows.first
    }

    static func savePreferences(_ value: CompanionAccountPreferences, expectedRevision: Int) async throws -> CompanionAccountPreferences {
        struct Body: Encodable {
            let p_daily: Bool; let p_urgent: Bool; let p_hour: Int; let p_minute: Int
            let p_time_zone: String; let p_expected_revision: Int
        }
        let data = try await request(path: "rpc/save_companion_preferences", method: "POST", uid: value.firebase_uid,
            body: JSONEncoder().encode(Body(p_daily: value.daily_enabled, p_urgent: value.urgent_enabled,
                p_hour: value.hour, p_minute: value.minute, p_time_zone: value.time_zone, p_expected_revision: expectedRevision)))
        let saved = try JSONDecoder().decode(CompanionAccountPreferences.self, from: data)
        guard saved.firebase_uid == value.firebase_uid, saved.isValid else { throw CompanionSummaryStoreError.invalidResponse }
        return saved
    }

    static func register(_ value: CompanionDeviceRegistration, uid: String) async throws {
        _ = try await request(path: "rpc/register_companion_device", method: "POST", uid: uid, body: JSONEncoder().encode(value))
    }

    static func unregister(installationID: UUID, uid: String) async throws {
        struct Body: Encodable { let p_installation_id: UUID }
        _ = try await request(path: "rpc/unregister_companion_device", method: "POST", uid: uid,
            body: JSONEncoder().encode(Body(p_installation_id: installationID)))
    }

    private static func request(path: String, method: String, uid: String,
                                query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        let (project, key, user, token) = try await CompanionSummaryStore.configuration()
        guard user.uid == uid else { throw CompanionSummaryStoreError.noAccount }
        var components = URLComponents(url: project.appending(path: "rest/v1/\(path)"), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw CompanionSummaryStoreError.configuration }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard CompanionSummaryStore.currentUser?.uid == uid else { throw CompanionSummaryStoreError.noAccount }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CompanionSummaryStoreError.unavailable
        }
        guard data.count <= 65_536 else { throw CompanionSummaryStoreError.invalidResponse }
        return data
    }
}
