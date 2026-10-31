import Foundation

private struct PolicyDNSFixture: WebHostResolving {
    let values: [String]
    var alias: String? = nil
    func addresses(for host: String) -> [String] { values }
    func resolution(for host: String) -> WebHostResolution { .init(addresses: values, canonicalName: alias) }
}

private actor PolicyChangingDNS: WebHostResolving {
    private var calls = 0
    func addresses(for host: String) -> [String] {
        calls += 1
        return calls == 1 ? ["8.8.8.8"] : ["127.0.0.1"]
    }
}

private actor PolicyHeldDNS: WebHostResolving {
    private var gate: CheckedContinuation<[String], Never>?
    private var entered = false
    func addresses(for host: String) async -> [String] {
        await withCheckedContinuation { gate = $0; entered = true }
    }
    func hasEntered() -> Bool { entered }
    func release() { gate?.resume(returning: ["8.8.8.8"]); gate = nil }
}

/// Isolated production-policy checks. Fixture DNS answers are not socket/TLS proof.
@main @MainActor struct WatchedURLPolicyChecks {
    private static var passed = 0
    private static var failed = 0
    private static func expect(_ condition: Bool, _ label: String) {
        if condition { passed += 1; print("PASS \(label)") }
        else { failed += 1; print("FAIL \(label)") }
    }
    private static func rejects(_ expected: WatchedLinkError, _ label: String, _ operation: () throws -> Void) {
        do { try operation(); expect(false, label) }
        catch let error as WatchedLinkError { expect(error == expected, label) }
        catch { expect(false, label + " returned another error type") }
    }
    private static func rejectsAsync(_ expected: WatchedLinkError, _ label: String, _ operation: () async throws -> Void) async {
        do { try await operation(); expect(false, label) }
        catch let error as WatchedLinkError { expect(error == expected, label) }
        catch { expect(false, label + " returned another error type") }
    }

