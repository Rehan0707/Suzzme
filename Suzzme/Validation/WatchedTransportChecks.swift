import Foundation
import Darwin

private struct DNSFixture: WebHostResolving {
    let values: [String]
    func addresses(for host: String) -> [String] { values }
}

private struct FailedDNS: WebHostResolving {
    let error: WatchedLinkError
    func addresses(for host: String) throws -> [String] { throw error }
}

private struct FailedHTTP: WatchedHTTPTransport {
    let error: WatchedLinkError
    var isAvailable: Bool { true }
    func get(_ request: WatchedPinnedRequest) throws -> WatchedHTTPResponse { throw error }
}

private actor SequencedDNS: WebHostResolving {
    private let answers: [[String]]
    private var hosts: [String] = []
    init(_ answers: [[String]]) { self.answers = answers }
    func addresses(for host: String) throws -> [String] {
        hosts.append(host)
        guard hosts.count <= answers.count else { throw WatchedLinkError.unavailable }
        return answers[hosts.count - 1]
    }
    func requestedHosts() -> [String] { hosts }
}

/// These actors record Core requests. They do not create or certify a socket.
private actor HTTPFixture: WatchedHTTPTransport {
    nonisolated let isAvailable = true
    private let responses: [WatchedHTTPResponse]
    private var requests: [WatchedPinnedRequest] = []
    init(_ responses: [WatchedHTTPResponse]) { self.responses = responses }
    func get(_ request: WatchedPinnedRequest) throws -> WatchedHTTPResponse {
        requests.append(request)
        guard requests.count <= responses.count else { throw WatchedLinkError.unavailable }
        return responses[requests.count - 1]
    }
    func recordedRequests() -> [WatchedPinnedRequest] { requests }
}

/// Records timeout forwarding only. It deliberately does not implement a DNS
/// deadline; delayed-answer rejection belongs to the Core deadline regression.
private actor BudgetDNS: WebHostResolving {
    struct Call: Sendable { let host: String; let timeout: TimeInterval }
    private let delay: Duration
    private var calls: [Call] = []
    init(delay: Duration = .zero) { self.delay = delay }
    func addresses(for host: String) throws -> [String] { throw WatchedLinkError.unavailable }
    func resolution(for host: String) throws -> WebHostResolution { throw WatchedLinkError.unavailable }
    func resolution(for host: String, timeout: TimeInterval) async throws -> WebHostResolution {
        calls.append(.init(host: host, timeout: timeout))
        if delay > .zero { try await Task.sleep(for: delay) }
        return .init(addresses: ["8.8.8.8"])
    }
    func recordedCalls() -> [Call] { calls }
}

private actor BudgetHTTP: WatchedHTTPTransport {
    nonisolated let isAvailable = true
    private let responses: [WatchedHTTPResponse]
    private let delay: Duration
    private var requests: [WatchedPinnedRequest] = []
    init(_ responses: [WatchedHTTPResponse], delay: Duration) {
        self.responses = responses; self.delay = delay
    }
    func get(_ request: WatchedPinnedRequest) async throws -> WatchedHTTPResponse {
        requests.append(request)
        guard requests.count <= responses.count else { throw WatchedLinkError.unavailable }
        if delay > .zero { try await Task.sleep(for: delay) }
        return responses[requests.count - 1]
    }
    func recordedRequests() -> [WatchedPinnedRequest] { requests }
}

private actor HeldDNS: WebHostResolving {
    private var continuation: CheckedContinuation<[String], Never>?
    private var entered = false
    private var released = false
    func addresses(for host: String) async -> [String] {
        entered = true
        if released { return ["8.8.8.8"] }
        return await withCheckedContinuation { continuation = $0 }
    }
    func hasEntered() -> Bool { entered }
    func release() {
        released = true
        continuation?.resume(returning: ["8.8.8.8"])
        continuation = nil
    }
}

private actor HeldHTTP: WatchedHTTPTransport {
    nonisolated let isAvailable = true
    private var continuation: CheckedContinuation<WatchedHTTPResponse, Never>?
    private var entered = false
    private var released = false
    func get(_ request: WatchedPinnedRequest) async -> WatchedHTTPResponse {
        entered = true
        if released { return Self.response }
        return await withCheckedContinuation { continuation = $0 }
    }
    func hasEntered() -> Bool { entered }
    func release() {
        released = true
        continuation?.resume(returning: Self.response)
        continuation = nil
    }
    private static var response: WatchedHTTPResponse {
        .init(statusCode: 200, headers: ["content-type": ["text/plain"]], data: Data("Held fixture response".utf8))
    }
}

