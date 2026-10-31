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
        let value = content.precomposedStringWithCompatibilityMapping.lowercased()
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        if matches(value, terms: ["password", "passcode", "cvv", "security code", "private key", "one-time code", "otp", "verification code", "access token", "bearer ", "api key", "api_key", "apikey", "api-key", "access_token", "refresh_token", "auth_token", "session_token", "client_secret", "sessionid", "session secret", "authentication token", "one time password", "one-time password", "-----begin", "sk-proj-"]) {
            return .init(sensitivity: .restricted, policy: .neverProcess, reason: "Contains authentication or secret data.")
        }
        if containsHighRiskIdentifier(value) {
            return .init(sensitivity: .restricted, policy: .neverProcess, reason: "Contains a high-risk personal identifier.")
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

    /// A conservative local backstop for OCR and model output. Context words are
    /// required for passports, while card-like digit runs must pass Luhn.
    private func containsHighRiskIdentifier(_ content: String) -> Bool {
        matchesPattern(#"\b(?!000|666|9\d{2})\d{3}[ -](?!00)\d{2}[ -](?!0000)\d{4}\b"#, in: content)
            || containsPaymentCardNumber(content)
            || matchesPattern(#"\bpassport\b.{0,24}\b(?=[a-z0-9]*\d)[a-z0-9]{6,9}\b"#, in: content)
    }

    private func containsPaymentCardNumber(_ content: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: #"\b\d(?:[ -]?\d){12,18}\b"#) else { return false }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return expression.matches(in: content, range: range).contains { match in
            guard let swiftRange = Range(match.range, in: content) else { return false }
            let digits = content[swiftRange].compactMap(\.wholeNumberValue)
            return (13...19).contains(digits.count) && passesLuhn(digits)
        }
    }

    private func passesLuhn(_ digits: [Int]) -> Bool {
        let sum = digits.reversed().enumerated().reduce(into: 0) { total, item in
            let (offset, digit) = item
            let doubled = offset.isMultiple(of: 2) ? digit : digit * 2
            total += doubled > 9 ? doubled - 9 : doubled
        }
        return sum.isMultiple(of: 10)
    }

    private func matchesPattern(_ pattern: String, in content: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return expression.firstMatch(in: content, range: range) != nil
    }
}
