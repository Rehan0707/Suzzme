import Foundation

enum SuzzmePrivacyPolicy: String, Codable, Sendable { case localOnly, allowSummary, allowExternalWithRedaction, neverProcess }

struct SuzzmePrivacyDecision: Sendable, Equatable {
    let sensitivity: SuzzmeContextSensitivity
    let policy: SuzzmePrivacyPolicy
    let reason: String
}

/// Deterministic, on-device first-pass classifier. Content is never logged.
struct PrivacyEngine: Sendable {
    func classify(_ content: String) -> SuzzmePrivacyDecision {
        let value = content.lowercased()
        if matches(value, terms: ["password", "passcode", "cvv", "security code", "private key", "one-time code", "otp", "verification code", "access token", "bearer ", "api key"]) {
            return .init(sensitivity: .restricted, policy: .neverProcess, reason: "Contains authentication or secret data.")
        }
        if matches(value, terms: ["medical", "diagnosis", "bank account", "credit card", "social security", "financial"]) {
            return .init(sensitivity: .sensitive, policy: .localOnly, reason: "Contains sensitive personal information.")
        }
        if matches(value, terms: ["my ", "i am", "meeting", "assignment", "calendar"]) {
            return .init(sensitivity: .personal, policy: .localOnly, reason: "Personal context remains on device.")
        }
        return .init(sensitivity: .public, policy: .allowSummary, reason: "No sensitive pattern detected.")
    }
    private func matches(_ content: String, terms: [String]) -> Bool { terms.contains { content.contains($0) } }
}