/// Offline Core orchestration and persistence evidence only. Actual numeric
/// socket selection and original-host TLS validation are tested separately by
/// SuzzmeWatchedTransport's isolated production-transport connection suite.
@main @MainActor struct WatchedTransportChecks {
    private static var passed = 0
    private static var failed = 0
    private static let publicURL = URL(string: "https://example.com/updates")!
    private static let pageBytes = Data("Notice: the timetable has a revised morning session.".utf8)

    private static func expect(_ condition: Bool, _ label: String) {
        if condition { passed += 1; print("PASS \(label)") }
        else { failed += 1; print("FAIL \(label)") }
    }

    private static func rejects(_ expected: WatchedLinkError, _ label: String, _ operation: () throws -> Void) {
        do { try operation(); expect(false, label) }
        catch let error as WatchedLinkError { expect(error == expected, label) }
        catch { expect(false, "\(label): unexpected error type") }
    }

    private static func rejectsAsync(_ expected: WatchedLinkError, _ label: String, _ operation: () async throws -> Void) async {
        do { try await operation(); expect(false, label) }
        catch let error as WatchedLinkError { expect(error == expected, label) }
        catch { expect(false, "\(label): unexpected error type") }
    }

    private static func response(_ status: Int = 200, headers: [String: [String]] = ["content-type": ["text/plain"]], data: Data = pageBytes) -> WatchedHTTPResponse {
        .init(statusCode: status, headers: headers, data: data)
    }

    private static func request(_ url: URL = publicURL, etag: String? = nil, modified: String? = nil) -> WatchedLinkFetchRequest {
        .init(url: url, etag: etag, lastModified: modified)
    }

    static func main() async throws {
        try await failClosedDefault()
        try await numericRequestOrchestration()
        try await redirectOrchestration()
        try await responseBoundaries()
        try await requestBudgets()
        await cancellationBoundaries()
        try await consentAndOwnership()
        print("Watched transport checks: \(passed) passed, \(failed) failed. Offline Core orchestration/storage fixtures; no socket or TLS acceptance claim.")
        if failed != 0 { exit(1) }
    }

