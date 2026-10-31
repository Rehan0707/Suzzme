import Foundation

struct GmailMessageListResponse: Decodable, Sendable {
    let messages: [GmailMessageReference]?
}

struct GmailMessageReference: Decodable, Sendable {
    let id: String
}

struct GmailMessageMetadataResponse: Decodable, Sendable {
    let id: String
    let internalDate: String?
    let payload: GmailMessagePayload?
    var labelIds: [String]? = nil
}

struct GmailMessagePayload: Decodable, Sendable {
    let headers: [GmailMessageHeader]?
    let mimeType: String?
    let filename: String?
    let body: GmailMessageBody?
    let parts: [GmailMessagePayload]?
}

struct GmailMessageBody: Decodable, Sendable {
    let data: String?
    let size: Int?
}

struct GmailMessageHeader: Decodable, Sendable {
    let name: String
    let value: String
}

extension GmailMessageMetadataResponse {
    func readableBody() -> String? {
        payload?.readableText(preferredMIME: "text/plain")
            ?? payload?.readableText(preferredMIME: "text/html")
    }

    func observation() -> InformationObservation? {
        guard let milliseconds = internalDate.flatMap(Double.init), milliseconds.isFinite else { return nil }
        let headers = payload?.headers ?? []
        let subject = headers.first { $0.name.caseInsensitiveCompare("subject") == .orderedSame }?.value
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let subject, !subject.isEmpty else { return nil }
        let from = headers.first { $0.name.caseInsensitiveCompare("from") == .orderedSame }?.value
        let sender = from.flatMap(Self.senderDisplayName(from:))
        let cleanSubject = String(subject.filter { !$0.isNewline && !$0.isControlCharacter }.prefix(180))
        let base = sender.map { "\($0): \(cleanSubject)" } ?? cleanSubject
        let rawTitle = (labelIds?.contains("UNREAD") == true ? "Unread · " : "") + base
        // Only the local model adapter may use the reserved summary marker.
        // A sender-controlled subject must not impersonate that classification.
        let title = rawTitle.hasPrefix("Important email · ") ? "Subject · " + rawTitle : rawTitle
        return InformationObservation(
            externalID: id,
            title: title,
            entities: sender.map { [$0] } ?? [],
            modifiedAt: Date(timeIntervalSince1970: milliseconds / 1_000),
            kindHint: .emailUpdate
        )
    }

    private static func senderDisplayName(from header: String) -> String? {
        guard let bracket = header.firstIndex(of: "<") else { return nil }
        let name = header[..<bracket]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !name.isEmpty else { return nil }
        return String(name.filter { !$0.isNewline && !$0.isControlCharacter }.prefix(60))
    }
}

private extension GmailMessagePayload {
    func readableText(preferredMIME: String, depth: Int = 0) -> String? {
        guard depth <= 6 else { return nil }
        if let parts {
            for part in parts {
                if let text = part.readableText(preferredMIME: preferredMIME, depth: depth + 1) {
                    return text
                }
            }
        }
        guard filename?.isEmpty != false,
              mimeType?.lowercased().hasPrefix(preferredMIME) == true,
              let encoded = body?.data, encoded.utf8.count <= 64_000 else { return nil }
        let normalized = encoded.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = normalized + String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        guard let decoded = Data(base64Encoded: padded), decoded.count <= 48_000,
              let utf8 = String(data: decoded, encoding: .utf8) else { return nil }
        let plain: String
        if preferredMIME == "text/html" {
            plain = Self.plainText(fromHTML: utf8)
        } else {
            plain = utf8
        }
        let cleaned = plain.replacingOccurrences(of: #"[\t\r ]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(6_000))
    }

    static func plainText(fromHTML html: String) -> String {
        var value = html
        for pattern in [#"(?is)<(script|style|head)[^>]*>.*?</\1>"#,
                        #"(?is)<!--.*?-->"#] {
            value = value.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        value = value.replacingOccurrences(of: #"(?i)<(br|/p|/div|/li|/tr)\b[^>]*>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for (entity, replacement) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"),
                                      ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")] {
            value = value.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        return value
    }
}

private extension Character {
    var isControlCharacter: Bool { unicodeScalars.allSatisfy(CharacterSet.controlCharacters.contains) }
}
