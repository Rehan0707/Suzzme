import Foundation
import CryptoKit

struct CustomMCPTool: Sendable, Identifiable {
    let name: String
    let description: String
    let digest: String
    let inputSchema: Data
    let reviewable: Bool
    var id: String { name }
}
protocol CustomMCPServing: Sendable {
    func discover(endpoint: URL, address: String, token: String?) async throws -> [CustomMCPTool]
    func read(endpoint: URL, address: String, token: String?, tool: String, digest: String, arguments: Data) async throws -> String
}

/// Network connections use this exact public IPv4 address, with TLS verified for
/// the URL hostname. DNS and redirects cannot substitute another destination.
/// IPv6, proxies, local commands and automatic OAuth discovery are unavailable.
enum CustomMCPPolicy {
    static func endpoint(_ raw: String, address: String) -> URL? {
        guard raw.utf8.count <= 128, isPublicIPv4(address), let parts = URLComponents(string: raw),
              parts.scheme == "https", parts.port == nil || parts.port == 443,
              parts.user == nil, parts.password == nil, parts.fragment == nil, parts.query == nil,
              let host = parts.host, !host.isEmpty, host.count <= 100,
              host.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46].contains($0) }),
              !host.lowercased().hasSuffix(".local"), host.lowercased() != "localhost", host.contains("."),
              !parts.path.contains("\r"), !parts.path.contains("\n"),
              let url = parts.url else { return nil }
        if host.split(separator: ".").allSatisfy({ UInt8($0) != nil }), !isPublicIPv4(host) { return nil }
        return url
    }
    static func isPublicIPv4(_ raw: String) -> Bool {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty && ($0.count == 1 || $0.first != "0") }),
              let a = UInt8(parts[0]), let b = UInt8(parts[1]), let c = UInt8(parts[2]), let d = UInt8(parts[3]),
              a > 0, a < 224, a != 10, a != 127, !(a == 169 && b == 254),
              !(a == 172 && (16...31).contains(b)), !(a == 192 && b == 168),
              !(a == 100 && (64...127).contains(b)), !(a == 198 && (b == 18 || b == 19)),
              !(a == 192 && (b == 0 || (b == 88 && c == 99))),
              !(a == 198 && b == 51 && c == 100), !(a == 203 && b == 0 && c == 113) else { return false }
        return [a,b,c,d].map(String.init).joined(separator: ".") == raw
    }
    static func credential(_ token: String) -> Bool {
        token.isEmpty || (token.utf8.count <= 1024 && token.utf8.allSatisfy { (33...126).contains($0) })
    }
    static func permitsTool(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 100, name.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95].contains($0) }) else { return false }
        let words = name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        let readWords: Set<String> = ["read", "get", "list", "search", "query", "fetch", "lookup", "inspect", "describe", "status", "summary"]
        return !readWords.isDisjoint(with: words) && words.allSatisfy { !["write", "create", "update", "delete", "send", "publish", "execute", "run", "shell", "transfer", "pay", "purchase", "invite", "grant", "revoke", "set", "remove", "add", "complete"].contains($0) }
    }
    static func identity(_ url: URL, _ address: String) -> String {
        SHA256.hash(data: Data((url.absoluteString + "|" + address).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct CustomMCPReadRequest: Sendable {
    let accountID: UUID
    let tool: String
    let arguments: Data
}
