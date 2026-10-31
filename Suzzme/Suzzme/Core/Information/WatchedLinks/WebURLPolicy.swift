import Foundation
import Darwin
import os
import dnssd

/// A numeric endpoint approved by the address policy, not evidence that a socket used it.
/// Only this policy can construct one; transports must connect to numericHost directly.
struct WebApprovedAddress: Sendable, Hashable {
    enum Family: Sendable, Hashable { case ipv4, ipv6 }
    let numericHost: String
    let family: Family
    fileprivate init(numericHost: String, family: Family) {
        self.numericHost = numericHost; self.family = family
    }
}

struct WebHostResolution: Sendable {
    let addresses: [String]
    /// DNS identity for the collected answer. Production rejects CNAME records.
    let canonicalName: String?
    init(addresses: [String], canonicalName: String? = nil) {
        self.addresses = addresses; self.canonicalName = canonicalName
    }
}

enum WebURLPolicy {
    static func validate(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { throw WatchedLinkError.invalidURL }
        guard url.scheme?.lowercased() == "https" else { throw WatchedLinkError.unsupportedScheme }
        try validateAuthoritySpelling(trimmed)
        return try validate(url)
    }

    static func validate(_ url: URL) throws -> URL {
        guard url.scheme?.lowercased() == "https" else { throw WatchedLinkError.unsupportedScheme }
        try validateAuthoritySpelling(url.absoluteString)
        guard url.user == nil, url.password == nil, let rawHost = url.host,
              url.port == nil || url.port == 443 else { throw WatchedLinkError.invalidURL }
        guard url.absoluteString.utf8.count <= 2048,
              PrivacyEngine().classify(url.absoluteString.removingPercentEncoding ?? url.absoluteString).policy != .neverProcess else { throw WatchedLinkError.invalidURL }
        let host = try canonicalHost(rawHost)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        components?.host = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        components?.port = nil
        components?.fragment = nil
        guard let canonical = components?.url else { throw WatchedLinkError.invalidURL }
        return canonical
    }

    /// Returns the exact immutable numeric choices a future transport may consume.
    /// It performs no connection, and does not certify socket pinning or TLS trust.
    static func approvedAddresses(for url: URL, resolver: any WebHostResolving = SystemWebHostResolver(), timeout: TimeInterval = WatchedLinkLimits.dnsTimeout) async throws -> [WebApprovedAddress] {
        let canonical = try validate(url)
        guard let rawHost = canonical.host else { throw WatchedLinkError.invalidURL }
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        try Task.checkCancellation()
        let answer = try await resolver.resolution(for: host, timeout: timeout)
        try Task.checkCancellation()
        // Resolver implementations must not substitute a different DNS identity.
        // The production resolver separately rejects every reported CNAME.
        if let alias = answer.canonicalName {
            guard try canonicalHost(alias) == host else { throw WatchedLinkError.blockedHost }
        }
        guard !answer.addresses.isEmpty, answer.addresses.count <= 64 else { throw WatchedLinkError.blockedHost }
        var approved: [WebApprovedAddress] = []
        for address in answer.addresses {
            guard let numeric = numericAddress(address), !isBlockedAddress(address) else { throw WatchedLinkError.blockedHost }
            if !approved.contains(numeric) { approved.append(numeric) }
        }
        return approved
    }

    static func validateResolvedAddresses(for url: URL, resolver: WebHostResolving = SystemWebHostResolver()) async throws {
        _ = try await approvedAddresses(for: url, resolver: resolver)
    }

    static func isBlockedHost(_ host: String) -> Bool {
        (try? canonicalHost(host)) == nil
    }

    private static func validateAuthoritySpelling(_ value: String) throws {
        guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !value.contains("\\") else { throw WatchedLinkError.invalidURL }
        guard let separator = value.range(of: "://") else { throw WatchedLinkError.unsupportedScheme }
        let authority = value[separator.upperBound...].prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard !authority.isEmpty, authority.utf8.allSatisfy({ $0 > 32 && $0 < 127 }),
              !authority.contains("%"), !authority.hasSuffix(":") else { throw WatchedLinkError.invalidURL }
    }