    private static func failClosedDefault() async throws {
        let fetcher = BoundedWatchedLinkFetcher()
        expect(!fetcher.isAvailable, "standalone validation does not enable production transport by importing fixtures")
        await rejectsAsync(.transportRestricted, "unconfigured default fetcher rejects before DNS or HTTP") {
            _ = try await fetcher.fetch(request())
        }
        expect(try WebURLPolicy.validate("https://EXAMPLE.COM./news#fragment").absoluteString == "https://example.com/news", "canonical normalization remains deterministic")
        await rejectsAsync(.invalidURL, "fetch rejects a noncanonical original request") {
            _ = try await fetcher.fetch(request(URL(string: "https://EXAMPLE.COM./news#fragment")!))
        }
        rejects(.responseTooLarge, "local extraction retains the byte cap") {
            _ = try WebContentExtractor.extract(data: Data(repeating: 65, count: WatchedLinkLimits.responseBytes + 1), mimeType: "text/html", now: .now)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SuzmeWatchedUnavailable-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = WatchedWebInformationSource(store: .init(fileURL: directory.appendingPathComponent("links.json")))
        expect(await source.authorization() == .unsupported, "source health does not claim readiness while production transport is unavailable")
        let event = InformationNormalizer.normalize(.init(externalID: "saved", title: "Saved update", modifiedAt: .now), source: .watchedWeb, now: .now)!
        expect(!(await source.permits(event, now: .now)), "unavailable transport does not restore derived-summary authority")
    }

    private static func numericRequestOrchestration() async throws {
        let dns = SequencedDNS([["2001:4860:4860::8888", "8.8.8.8", "1.1.1.1"]])
        let http = HTTPFixture([response()])
        let fetcher = BoundedWatchedLinkFetcher(resolver: dns, transport: http)
        let value = try await fetcher.fetch(request(etag: "\"saved-v1\"", modified: "Tue, 20 Oct 2026 10:00:00 GMT"))
        let calls = await http.recordedRequests()
        expect(value.finalURL == publicURL && value.data == pageBytes, "fixture success preserves final URL and bounded bytes")
        expect(calls.count == 1 && calls[0].address.numericHost == "8.8.8.8" && calls[0].address.family == .ipv4, "Core hands an exact approved immutable IPv4 choice to the transport seam")
        expect(calls.count == 1 && calls[0].url.host == "example.com" && calls[0].url == publicURL, "numeric destination does not replace the original URL hostname in Core")
        expect(calls.count == 1 && calls[0].etag == "\"saved-v1\"" && calls[0].lastModified == "Tue, 20 Oct 2026 10:00:00 GMT", "conditional values stay associated with the original resource")
        expect(calls.count == 1 && calls[0].timeout > 0 && calls[0].timeout <= WatchedLinkLimits.timeout, "Core hands down only the remaining bounded request time")
        expect(await dns.requestedHosts() == ["example.com"], "Core performs one resolver lookup for a nonredirected request")

        let ipv6 = HTTPFixture([response()])
        _ = try await BoundedWatchedLinkFetcher(resolver: DNSFixture(values: ["2001:4860:4860:0:0:0:0:8888"]), transport: ipv6).fetch(request())
        let ipv6Calls = await ipv6.recordedRequests()
        expect(ipv6Calls.count == 1 && ipv6Calls[0].address.numericHost == "2001:4860:4860::8888" && ipv6Calls[0].address.family == .ipv6, "IPv6-only answer supplies its exact canonical numeric endpoint")

        for values in [["8.8.8.8", "127.0.0.1"], ["8.8.8.8", "fd00::1"], ["2001:4860:4860::8888", "::ffff:169.254.1.1"], ["8.8.8.8", "ambiguous"]] {
            let deniedHTTP = HTTPFixture([response()])
            await rejectsAsync(.blockedHost, "mixed or ambiguous DNS answer is rejected with a typed policy error") {
                _ = try await BoundedWatchedLinkFetcher(resolver: DNSFixture(values: values), transport: deniedHTTP).fetch(request())
            }
            expect(await deniedHTTP.recordedRequests().isEmpty, "no transport call receives the safe subset of a mixed DNS answer")
        }
    }

    private static func redirectOrchestration() async throws {
        for destination in ["/next", "https://other.example.com/next"] {
            let dns = SequencedDNS([["8.8.8.8"], ["1.1.1.1"]])
            let http = HTTPFixture([response(302, headers: ["location": [destination]], data: Data()), response()])
            let value = try await BoundedWatchedLinkFetcher(resolver: dns, transport: http).fetch(request(etag: "\"private-cache-key\"", modified: "Tue, 20 Oct 2026 10:00:00 GMT"))
            let calls = await http.recordedRequests()
            expect(calls.count == 2 && calls[0].address.numericHost == "8.8.8.8" && calls[1].address.numericHost == "1.1.1.1", "each same/cross-host redirect receives a newly approved numeric destination")
            expect(calls.count == 2 && calls[0].etag != nil && calls[0].lastModified != nil && calls[1].etag == nil && calls[1].lastModified == nil, "same/cross-host redirects clear all conditional values")
            expect(calls.count == 2 && calls[0].address.numericHost == "8.8.8.8" && value.finalURL == calls[1].url, "later DNS answers cannot mutate an earlier captured numeric request")
            expect(await dns.requestedHosts() == ["example.com", destination.hasPrefix("/") ? "example.com" : "other.example.com"], "Core resolves each redirect's own hostname")
        }

        let changingDNS = SequencedDNS([["8.8.8.8"], ["127.0.0.1"]])
        let changingHTTP = HTTPFixture([response(302, headers: ["location": ["/later"]], data: Data()), response()])
        await rejectsAsync(.blockedHost, "DNS changed to private between redirect hops fails closed") {
            _ = try await BoundedWatchedLinkFetcher(resolver: changingDNS, transport: changingHTTP).fetch(request())
        }
        expect(await changingHTTP.recordedRequests().count == 1, "changed private DNS cannot reach a second transport call")

        for (destination, error) in [
            ("https://127.0.0.1/", WatchedLinkError.blockedHost),
            ("https://169.254.169.254/latest/meta-data", .blockedHost),
            ("https://[::ffff:127.0.0.1]/", .blockedHost),
            ("https://router.home.arpa/", .blockedHost),
            ("http://example.com/next", .unsupportedScheme),
            ("file:///private/etc/hosts", .unsupportedScheme),
            ("https://user:secret@example.com/", .invalidURL),
            ("https://example.com:8443/", .invalidURL),
            ("https://%31%32%37.0.0.1/", .invalidURL),
            ("https://example.com\\@127.0.0.1/", .invalidURL),
            ("/next\r\nX-Test: injected", .invalidURL),
            ("", .invalidURL)
        ] {
            let dns = SequencedDNS([["8.8.8.8"]])
            let http = HTTPFixture([response(302, headers: ["location": [destination]], data: Data())])
            await rejectsAsync(error, "prohibited or malformed redirect is typed: \(destination.debugDescription)") {
                _ = try await BoundedWatchedLinkFetcher(resolver: dns, transport: http).fetch(request())
            }
            let redirectCalls = await http.recordedRequests()
            let redirectHosts = await dns.requestedHosts()
            expect(redirectCalls.count == 1 && redirectHosts.count == 1, "prohibited redirect cannot start another lookup or transport call")
        }

        for headers: [String: [String]] in [[:], ["location": ["/one", "/two"]]] {
            let expected: WatchedLinkError = headers.isEmpty ? .invalidURL : .malformedContent
            await rejectsAsync(expected, "missing or duplicate Location is never guessed") {
                _ = try await BoundedWatchedLinkFetcher(resolver: DNSFixture(values: ["8.8.8.8"]), transport: HTTPFixture([response(302, headers: headers, data: Data())])).fetch(request())
            }
        }
        let loopHTTP = HTTPFixture([response(302, headers: ["location": [publicURL.absoluteString]], data: Data())])
        await rejectsAsync(.redirectLimit, "redirect to a visited canonical URL stops as a loop") {
            _ = try await BoundedWatchedLinkFetcher(resolver: DNSFixture(values: ["8.8.8.8"]), transport: loopHTTP).fetch(request())
        }
        expect(await loopHTTP.recordedRequests().count == 1, "redirect loop cannot start a repeated HTTP call")
        let many = (0...WatchedLinkLimits.redirects).map { response(302, headers: ["location": ["/hop-\($0)"]], data: Data()) }
        let manyHTTP = HTTPFixture(many)
        await rejectsAsync(.redirectLimit, "bounded manual redirect count rejects the next destination") {
            _ = try await BoundedWatchedLinkFetcher(resolver: DNSFixture(values: ["8.8.8.8"]), transport: manyHTTP).fetch(request())
        }
        expect(await manyHTTP.recordedRequests().count == WatchedLinkLimits.redirects + 1, "redirect limit bounds Core HTTP calls exactly")
    }

    private static func responseBoundaries() async throws {
        let unusedHTTP = HTTPFixture([response()])
        await rejectsAsync(.timeout, "Core propagates a resolver timeout without starting HTTP") {
            _ = try await BoundedWatchedLinkFetcher(resolver: FailedDNS(error: .timeout), transport: unusedHTTP).fetch(request())
        }
        expect(await unusedHTTP.recordedRequests().isEmpty, "timed-out resolver cannot supply a transport destination")
        await rejectsAsync(.timeout, "Core preserves the transport's typed timeout") {
            _ = try await BoundedWatchedLinkFetcher(resolver: DNSFixture(values: ["8.8.8.8"]), transport: FailedHTTP(error: .timeout)).fetch(request())
        }
        for (status, error) in [(404, WatchedLinkError.notFound), (500, .serverError), (401, .unavailable), (206, .unavailable)] {
            await rejectsAsync(error, "HTTP \(status) keeps its typed failure") {
                _ = try await BoundedWatchedLinkFetcher(resolver: DNSFixture(values: ["8.8.8.8"]), transport: HTTPFixture([response(status)])).fetch(request())
            }
        }
        for headers: [String: [String]] in [[:], ["content-type": ["application/pdf"]], ["content-type": ["application/json"]], ["content-type": ["image/png"]]] {
            await rejectsAsync(.unsupportedContent, "absent or unsupported MIME cannot become extracted page content") {
                _ = try await BoundedWatchedLinkFetcher(resolver: DNSFixture(values: ["8.8.8.8"]), transport: HTTPFixture([response(headers: headers)])).fetch(request())
            }
        }
        await rejectsAsync(.malformedContent, "duplicate Content-Type is not resolved by first/last wins") {
            _ = try await BoundedWatchedLinkFetcher(resolver: DNSFixture(values: ["8.8.8.8"]), transport: HTTPFixture([response(headers: ["content-type": ["text/plain", "text/html"]])])).fetch(request())
        }
        for mime in ["text/html; charset=utf-8", "TEXT/PLAIN", "application/xhtml+xml"] {
            let value = try await BoundedWatchedLinkFetcher(resolver: DNSFixture(values: ["8.8.8.8"]), transport: HTTPFixture([response(headers: ["content-type": [mime]])])).fetch(request())
            expect(value.mimeType == mime, "supported MIME passes to bounded local extraction")
        }
        await rejectsAsync(.responseTooLarge, "Core rejects oversized response bytes even from an injected seam") {
            _ = try await BoundedWatchedLinkFetcher(resolver: DNSFixture(values: ["8.8.8.8"]), transport: HTTPFixture([response(data: Data(repeating: 65, count: WatchedLinkLimits.responseBytes + 1))])).fetch(request())
        }
        await rejectsAsync(.malformedContent, "unsolicited 304 cannot validate previously saved content") {
            _ = try await BoundedWatchedLinkFetcher(resolver: DNSFixture(values: ["8.8.8.8"]), transport: HTTPFixture([response(304, headers: [:], data: Data())])).fetch(request())
        }
        await rejectsAsync(.malformedContent, "304 with a body is malformed even when a validator was sent") {
            _ = try await BoundedWatchedLinkFetcher(resolver: DNSFixture(values: ["8.8.8.8"]), transport: HTTPFixture([response(304, headers: [:])])).fetch(request(etag: "\"v1\""))
        }
        let validated = try await BoundedWatchedLinkFetcher(resolver: DNSFixture(values: ["8.8.8.8"]), transport: HTTPFixture([response(304, headers: [:], data: Data())])).fetch(request(etag: "\"v1\""))
        expect(validated.statusCode == 304 && validated.data.isEmpty, "empty conditional 304 preserves its explicit validation status")
        for conditional in ["\"v1\"\r\nAuthorization: injected", "unsafe\u{0000}value", String(repeating: "x", count: 513)] {
            let http = HTTPFixture([response()])
            await rejectsAsync(.invalidURL, "unsafe request ETag is rejected before HTTP") {
                _ = try await BoundedWatchedLinkFetcher(resolver: DNSFixture(values: ["8.8.8.8"]), transport: http).fetch(request(etag: conditional))
            }
            expect(await http.recordedRequests().isEmpty, "invalid request validator is never handed to transport")
        }
        await rejectsAsync(.invalidURL, "CRLF request Last-Modified is rejected") {
            _ = try await BoundedWatchedLinkFetcher(resolver: DNSFixture(values: ["8.8.8.8"]), transport: HTTPFixture([response()])).fetch(request(modified: "date\r\nCookie: injected"))
        }
        for field in ["etag", "last-modified"] {
            await rejectsAsync(.invalidURL, "unsafe response \(field) cannot become a future request header") {
                _ = try await BoundedWatchedLinkFetcher(resolver: DNSFixture(values: ["8.8.8.8"]), transport: HTTPFixture([response(headers: ["content-type": ["text/plain"], field: ["value\r\nX-Test: injected"]])])).fetch(request())
            }
        }
    }

    private static func requestBudgets() async throws {
        let directDNS = BudgetDNS()
        _ = try await WebURLPolicy.approvedAddresses(for: publicURL, resolver: directDNS, timeout: 0.25)
        let directCalls = await directDNS.recordedCalls()
        expect(directCalls.count == 1 && directCalls[0].host == "example.com" && directCalls[0].timeout == 0.25, "policy forwards an explicit bounded timeout to the budgeted resolver seam")

        let cappedDNS = BudgetDNS()
        let cappedHTTP = HTTPFixture([response()])
        _ = try await BoundedWatchedLinkFetcher(resolver: cappedDNS, transport: cappedHTTP).fetch(request())
        let cappedCalls = await cappedDNS.recordedCalls()
        expect(cappedCalls.count == 1 && cappedCalls[0].timeout > 0 && cappedCalls[0].timeout <= WatchedLinkLimits.dnsTimeout, "normal Core request caps its DNS budget at the independent DNS limit")

        // The injected timeout only shortens the fixed production maximum. Small
        // fixture sleeps exercise the same deadline calculations without a 15 s
        // test or real resolver, connection, or remote website.
        let dns = BudgetDNS(delay: .milliseconds(20))
        let http = BudgetHTTP([response(302, headers: ["location": ["/budget-next"]], data: Data()), response()], delay: .milliseconds(20))
        _ = try await BoundedWatchedLinkFetcher(resolver: dns, transport: http, totalTimeout: 2).fetch(request())
        let dnsCalls = await dns.recordedCalls()
        let httpCalls = await http.recordedRequests()
        expect(dnsCalls.count == 2 && dnsCalls[0].timeout <= 2 && dnsCalls[1].timeout > 0 && dnsCalls[1].timeout < dnsCalls[0].timeout, "redirect DNS receives a shrinking overall budget after delayed DNS and HTTP")
        expect(httpCalls.count == 2 && httpCalls[1].timeout > 0 && httpCalls[1].timeout < httpCalls[0].timeout && httpCalls[0].timeout < 2, "transport receives only the remaining overall budget at each delayed hop")
        expect(dnsCalls.count == 2 && httpCalls.count == 2 && httpCalls[0].timeout < dnsCalls[0].timeout && httpCalls[1].timeout < dnsCalls[1].timeout, "DNS work consumes the shared deadline before its corresponding HTTP call")

        let expiredDNS = BudgetDNS(delay: .milliseconds(300))
        let unusedHTTP = HTTPFixture([response()])
        await rejectsAsync(.timeout, "DNS result arriving after the overall deadline is rejected before transport") {
            _ = try await BoundedWatchedLinkFetcher(resolver: expiredDNS, transport: unusedHTTP, totalTimeout: 0.2).fetch(request())
        }
        let expiredDNSCalls = await expiredDNS.recordedCalls()
        expect(expiredDNSCalls.count == 1 && expiredDNSCalls[0].timeout > 0 && expiredDNSCalls[0].timeout <= 0.2, "shortened request passes only its own remaining DNS allowance")
        expect(await unusedHTTP.recordedRequests().isEmpty, "depleted DNS deadline cannot initiate any HTTP call")

        let initialDNS = BudgetDNS()
        let expiredHTTP = BudgetHTTP([response(302, headers: ["location": ["/too-late"]], data: Data()), response()], delay: .milliseconds(300))
        await rejectsAsync(.timeout, "late redirect response cannot restart the overall deadline") {
            _ = try await BoundedWatchedLinkFetcher(resolver: initialDNS, transport: expiredHTTP, totalTimeout: 0.2).fetch(request())
        }
        let lateDNSCalls = await initialDNS.recordedCalls()
        let lateHTTPCalls = await expiredHTTP.recordedRequests()
        expect(lateDNSCalls.count == 1 && lateHTTPCalls.count == 1, "depleted HTTP deadline prevents another redirect lookup and connection attempt")
    }

    private static func cancellationBoundaries() async {
        let beforeDNS = SequencedDNS([["8.8.8.8"]])
        let beforeHTTP = HTTPFixture([response()])
        let before = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await BoundedWatchedLinkFetcher(resolver: beforeDNS, transport: beforeHTTP).fetch(request())
        }
        before.cancel()
        do { _ = try await before.value; expect(false, "pre-cancelled fetch") }
        catch is CancellationError { expect(true, "pre-cancelled fetch returns CancellationError") }
        catch { expect(false, "pre-cancelled fetch has unexpected error type") }
        let earlyHosts = await beforeDNS.requestedHosts()
        let earlyCalls = await beforeHTTP.recordedRequests()
        expect(earlyHosts.isEmpty && earlyCalls.isEmpty, "pre-cancelled Core work invokes neither seam")

        let heldDNS = HeldDNS()
        let unusedHTTP = HTTPFixture([response()])
        let dnsTask = Task { try await BoundedWatchedLinkFetcher(resolver: heldDNS, transport: unusedHTTP).fetch(request()) }
        for _ in 0..<10_000 { if await heldDNS.hasEntered() { break }; await Task.yield() }
        expect(await heldDNS.hasEntered(), "resolver cancellation fixture reached its explicit gate")
        dnsTask.cancel(); await heldDNS.release()
        do { _ = try await dnsTask.value; expect(false, "cancelled DNS result") }
        catch is CancellationError { expect(true, "Core rejects a delayed resolver result after cancellation") }
        catch { expect(false, "delayed cancelled DNS returned another error type") }
        expect(await unusedHTTP.recordedRequests().isEmpty, "delayed cancelled resolution cannot start transport")

        let heldHTTP = HeldHTTP()
        let httpTask = Task { try await BoundedWatchedLinkFetcher(resolver: DNSFixture(values: ["8.8.8.8"]), transport: heldHTTP).fetch(request()) }
        for _ in 0..<10_000 { if await heldHTTP.hasEntered() { break }; await Task.yield() }
        expect(await heldHTTP.hasEntered(), "HTTP cancellation fixture reached its explicit gate")
        httpTask.cancel(); await heldHTTP.release()
        do { _ = try await httpTask.value; expect(false, "cancelled HTTP result") }
        catch is CancellationError { expect(true, "Core rejects delayed HTTP bytes after cancellation") }
        catch { expect(false, "delayed cancelled HTTP returned another error type") }
        // These late-callback checks deliberately do not claim that mocks close
        // sockets; prompt cancellation is proven in the real transport suite.
    }

