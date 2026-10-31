import Foundation
import FirebaseAuth

enum SupabaseAccountStoreError: LocalizedError {
    case configuration
    case rejected
    case deletionRejected

    var errorDescription: String? {
        switch self {
        case .configuration: "Account storage is not configured yet. Please try again later."
        case .rejected: "Suzzme could not save your account. Please try again."
        case .deletionRejected: "Suzzme could not delete your account data. Please try again."
        }
    }
}

/// Stores only the identity fields needed to identify an app account.
/// Firebase ID tokens are verified by Supabase Third-Party Auth before RLS runs.
enum SupabaseAccountStore {
    static func delete(_ user: User) async throws {
        guard let rawURL = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              let projectURL = URL(string: rawURL), projectURL.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String,
              !key.isEmpty, !key.contains("$(") else {
            throw SupabaseAccountStoreError.configuration
        }
        let token = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            user.getIDToken { token, error in
                if let error { continuation.resume(throwing: error) }
                else if let token { continuation.resume(returning: token) }
                else { continuation.resume(throwing: SupabaseAccountStoreError.deletionRejected) }
            }
        }
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/app_accounts"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "firebase_uid", value: "eq.\(user.uid)")]
        guard let url = components?.url else { throw SupabaseAccountStoreError.configuration }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              rows.count == 1, rows[0]["firebase_uid"] as? String == user.uid else {
            throw SupabaseAccountStoreError.deletionRejected
        }
    }

    static func save(_ user: User) async throws {
        guard let rawURL = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              let projectURL = URL(string: rawURL), projectURL.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String,
              !key.isEmpty, !key.contains("$("),
              let email = user.email, !email.isEmpty else {
            throw SupabaseAccountStoreError.configuration
        }

        let token = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            user.getIDToken { token, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: SupabaseAccountStoreError.rejected)
                }
            }
        }
        let endpoint = projectURL.appending(path: "rest/v1/app_accounts")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw SupabaseAccountStoreError.configuration
        }
        components.queryItems = [URLQueryItem(name: "on_conflict", value: "firebase_uid")]
        guard let url = components.url else { throw SupabaseAccountStoreError.configuration }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(AccountRecord(
            firebase_uid: user.uid,
            email: email,
            display_name: user.displayName,
            last_seen_at: ISO8601DateFormatter().string(from: Date())
        ))
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SupabaseAccountStoreError.rejected
        }
    }

    private struct AccountRecord: Encodable {
        let firebase_uid: String
        let email: String
        let display_name: String?
        let last_seen_at: String
    }
}