    private static func canonicalHost(_ raw: String) throws -> String {
        var host = raw.lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") { host.removeFirst(); host.removeLast() }
        guard !host.isEmpty, !host.contains("%") else { throw WatchedLinkError.invalidURL }
        // Watched URLs require a DNS identity for Host, SNI and certificate
        // hostname verification. Numeric addresses are only connection outputs.
        guard numericAddress(host) == nil else { throw WatchedLinkError.blockedHost }
        guard !host.contains(":") else { throw WatchedLinkError.invalidURL }
        if host.hasSuffix(".") { host.removeLast() }
        let prohibited = ["localhost", "local", "internal", "home.arpa", "localdomain", "onion", "test", "invalid", "example"]
        guard !prohibited.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { throw WatchedLinkError.blockedHost }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.utf8.count <= 253, labels.count >= 2,
              labels.allSatisfy({ label in
                  !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-"
                      && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
              }) else { throw WatchedLinkError.invalidURL }
        // Numeric final labels cannot be DNS TLDs. This also rejects inet_aton
        // integer/short/octal/hex spellings before an OS resolver interprets them.
        guard let last = labels.last,
              !last.utf8.allSatisfy({ (48...57).contains($0) }),
              !(last.hasPrefix("0x") && last.dropFirst(2).utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })) else { throw WatchedLinkError.blockedHost }
        return host
    }

    private static func numericAddress(_ value: String) -> WebApprovedAddress? {
        guard !value.isEmpty, value.utf8.allSatisfy({ $0 < 128 }) else { return nil }
        var ipv4 = in_addr()
        if inet_pton(AF_INET, value, &ipv4) == 1 {
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &ipv4, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            return .init(numericHost: decodedCString(buffer), family: .ipv4)
        }
        var ipv6 = in6_addr()
        guard inet_pton(AF_INET6, value, &ipv6) == 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &ipv6, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
        return .init(numericHost: decodedCString(buffer), family: .ipv6)
    }

    static func isBlockedAddress(_ address: String) -> Bool {
        guard numericAddress(address) != nil else { return true }
        var ipv4 = in_addr()
        if inet_pton(AF_INET, address, &ipv4) == 1 { return legacyIsBlockedIPv4(ipv4Bytes(ipv4)) }
        var ipv6 = in6_addr()
        guard inet_pton(AF_INET6, address, &ipv6) == 1 else { return true }
        let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
        guard bytes.count == 16 else { return true }
        if bytes.prefix(12).elementsEqual(Array(repeating: 0, count: 10) + [0xff, 0xff]) {
            return legacyIsBlockedIPv4(Array(bytes.suffix(4)))
        }
        // Conservative IANA allocated global-unicast snapshot (2025-10-10).
        // Everything else, including translation/tunnel, special-use and future
        // reserved ranges, is denied. New allocations require policy review.
        // https://www.iana.org/assignments/ipv6-unicast-address-assignments/
        let first = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let second = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        if first == 0x2001 {
            if second == 0x0db8 { return true }
            return !((0x0200...0x0fff).contains(second) || (0x1200...0x4dff).contains(second)
                || (0x5000...0x5fff).contains(second) || (0x8000...0xbfff).contains(second))
        }
        if first == 0x2003 { return second > 0x3fff }
        return !((0x2400...0x241f).contains(first) || (0x2600...0x2611).contains(first)
            || (0x2620...0x2621).contains(first) || (0x2630...0x263f).contains(first)
            || (0x2800...0x280f).contains(first) || (0x2a00...0x2a1f).contains(first)
            || (0x2c00...0x2c0f).contains(first))
    }

    /// Frozen schema-1 read policy. Tightening new network eligibility must not
    /// hide previously accepted saved pages or prevent their individual removal.
    /// This result grants no network, Open Source, or Daily Summary authority.
    static func validateLegacyStoredURL(_ url: URL) throws -> URL {
        guard url.scheme?.lowercased() == "https" else { throw WatchedLinkError.unsupportedScheme }
        guard url.user == nil, url.password == nil, let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")), !host.isEmpty else { throw WatchedLinkError.invalidURL }
        guard url.absoluteString.utf8.count <= 2048, !host.contains("%"),
              PrivacyEngine().classify(url.absoluteString.removingPercentEncoding ?? url.absoluteString).policy != .neverProcess else { throw WatchedLinkError.invalidURL }
        let value = host.trimmingCharacters(in: CharacterSet(charactersIn: "[].")).lowercased()
        guard value != "localhost", !value.hasSuffix(".localhost"), !value.hasSuffix(".local"),
              !value.hasSuffix(".internal"), !legacyIsBlockedAddress(value) else { throw WatchedLinkError.blockedHost }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        components?.host = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        components?.fragment = nil
        guard let canonical = components?.url else { throw WatchedLinkError.invalidURL }
        return canonical
    }

    private static func legacyIsBlockedAddress(_ value: String) -> Bool {
        var ipv4 = in_addr()
        if inet_pton(AF_INET, value, &ipv4) == 1 { return legacyIsBlockedIPv4(ipv4Bytes(ipv4)) }
        var ipv6 = in6_addr()
        guard inet_pton(AF_INET6, value, &ipv6) == 1 else { return false }
        let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
        guard bytes.count == 16 else { return true }
        if bytes.allSatisfy({ $0 == 0 }) || bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1 { return true }
        if bytes[0] == 0xff || bytes[0] & 0xfe == 0xfc || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80) { return true }
        if bytes.prefix(4).elementsEqual([0x20, 0x01, 0x0d, 0xb8]) { return true }
        if bytes.prefix(12).elementsEqual(Array(repeating: 0, count: 10) + [0xff, 0xff]) {
            return legacyIsBlockedIPv4(Array(bytes.suffix(4)))
        }
        if bytes.prefix(12).allSatisfy({ $0 == 0 }) { return true }
        return false
    }

    private static func ipv4Bytes(_ address: in_addr) -> [UInt8] {
        let raw = UInt32(bigEndian: address.s_addr)
        return [UInt8((raw >> 24) & 0xff), UInt8((raw >> 16) & 0xff), UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
    }

    private static func decodedCString(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func legacyIsBlockedIPv4(_ bytes: [UInt8]) -> Bool {
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
    func resolution(for host: String) async throws -> WebHostResolution
    func resolution(for host: String, timeout: TimeInterval) async throws -> WebHostResolution
}

extension WebHostResolving {
    func resolution(for host: String) async throws -> WebHostResolution {
        .init(addresses: try await addresses(for: host))
    }
    func resolution(for host: String, timeout: TimeInterval) async throws -> WebHostResolution {
        try await resolution(for: host)
    }
}

/// Two independent DNS-SD queries avoid getaddrinfo's interface-family heuristics.
/// Termination deallocates both daemon operations before resuming the caller.
/// DNS-SD cancels their work immediately and drains its dispatch-source file
/// descriptor cleanup asynchronously; there is no blocked getaddrinfo worker.
struct SystemWebHostResolver: WebHostResolving {
    private static let busy = OSAllocatedUnfairLock(initialState: false)
    private let backend: any WebDNSBackend
    init() { backend = NativeWebDNSBackend() }
    private init(backend: any WebDNSBackend) { self.backend = backend }

    func addresses(for host: String) async throws -> [String] {
        try await resolution(for: host).addresses
    }
    func resolution(for host: String) async throws -> WebHostResolution {
        try await resolution(for: host, timeout: WatchedLinkLimits.dnsTimeout)
    }
    func resolution(for host: String, timeout: TimeInterval) async throws -> WebHostResolution {
        try Task.checkCancellation()
        guard timeout.isFinite, timeout > 0, timeout <= WatchedLinkLimits.dnsTimeout else { throw WatchedLinkError.timeout }
        guard try WebURLPolicy.validate("https://" + host + "/").host == host else { throw WatchedLinkError.invalidURL }
        guard Self.busy.withLock({ busy in
            guard !busy else { return false }; busy = true; return true
        }) else { throw WatchedLinkError.unavailable }
        defer { Self.busy.withLock { $0 = false } }
        return try await WebDNSOperation(host: host, timeout: timeout, backend: backend).run()
    }

    #if WATCHED_DNS_CHECKS
    static func validationScripted(_ steps: [WebDNSValidationStep], audit: @escaping @Sendable (WebDNSValidationAudit) -> Void) -> Self {
        Self(backend: ScriptedWebDNSBackend(steps: steps, audit: audit))
    }
    static func validationLocalOnly(negativeAnswers: Bool = true, audit: @escaping @Sendable (WebDNSValidationAudit) -> Void) -> Self {
        Self(backend: NativeWebDNSBackend(negativeAnswers: negativeAnswers, audit: audit))
    }
    #endif
}

private struct WebDNSRecord: Sendable {
    let requestedType: UInt16
    let flags: UInt32
    let error: Int32
    let name: String?
    let type: UInt16
    let recordClass: UInt16
    let bytes: Data
}

private protocol WebDNSToken: Sendable { func cancel() }
private protocol WebDNSBackend: Sendable {
    func start(host: String, type: UInt16, queue: DispatchQueue,
               receive: @escaping @Sendable (WebDNSRecord) -> Void) throws -> any WebDNSToken
}

/// All mutable state and every DNS-SD call are confined to this private serial
/// queue. C callbacks already arrive on that queue; cancellation only enqueues.
private final class WebDNSOperation: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.suzzme.watched-dns", qos: .utility)
    private let host: String
    private let deadline: DispatchTime
    private let backend: any WebDNSBackend
    private var terminal: Result<WebHostResolution, any Error>?
    private var continuation: CheckedContinuation<WebHostResolution, any Error>?
    private var tokens: [any WebDNSToken] = []
    private var timer: DispatchSourceTimer?
    private var completedFamilies: Set<UInt16> = []
    private var addresses: Set<String> = []
    private var records = 0

    init(host: String, timeout: TimeInterval, backend: any WebDNSBackend) {
        self.host = host; self.backend = backend
        deadline = .now() + timeout
    }
    func run() async throws -> WebHostResolution {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { self.begin(continuation) }
            }
        } onCancel: {
            self.queue.async { self.finish(.failure(CancellationError())) }
        }
    }
    private func begin(_ continuation: CheckedContinuation<WebHostResolution, any Error>) {
        dispatchPrecondition(condition: .onQueue(queue))
        if let terminal { continuation.resume(with: terminal); return }
        self.continuation = continuation
        guard DispatchTime.now() < deadline else { finish(.failure(WatchedLinkError.timeout)); return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: deadline)
        timer.setEventHandler { [weak self] in self?.finish(.failure(WatchedLinkError.timeout)) }
        self.timer = timer; timer.resume()
        do {
            for type in [UInt16(kDNSServiceType_A), UInt16(kDNSServiceType_AAAA)] {
                guard DispatchTime.now() < deadline else { throw WatchedLinkError.timeout }
                tokens.append(try backend.start(host: host, type: type, queue: queue) { [weak self] record in self?.receive(record) })
            }
        } catch { finish(.failure(error)) }
    }
    private func receive(_ record: WebDNSRecord) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard terminal == nil else { return }
        guard DispatchTime.now() < deadline else { finish(.failure(WatchedLinkError.timeout)); return }
        guard !completedFamilies.contains(record.requestedType) else { finish(.failure(WatchedLinkError.blockedHost)); return }
        if record.error == Int32(kDNSServiceErr_NoSuchRecord) {
            // Other callback fields are undefined on errors. The independently
            // owned query context identifies which family has no records.
            completedFamilies.insert(record.requestedType)
        } else if record.error != 0 {
            finish(.failure(WatchedLinkError.unavailable)); return
        } else {
            records += 1
            guard records <= 64, record.type == record.requestedType,
                  record.recordClass == UInt16(kDNSServiceClass_IN),
                  record.flags & UInt32(kDNSServiceFlagsAdd) != 0,
                  record.name?.lowercased() == host + ".",
                  let address = Self.address(record) else {
                // This also rejects CNAMEs without parsing or silently following
                // alias targets, unknown RR types, removals and malformed bytes.
                finish(.failure(WatchedLinkError.blockedHost)); return
            }
            addresses.insert(address)
            if record.flags & UInt32(kDNSServiceFlagsMoreComing) == 0 { completedFamilies.insert(record.requestedType) }
        }
        // MoreComing only closes this currently delivered answer batch. It is
        // never treated as completion of the other family or as a guarantee
        // that the daemon cannot report a later DNS change. No result is cached.
        if completedFamilies.count == 2 {
            guard !addresses.isEmpty else { finish(.failure(WatchedLinkError.blockedHost)); return }
            finish(.success(.init(addresses: addresses.sorted(), canonicalName: host)))
        }
    }
    private static func address(_ record: WebDNSRecord) -> String? {
        let family: Int32
        let length: Int
        if record.type == UInt16(kDNSServiceType_A) { family = AF_INET; length = 4 }
        else if record.type == UInt16(kDNSServiceType_AAAA) { family = AF_INET6; length = 16 }
        else { return nil }
        guard record.bytes.count == length else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let converted = record.bytes.withUnsafeBytes { bytes in inet_ntop(family, bytes.baseAddress, &buffer, socklen_t(buffer.count)) != nil }
        guard converted else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    private func finish(_ result: Result<WebHostResolution, any Error>) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard terminal == nil else { return }
        terminal = result
        timer?.cancel(); timer = nil
        // DNSServiceRefDeallocate must run on the callback queue. It terminates
        // queries before resumption; DNS-SD drains its cancelled dispatch-source
        // descriptor cleanup after the current queue block/callback unwinds.
        for token in tokens { token.cancel() }
        tokens.removeAll()
        let continuation = continuation; self.continuation = nil
        continuation?.resume(with: result)
    }
}