    private static func consentAndOwnership() async throws {
        struct LegacyState: Encodable { let schemaVersion = 1; let links: [WatchedLinkRecord] }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SuzmeWatchedOwnership-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_792_598_400)
        let change = WatchedLinkChange(id: "saved", kind: .general, title: "Saved notice", detail: "Earlier user-selected page content.", effectiveAt: nil, effectiveUntil: nil, location: nil, observedAt: now)
        let legacy = WatchedLinkRecord(id: UUID(), name: "Legacy page", canonicalURL: publicURL, enabled: true, state: .changed, etag: "\"old\"", lastModifiedHeader: "Tue, 20 Oct 2026 10:00:00 GMT", fingerprint: "saved", lastAttempt: now, lastSuccess: now, lastMeaningfulChange: now, consecutiveFailures: 0, nextEligibleRefresh: now.addingTimeInterval(3_600), pageTitle: "Saved title", changes: [change])
        let file = root.appendingPathComponent("legacy.json")
        try JSONEncoder().encode(LegacyState(links: [legacy])).write(to: file, options: .atomic)
        let store = WatchedLinkStore(fileURL: file)
        let inspected = try await store.records(now: now)
        expect(inspected.count == 1 && inspected[0].changes == [change] && inspected[0].canonicalURL == publicURL && inspected[0].pageTitle == "Saved title", "legacy optional-field migration preserves readable URL, title and history")
        expect(inspected.count == 1 && inspected[0].enabled && inspected[0].transportConsentRevision == nil && !inspected[0].permitsFetching, "legacy saved enabled flag does not grant new transport consent")
        await rejectsAsync(.consentRequired, "legacy link cannot begin even a forced refresh before per-link review") { _ = try await store.begin(legacy.id, now: now, force: true) }
        await rejectsAsync(.consentRequired, "manual refresh cannot substitute for legacy re-consent") { try await store.requestRefresh(legacy.id) }
        let source = WatchedWebInformationSource(store: store, fetcher: BoundedWatchedLinkFetcher(resolver: DNSFixture(values: ["8.8.8.8"]), transport: HTTPFixture([])))
        expect(await source.authorization() == .disabled, "transport availability alone does not enable a legacy saved source")
        let event = InformationNormalizer.normalize(.init(externalID: "\(legacy.sourceIdentity)#saved", title: change.title, modifiedAt: now), source: .watchedWeb, now: now)!
        expect(!(await source.permits(event, now: now)), "legacy saved changes cannot enter Daily Summary without renewed consent")
        try await store.setEnabled(legacy.id, enabled: true)
        let reviewed = try await store.records(now: now)[0]
        expect(reviewed.permitsFetching && reviewed.transportConsentRevision == WatchedLinkLimits.transportConsentRevision, "explicit per-link resume grants only the current consent revision")
        expect(reviewed.etag == nil && reviewed.lastModifiedHeader == nil && reviewed.nextEligibleRefresh == nil, "resuming a reviewed link requires a complete fresh response")
        expect(reviewed.changes == [change] && reviewed.pageTitle == "Saved title", "re-consent does not erase previously retained history")
        let reopened = try await WatchedLinkStore(fileURL: file).records(now: now)[0]
        expect(reopened.permitsFetching && reopened.etag == nil, "per-link consent and fresh-validator state survive restart")
        try await store.setEnabled(legacy.id, enabled: false)
        let disabled = try await store.records(now: now)[0]
        expect(!disabled.permitsFetching && disabled.transportConsentRevision == nil && disabled.changes == [change], "disabling revokes consent while preserving history for inspection")
        try await store.remove(legacy.id)
        expect(try await WatchedLinkStore(fileURL: file).records(now: now).isEmpty, "saved legacy history remains individually deletable with fetching disabled")