    static func main() async throws {
        let publicURL = URL(string: "https://example.com/updates")!
        expect(try WebURLPolicy.validate("https://EXAMPLE.COM.:443/news#part").absoluteString == "https://example.com/news", "canonical HTTPS host, default port and fragment")
        expect(try WebURLPolicy.validate("https://xn--bcher-kva.de/page").host == "xn--bcher-kva.de", "explicit ASCII IDNA spelling")
        rejects(.blockedHost, "literal public IPv4 URL does not supply a DNS TLS identity") { _ = try WebURLPolicy.validate("https://8.8.8.8/") }
        rejects(.blockedHost, "literal public IPv6 URL does not supply a DNS TLS identity") { _ = try WebURLPolicy.validate("https://[2001:4860:4860::8888]/") }
        for value in ["http://example.com/", "file:///tmp/page", "not a url"] {
            rejects(.unsupportedScheme, "unsupported scheme is typed") { _ = try WebURLPolicy.validate(value) }
        }
        for value in ["https://user:secret@example.com/", "https://example.com:8443/", "https://example.com:/", "https://%31%32%37.0.0.1/", "https://%65xample.com/", "https://example.com\\@127.0.0.1/", "https://example.com/\npath", "https://.example.com/", "https://example..com/", "https://example.com../", "https://-bad.example.com/", "https://bad-.example.com/", "https://bad_name.example.com/", "https://printer/", "https://2130706433/", "https://0x7f000001/", "https://" + String(repeating: "a", count: 64) + ".com/"] {
            rejects(.invalidURL, "malformed/ambiguous authority is typed") { _ = try WebURLPolicy.validate(value) }
        }
        for host in ["localhost", "sub.localhost", "printer.local", "example.internal", "router.home.arpa", "home.arpa", "host.localdomain", "service.onion", "host.invalid", "host.test", "host.example", "127.1", "0177.0.0.1", "0x7f.0.0.1", "example.123"] {
            rejects(.blockedHost, "unsafe alias/numeric host \(host)") { _ = try WebURLPolicy.validate("https://\(host)/") }
        }
        for address in ["0.0.0.0", "0.1.2.3", "10.0.0.1", "100.64.0.1", "100.127.255.255", "127.0.0.1", "169.254.169.254", "172.16.0.1", "172.31.255.255", "192.0.0.1", "192.0.2.1", "192.88.99.1", "192.168.0.1", "198.18.0.1", "198.19.255.255", "198.51.100.1", "203.0.113.1", "224.0.0.1", "239.255.255.255", "240.0.0.1", "255.255.255.255"] {
            expect(WebURLPolicy.isBlockedAddress(address), "special IPv4 \(address)")
            rejects(.blockedHost, "IPv4 URL rejects before DNS \(address)") { _ = try WebURLPolicy.validate("https://\(address)/") }
        }
        for address in ["1.1.1.1", "8.8.8.8", "93.184.216.34", "100.63.255.255", "100.128.0.1", "172.15.255.255", "172.32.0.1", "198.17.255.255", "198.20.0.1", "223.255.255.254"] {
            expect(!WebURLPolicy.isBlockedAddress(address), "public IPv4 policy boundary \(address)")
        }
        for address in ["::", "::1", "::8.8.8.8", "fc00::1", "fdff::1", "fe80::1", "febf::1", "fec0::1", "ff02::1", "100::1", "100:0:0:1::1", "64:ff9b::a00:1", "64:ff9b:1::a00:1", "2001::1", "2001:2::1", "2001:20::1", "2001:db8::1", "2001:1000::1", "2001:4e00::1", "2002:7f00:1::1", "2003:4000::1", "2612::1", "2622::1", "2d00::1", "3000::1", "3ffe::1", "3fff::1", "5f00::1", "4000::1", "::ffff:127.0.0.1", "::ffff:192.168.1.1", "::ffff:198.51.100.1", "::ffff:0a00:0001"] {
            expect(WebURLPolicy.isBlockedAddress(address), "special/reserved IPv6 \(address)")
            rejects(.blockedHost, "IPv6 URL rejects before DNS \(address)") { _ = try WebURLPolicy.validate("https://[\(address)]/") }
        }
        for address in ["2001:4860:4860::8888", "2001:200::1", "2003:3fff::1", "2406:da00::1", "2410::1", "2606:4700:4700::1111", "2610::1", "2620:fe::fe", "2630::1", "2800::1", "2a10::1", "2c00::1", "::ffff:8.8.8.8"] {
            expect(!WebURLPolicy.isBlockedAddress(address), "allocated public IPv6 policy \(address)")
        }
        for value in ["garbage", "127.1", "2130706433", "[::1]", "8.8.8.8.", "fe80::1%en0", "8.8.8.8\n"] {
            expect(WebURLPolicy.isBlockedAddress(value), "ambiguous resolver address fails closed")
        }
        let approved = try await WebURLPolicy.approvedAddresses(for: publicURL, resolver: PolicyDNSFixture(values: ["8.8.8.8", "2001:4860:4860:0:0:0:0:8888", "8.8.8.8"]))
        expect(approved.count == 2 && approved[0].numericHost == "8.8.8.8" && approved[0].family == .ipv4 && approved[1].numericHost == "2001:4860:4860::8888" && approved[1].family == .ipv6, "approved values retain exact canonical numeric endpoints and families")
        for values in [[], ["8.8.8.8", "127.0.0.1"], ["8.8.8.8", "fd00::1"], ["2001:4860::1", "100::1"], ["8.8.8.8", "not-an-address"], ["8.8.8.8", "[2001:4860::1]"], Array(repeating: "8.8.8.8", count: 65)] {
            await rejectsAsync(.blockedHost, "empty/mixed/ambiguous DNS answer is typed") { _ = try await WebURLPolicy.approvedAddresses(for: publicURL, resolver: PolicyDNSFixture(values: values)) }
        }
        for alias in ["router.home.arpa", "host.local", "127.0.0.1"] {
            await rejectsAsync(.blockedHost, "available unsafe canonical alias is rejected") { _ = try await WebURLPolicy.approvedAddresses(for: publicURL, resolver: PolicyDNSFixture(values: ["8.8.8.8"], alias: alias)) }
        }
        await rejectsAsync(.invalidURL, "malformed canonical alias is rejected") { _ = try await WebURLPolicy.approvedAddresses(for: publicURL, resolver: PolicyDNSFixture(values: ["8.8.8.8"], alias: "bad..example.com")) }
        await rejectsAsync(.blockedHost, "different public canonical alias denied because intermediate CNAME hops are unavailable") { _ = try await WebURLPolicy.approvedAddresses(for: publicURL, resolver: PolicyDNSFixture(values: ["8.8.8.8"], alias: "CDN.EXAMPLE.COM.")) }
        expect(try await WebURLPolicy.approvedAddresses(for: publicURL, resolver: PolicyDNSFixture(values: ["8.8.8.8"], alias: "EXAMPLE.COM.")).count == 1, "matching available canonical name permits address policy, not socket proof")
        let changing = PolicyChangingDNS()
        let earlier = try await WebURLPolicy.approvedAddresses(for: publicURL, resolver: changing)
        await rejectsAsync(.blockedHost, "changed DNS is revalidated without mutating earlier choices") { _ = try await WebURLPolicy.approvedAddresses(for: publicURL, resolver: changing) }
        expect(earlier.map(\.numericHost) == ["8.8.8.8"], "approved choices are immutable; no socket pinning claim")
        let held = PolicyHeldDNS()
        let cancelled = Task { try await WebURLPolicy.approvedAddresses(for: publicURL, resolver: held) }
        for _ in 0..<10_000 { if await held.hasEntered() { break }; await Task.yield() }
        expect(await held.hasEntered(), "held resolver reached its explicit gate")
        cancelled.cancel(); await held.release()
        do { _ = try await cancelled.value; expect(false, "cancelled resolution cannot return approved choices") }
        catch is CancellationError { expect(true, "cancelled resolution cannot return approved choices") }
        catch { expect(false, "cancelled resolution returned wrong error type") }
        let preCancelled = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await WebURLPolicy.approvedAddresses(for: publicURL, resolver: PolicyDNSFixture(values: ["8.8.8.8"]))
        }
        preCancelled.cancel()
        do { _ = try await preCancelled.value; expect(false, "pre-cancelled resolution") }
        catch is CancellationError { expect(true, "pre-cancelled resolution") }
        catch { expect(false, "pre-cancelled resolution returned wrong error type") }
        try await savedLegacyInspection()
        print("Watched URL policy checks: \(passed) passed, \(failed) failed. Isolated policy/storage fixtures only; no DNS, socket or TLS acceptance.")
        if failed != 0 { exit(1) }
    }

    private static func savedLegacyInspection() async throws {
        struct LegacyState: Encodable { let schemaVersion = 1; let links: [WatchedLinkRecord] }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SuzmeWatchedPolicy-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (index, value) in ["https://2130706433/", "https://[3fff::1]/", "https://router.home.arpa/", "https://example.com:8443/"].enumerated() {
            let url = URL(string: value)!
            expect(try WebURLPolicy.validateLegacyStoredURL(url) == url, "legacy URL remains readable without granting new fetch eligibility")
            expect((try? WebURLPolicy.validate(url)) == nil, "legacy URL cannot become a newly approved request")
            let change = WatchedLinkChange(id: "saved", kind: .general, title: "Saved update", detail: "Earlier selected page detail.", effectiveAt: nil, effectiveUntil: nil, location: nil, observedAt: .now)
            let record = WatchedLinkRecord(id: UUID(), name: "Saved page", canonicalURL: url, enabled: true, state: .changed, etag: nil, lastModifiedHeader: nil, fingerprint: "saved", lastAttempt: nil, lastSuccess: .now, lastMeaningfulChange: .now, consecutiveFailures: 0, nextEligibleRefresh: nil, pageTitle: "Saved title", changes: [change])
            let file = root.appendingPathComponent("legacy-\(index).json")
            try JSONEncoder().encode(LegacyState(links: [record])).write(to: file, options: .atomic)
            let store = WatchedLinkStore(fileURL: file)
            let records = try await store.records()
            expect(records.count == 1 && records[0].canonicalURL == url && records[0].changes == [change], "actual legacy store retains saved URL and history")
            try await store.remove(record.id)
            expect(try await WatchedLinkStore(fileURL: file).records().isEmpty, "actual legacy store permits individual deletion without fetching")
        }
        for value in ["http://example.com/", "https://user:secret@example.com/", "https://localhost/", "https://example.com/?api_key=secret"] {
            expect((try? WebURLPolicy.validateLegacyStoredURL(URL(string: value)!)) == nil, "frozen legacy reader retains original scheme/credentials/host/privacy restrictions")
        }
    }
}