private final class WebDNSCallback: Sendable {
    let requestedType: UInt16
    let receive: @Sendable (WebDNSRecord) -> Void
    init(type: UInt16, receive: @escaping @Sendable (WebDNSRecord) -> Void) { requestedType = type; self.receive = receive }
}

/// This token is created, cancelled and released only on its callback queue.
private final class NativeWebDNSToken: WebDNSToken, @unchecked Sendable {
    private var reference: DNSServiceRef?
    private var context: UnsafeMutableRawPointer?
    private let queue: DispatchQueue
    #if WATCHED_DNS_CHECKS
    var validationAudit: (@Sendable (WebDNSValidationAudit) -> Void)?
    var validationType: UInt16 = 0
    #endif
    init(reference: DNSServiceRef, context: UnsafeMutableRawPointer, queue: DispatchQueue) {
        self.reference = reference; self.context = context; self.queue = queue
    }
    func cancel() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let reference, let context else { return }
        self.reference = nil; self.context = nil
        #if WATCHED_DNS_CHECKS
        let descriptor = DNSServiceRefSockFD(reference)
        let started = DispatchTime.now()
        #endif
        DNSServiceRefDeallocate(reference)
        Unmanaged<WebDNSCallback>.fromOpaque(context).release()
        #if WATCHED_DNS_CHECKS
        validationAudit?(.cancelled(validationType))
        if let validationAudit {
            Self.observeClosure(type: validationType, descriptor: descriptor, started: started, queue: queue, audit: validationAudit)
        }
        #endif
    }
    #if WATCHED_DNS_CHECKS
    // Test-only observation never owns/closes this descriptor. Native DNS-SD
    // owns its asynchronous dispatch-source cancellation and descriptor cleanup.
    private static func observeClosure(type: UInt16, descriptor: Int32, started: DispatchTime, queue: DispatchQueue,
                                       audit: @escaping @Sendable (WebDNSValidationAudit) -> Void) {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e9
        let closed = fcntl(descriptor, F_GETFD) == -1 && errno == EBADF
        if closed || elapsed >= 1 { audit(.descriptorClosed(type, descriptor, closed, elapsed)); return }
        queue.asyncAfter(deadline: .now() + .milliseconds(1)) {
            observeClosure(type: type, descriptor: descriptor, started: started, queue: queue, audit: audit)
        }
    }
    #endif
}