        let ownership = WatchedLinkStore(fileURL: root.appendingPathComponent("ownership.json"))
        let record = try await ownership.add(name: "Explicit page", url: publicURL.absoluteString)
        expect(record.permitsFetching, "adding an explicitly enabled page records current per-link consent")
        let older = try await ownership.begin(record.id, now: now, force: true)!
        let newer = try await ownership.begin(record.id, now: now.addingTimeInterval(1), force: true)!
        expect(older.generation != newer.generation, "new forced refresh has distinct ownership")
        let extraction = try WebContentExtractor.extract(data: pageBytes, mimeType: "text/plain", now: now)
        let content = WatchedLinkFetchResponse(finalURL: publicURL, statusCode: 200, mimeType: "text/plain", data: pageBytes, etag: "\"fresh\"", lastModified: "Wed, 21 Oct 2026 10:00:00 GMT")
        await rejectsAsync(.staleRefresh, "stale commit cannot replace a newer refresh") { _ = try await ownership.commit(record.id, generation: older.generation, response: content, extraction: extraction, now: now) }
        try await ownership.fail(record.id, generation: older.generation, error: .restrictedContent, now: now)
        try await ownership.cancel(record.id, generation: older.generation)
        let stillRefreshing = try await ownership.records(now: now)[0]
        expect(stillRefreshing.state == .refreshing && stillRefreshing.consecutiveFailures == 0 && stillRefreshing.lastSuccess == nil, "stale fail and cancel do not alter newer ownership, failure state or success")
        expect(try await ownership.commit(record.id, generation: newer.generation, response: content, extraction: extraction, now: now), "newest owner can commit after stale callbacks")
        let committed = try await ownership.records(now: now)[0]
        expect(committed.state == .changed && committed.fingerprint == extraction.fingerprint && committed.etag == "\"fresh\"", "newest commit retains its own extracted content and validators")

