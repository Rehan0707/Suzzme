import Foundation

final class IntegrationRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum IntegrationCredentialGuard {
    static func containsSecret(in text: String, token: String) -> Bool {
        text.contains(token) || text.range(of: #"(?:github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|lin_api_[A-Za-z0-9_-]{20,}|Bearer\s+[A-Za-z0-9_.-]{20,})"#, options: .regularExpression) != nil
    }

    static func containsSecret(in data: Data, token: String) -> Bool {
        containsSecret(in: String(decoding: data, as: UTF8.self), token: token)
    }

    static func containsSecret(in value: Any, token: String) -> Bool {
        if let text = value as? String { return containsSecret(in: text, token: token) }
        if let values = value as? [String: Any] {
            return values.contains { containsSecret(in: $0.key, token: token) || containsSecret(in: $0.value, token: token) }
        }
        if let values = value as? [Any] { return values.contains { containsSecret(in: $0, token: token) } }
        return false
    }
}

