import Foundation
import Darwin
import os

enum WebURLPolicy {
    static func validate(_ value: String) throws -> URL {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw WatchedLinkError.invalidURL }
        return try validate(url)
    }

    static func validate(_ url: URL) throws -> URL {
        guard url.scheme?.lowercased() == "https" else { throw WatchedLinkError.unsupportedScheme }
        guard url.user == nil, url.password == nil, let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")), !host.isEmpty else { throw WatchedLinkError.invalidURL }
        guard url.absoluteString.utf8.count <= 2048,
              !host.contains("%"),
              PrivacyEngine().classify(url.absoluteString.removingPercentEncoding ?? url.absoluteString).policy != .neverProcess else { throw WatchedLinkError.invalidURL }
        guard !isBlockedHost(host) else { throw WatchedLinkError.blockedHost }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        components?.host = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        components?.fragment = nil
        guard let canonical = components?.url else { throw WatchedLinkError.invalidURL }
        return canonical
    }

    static func validateResolvedAddresses(for url: URL, resolver: WebHostResolving = SystemWebHostResolver()) async throws {
        guard let host = url.host else { throw WatchedLinkError.invalidURL }
        try Task.checkCancellation()
        let addresses = try await resolver.addresses(for: host)
        try Task.checkCancellation()
        guard !addresses.isEmpty, addresses.allSatisfy({ isNumericAddress($0) && !isBlockedAddress($0) }) else { throw WatchedLinkError.blockedHost }
    }

    static func isBlockedHost(_ host: String) -> Bool {
        let value = host.trimmingCharacters(in: CharacterSet(charactersIn: "[].")).lowercased()
        if value == "localhost" || value.hasSuffix(".localhost") || value.hasSuffix(".local") || value.hasSuffix(".internal") { return true }
        return isBlockedAddress(value)
    }

    private static func isNumericAddress(_ value: String) -> Bool {
        var v4 = in_addr(); var v6 = in6_addr()
        return inet_pton(AF_INET, value, &v4) == 1 || inet_pton(AF_INET6, value, &v6) == 1
    }

    static func isBlockedAddress(_ address: String) -> Bool {
        let value = address.trimmingCharacters(in: CharacterSet(charactersIn: "[].")).lowercased()
        var ipv4 = in_addr()
        if inet_pton(AF_INET, value, &ipv4) == 1 {
            let raw = UInt32(bigEndian: ipv4.s_addr)
            return isBlockedIPv4([
                UInt8((raw >> 24) & 0xff), UInt8((raw >> 16) & 0xff),
                UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)
            ])
        }

        var ipv6 = in6_addr()
        guard inet_pton(AF_INET6, value, &ipv6) == 1 else { return false }
        let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
        guard bytes.count == 16 else { return true }
        if bytes.allSatisfy({ $0 == 0 }) || bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1 { return true }
        if bytes[0] == 0xff || bytes[0] & 0xfe == 0xfc || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80) { return true }
        if bytes.prefix(4).elementsEqual([0x20, 0x01, 0x0d, 0xb8]) { return true }
        if bytes.prefix(12).elementsEqual(Array(repeating: 0, count: 10) + [0xff, 0xff]) {
            return isBlockedIPv4(Array(bytes.suffix(4)))
        }
        if bytes.prefix(12).allSatisfy({ $0 == 0 }) { return true }
        return false
    }

    private static func isBlockedIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return true }
        let a = Int(bytes[0]), b = Int(bytes[1]), c = Int(bytes[2])
        return a == 0 || a == 10 || a == 127
            || (a == 100 && 64...127 ~= b)
            || (a == 169 && b == 254)
            || (a == 172 && 16...31 ~= b)
            || (a == 192 && b == 0 && c == 0)
            || (a == 192 && b == 0 && c == 2)
            || (a == 192 && b == 88 && c == 99)
            || (a == 192 && b == 168)
            || (a == 198 && (b == 18 || b == 19))
            || (a == 198 && b == 51 && c == 100)
            || (a == 203 && b == 0 && c == 113)
            || a >= 224
    }
}

protocol WebHostResolving: Sendable {
    func addresses(for host: String) async throws -> [String]
}

/// getaddrinfo has no cancellable Darwin API. Bound caller latency and permit
/// only one outstanding OS resolution, even after cancellation or timeout.
private final class WebDNSCompletion: Sendable {
    private struct State {
        var continuation: CheckedContinuation<[String], any Error>?
        var result: Result<[String], any Error>?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    func install(_ continuation: CheckedContinuation<[String], any Error>) {
        let result: Result<[String], any Error>? = state.withLock { value in
            if let result = value.result { return result }
            value.continuation = continuation; return nil
        }
        if let result { continuation.resume(with: result) }
    }
    func finish(_ result: Result<[String], any Error>) {
        let continuation = state.withLock { value in
            guard value.result == nil else { return Optional<CheckedContinuation<[String], any Error>>.none }
            value.result = result
            defer { value.continuation = nil }
            return value.continuation
        }
        continuation?.resume(with: result)
    }
}

struct SystemWebHostResolver: WebHostResolving {
    private static let busy = OSAllocatedUnfairLock(initialState: false)
    func addresses(for host: String) async throws -> [String] {
        try Task.checkCancellation()
        guard Self.busy.withLock({ busy in
            guard !busy else { return false }; busy = true; return true
        }) else { throw WatchedLinkError.unavailable }
        let completion = WebDNSCompletion()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + WatchedLinkLimits.timeout) {
                    completion.finish(.failure(WatchedLinkError.timeout))
                }
                DispatchQueue.global(qos: .utility).async {
                    defer { Self.busy.withLock { $0 = false } }
                    completion.finish(Result { try Self.resolve(host) })
                }
            }
        } onCancel: { completion.finish(.failure(CancellationError())) }
    }

    private static func resolve(_ host: String) throws -> [String] {
        var hints = addrinfo(ai_flags: AI_ADDRCONFIG, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { throw WatchedLinkError.unavailable }
        defer { freeaddrinfo(result) }
        var values: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let current = cursor {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(current.pointee.ai_addr, current.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
                values.append(String(decoding: buffer[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self))
            }
            cursor = current.pointee.ai_next
        }
        return Array(Set(values)).sorted()
    }
}