private struct NativeWebDNSBackend: WebDNSBackend {
    private let interfaceIndex: UInt32
    private let flags: UInt32
    #if WATCHED_DNS_CHECKS
    private let validationAudit: (@Sendable (WebDNSValidationAudit) -> Void)?
    #endif
    init() {
        interfaceIndex = 0; flags = UInt32(kDNSServiceFlagsReturnIntermediates)
        #if WATCHED_DNS_CHECKS
        validationAudit = nil
        #endif
    }
    #if WATCHED_DNS_CHECKS
    init(negativeAnswers: Bool, audit: @escaping @Sendable (WebDNSValidationAudit) -> Void) {
        interfaceIndex = UInt32(kDNSServiceInterfaceIndexLocalOnly)
        flags = negativeAnswers ? UInt32(kDNSServiceFlagsReturnIntermediates) : 0
        validationAudit = audit
    }
    #endif
    func start(host: String, type: UInt16, queue: DispatchQueue,
               receive: @escaping @Sendable (WebDNSRecord) -> Void) throws -> any WebDNSToken {
        dispatchPrecondition(condition: .onQueue(queue))
        let context = Unmanaged.passRetained(WebDNSCallback(type: type, receive: receive)).toOpaque()
        var reference: DNSServiceRef?
        let callback: DNSServiceQueryRecordReply = { _, flags, _, error, name, type, recordClass, length, bytes, _, context in
            guard let context else { return }
            let callback = Unmanaged<WebDNSCallback>.fromOpaque(context).takeUnretainedValue()
            var hostname: String?
            var data = Data()
            if error == 0 {
                if let name, strnlen(name, 255) < 255 { hostname = String(cString: name) }
                if (type == UInt16(kDNSServiceType_A) && length == 4 || type == UInt16(kDNSServiceType_AAAA) && length == 16), let bytes {
                    data = Data(bytes: bytes, count: Int(length))
                }
            }
            callback.receive(.init(requestedType: callback.requestedType, flags: flags, error: error,
                                   name: hostname, type: type, recordClass: recordClass, bytes: data))
        }
        let error = DNSServiceQueryRecord(&reference, flags, interfaceIndex, host + ".", type,
                                          UInt16(kDNSServiceClass_IN), callback, context)
        guard error == 0, let reference else {
            Unmanaged<WebDNSCallback>.fromOpaque(context).release()
            throw WatchedLinkError.unavailable
        }
        let token = NativeWebDNSToken(reference: reference, context: context, queue: queue)
        #if WATCHED_DNS_CHECKS
        token.validationAudit = validationAudit; token.validationType = type
        validationAudit?(.started(type))
        validationAudit?(.descriptorOpened(type, DNSServiceRefSockFD(reference)))
        #endif
        guard DNSServiceSetDispatchQueue(reference, queue) == 0 else { token.cancel(); throw WatchedLinkError.unavailable }
        return token
    }
}