        let disabledCycle = try await ownership.begin(record.id, now: now, force: true)!
        try await ownership.setEnabled(record.id, enabled: false)
        await rejectsAsync(.staleRefresh, "disable invalidates an outstanding commit") { _ = try await ownership.commit(record.id, generation: disabledCycle.generation, response: content, extraction: extraction, now: now) }
        try await ownership.fail(record.id, generation: disabledCycle.generation, error: .restrictedContent, now: now)
        try await ownership.cancel(record.id, generation: disabledCycle.generation)
        let afterDisable = try await ownership.records(now: now)[0]
        expect(afterDisable.state == .disabled && !afterDisable.permitsFetching && afterDisable.changes == extraction.changes && afterDisable.consecutiveFailures == 0, "late fail/cancel after disable cannot re-enable or erase retained history")
        await rejectsAsync(.disabled, "disabled link cannot begin a forced refresh") { _ = try await ownership.begin(record.id, now: now, force: true) }

        try await ownership.setEnabled(record.id, enabled: true)
        let removedCycle = try await ownership.begin(record.id, now: now, force: true)!
        try await ownership.remove(record.id)
        await rejectsAsync(.staleRefresh, "individual removal invalidates an outstanding commit") { _ = try await ownership.commit(record.id, generation: removedCycle.generation, response: content, extraction: extraction, now: now) }
        try await ownership.fail(record.id, generation: removedCycle.generation, error: .unavailable, now: now)
        try await ownership.cancel(record.id, generation: removedCycle.generation)
        expect(try await ownership.records(now: now).isEmpty, "late callbacks cannot resurrect a removed link")

        let resetRecord = try await ownership.add(name: "Reset page", url: publicURL.absoluteString)
        let resetCycle = try await ownership.begin(resetRecord.id, now: now, force: true)!
        try await ownership.reset()
        await rejectsAsync(.staleRefresh, "explicit reset invalidates an outstanding commit") { _ = try await ownership.commit(resetRecord.id, generation: resetCycle.generation, response: content, extraction: extraction, now: now) }
        try await ownership.fail(resetRecord.id, generation: resetCycle.generation, error: .unavailable, now: now)
        try await ownership.cancel(resetRecord.id, generation: resetCycle.generation)
        expect(try await ownership.records(now: now).isEmpty, "late callbacks cannot resurrect links after explicit reset")
    }
}