#if WATCHED_DNS_CHECKS
struct WebDNSValidationStep: Sendable {
    let requestedType: UInt16
    var delay: TimeInterval = 0
    var flags: UInt32 = UInt32(kDNSServiceFlagsAdd)
    var error: Int32 = 0
    var name: String? = nil
    var responseType: UInt16? = nil
    var recordClass: UInt16 = UInt16(kDNSServiceClass_IN)
    var bytes = Data()
    var deliverAfterCancellation = false
}
enum WebDNSValidationAudit: Sendable {
    case started(UInt16), cancelled(UInt16)
    case descriptorOpened(UInt16, Int32), descriptorClosed(UInt16, Int32, Bool, TimeInterval)
}
private final class ScriptedWebDNSToken: WebDNSToken, @unchecked Sendable {
    // State is read/written only on the operation's serial queue.
    var cancelled = false
    let type: UInt16
    let audit: @Sendable (WebDNSValidationAudit) -> Void
    init(type: UInt16, audit: @escaping @Sendable (WebDNSValidationAudit) -> Void) { self.type = type; self.audit = audit }
    func cancel() { guard !cancelled else { return }; cancelled = true; audit(.cancelled(type)) }
}
private struct ScriptedWebDNSBackend: WebDNSBackend {
    let steps: [WebDNSValidationStep]
    let audit: @Sendable (WebDNSValidationAudit) -> Void
    func start(host: String, type: UInt16, queue: DispatchQueue,
               receive: @escaping @Sendable (WebDNSRecord) -> Void) throws -> any WebDNSToken {
        let token = ScriptedWebDNSToken(type: type, audit: audit)
        audit(.started(type))
        for step in steps where step.requestedType == type {
            queue.asyncAfter(deadline: .now() + step.delay) {
                guard !token.cancelled || step.deliverAfterCancellation else { return }
                receive(.init(requestedType: type, flags: step.flags, error: step.error,
                              name: step.name ?? host + ".", type: step.responseType ?? type,
                              recordClass: step.recordClass, bytes: step.bytes))
            }
        }
        return token
    }
}
#endif
