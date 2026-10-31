import Foundation
import Darwin
import NIOCore
import NIOPosix
import Testing
@testable import SuzzmeWatchedTransport

#if WATCHED_TRANSPORT_CONNECTION_TESTS

private struct Fixture: Decodable, Sendable {
    let hostname: String
    let address: String
    let port: UInt16
    let tlsStallPort: UInt16
    let backlogPort: UInt16
    let backlogOutcome: String
    let backlogSocketError: Int
    let decoyPort: UInt16
    let auditPort: UInt16
    let rootDERPath: String
    let eventsPath: String

    static func load() throws -> Self {
        let path = try #require(ProcessInfo.processInfo.environment["SUZZME_WATCHED_TLS_FIXTURE"],
                                "Run Validation/watched-pinned-connection-check.sh to start isolated fixtures")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    func client() throws -> PinnedHTTPClient {
        try .connectionTestClient(rootCertificateDER: Data(contentsOf: URL(fileURLWithPath: rootDERPath)))
    }

    func request(_ path: String, hostname: String? = nil, port: UInt16? = nil,
                 timeout: TimeInterval = 3) -> PinnedHTTPRequest {
        .init(hostname: hostname ?? self.hostname, numericIPAddress: address, port: port ?? self.port,
              pathAndQuery: path, timeout: timeout)
    }

    struct Event: Decodable, Sendable {
        let event: String
        let id: Int?
        let mode: String?
        let port: UInt16?
        let method: String?
        let path: String?
        let headers: [String: String]?
        let bodyBytes: Int?
        let sni: String?
    }

    func events() throws -> [Event] {
        let data = try Data(contentsOf: URL(fileURLWithPath: eventsPath))
        return data.split(separator: 10).compactMap { try? JSONDecoder().decode(Event.self, from: Data($0)) }
    }

    func waitFor(_ predicate: (Event) -> Bool, timeout: Duration = .seconds(2)) async throws -> Event? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        repeat {
            if let event = try events().first(where: predicate) { return event }
            try await Task.sleep(for: .milliseconds(20))
        } while clock.now < deadline
        return nil
    }
}

private func rejects(_ errors: [PinnedHTTPError], operation: () async throws -> PinnedHTTPResponse) async {
    do {
        _ = try await operation()
        Issue.record("An adversarial socket response unexpectedly succeeded")
    } catch let error as PinnedHTTPError {
        #expect(errors.contains(error), "Unexpected transport error: \(error)")
    } catch {
        Issue.record("Expected a classified transport failure, received \(error)")
    }
}

@Suite(.serialized)
struct PinnedConnectionTests {
    @Test
    func socketUsesSelectedEndpointWithOriginalHostAndSNI() async throws {
        let fixture = try Fixture.load()
        let response = try await fixture.client().get(fixture.request("/ok"))
        #expect(response.statusCode == 200)
        #expect(response.data == Data("hello".utf8))
        #expect(response.peerIPAddress == fixture.address)
        #expect(response.peerPort == fixture.port)
        #expect(response.headers["content-type"] == ["text/plain"])
        let event = try #require(await fixture.waitFor { $0.event == "request" && $0.path == "/ok" })
        #expect(event.method == "GET")
        #expect(event.sni == fixture.hostname)
        #expect(event.headers?["host"] == "\(fixture.hostname):\(fixture.port)")
        #expect(event.bodyBytes == 0)
        for name in ["cookie", "authorization", "proxy-authorization", "referer", "origin"] {
            #expect(event.headers?[name] == nil)
        }
    }

    @Test
    func changedCandidateDoesNotRetargetSelectedSocket() async throws {
        let fixture = try Fixture.load()
        // .invalid has no usable DNS answer. Only the captured numeric endpoint can reach this listener.
        var candidatePort = fixture.port
        let selected = fixture.request("/captured-endpoint", port: candidatePort)
        candidatePort = fixture.decoyPort
        let response = try await fixture.client().get(selected)
        #expect(candidatePort != response.peerPort)
        #expect(response.peerPort == fixture.port)
        #expect(response.data == Data("hello".utf8))
        #expect(try !fixture.events().contains { $0.mode == "decoy" && $0.event == "accepted" })
    }

    @Test(arguments: ["wrong.fixture.invalid", "untrusted.fixture.invalid", "expired.fixture.invalid"])
    func normalTLSVerificationRejectsInvalidIdentity(hostname: String) async throws {
        let fixture = try Fixture.load()
        let client = try fixture.client()
        await rejects([.tlsVerificationFailed]) {
            try await client.get(fixture.request("/must-not-be-read", hostname: hostname))
        }
        #expect(try !fixture.events().contains { $0.event == "request" && $0.sni == hostname })
    }

    @Test
    func privateAIAIsNeverFetchedByTrustEvaluation() async throws {
        let fixture = try Fixture.load()
        let client = try fixture.client()
        // The missing intermediate is available only from the private HTTP audit listener.
        await rejects([.tlsVerificationFailed]) {
            try await client.get(fixture.request("/must-not-be-read", hostname: "aia.fixture.invalid"))
        }
        #expect(try !fixture.events().contains { $0.mode == "audit" && $0.event == "accepted" })
    }

    @Test
    func productionFactoryRejectsLoopbackBeforeSocketCreation() async throws {
        let fixture = try Fixture.load()
        let before = try fixture.events().filter { $0.event == "accepted" }.count
        await rejects([.prohibitedAddress, .invalidRequest]) {
            try await PinnedHTTPClient().get(fixture.request("/production-must-not-connect"))
        }
        #expect(try fixture.events().filter { $0.event == "accepted" }.count == before)
    }

    @Test(arguments: [201, 204, 301, 302, 303, 304, 307, 308, 400, 401, 403, 404, 429, 500, 503])
    func oneHopReturnsStatusAndHeadersWithoutFollowing(status: Int) async throws {
        let fixture = try Fixture.load()
        let response = try await fixture.client().get(fixture.request("/status/\(status)"))
        #expect(response.statusCode == status)
        #expect(response.headers["location"] == ["https://target.fixture.invalid/next"])
        #expect(response.data.isEmpty)
        #expect(response.peerPort == fixture.port)
    }

    @Test(arguments: ["html", "plain", "xhtml", "case"])
    func exactSupportedMIMETypesAreAccepted(kind: String) async throws {
        let fixture = try Fixture.load()
        let response = try await fixture.client().get(fixture.request("/mime/\(kind)"))
        #expect(response.data == Data("hello".utf8))
    }

    @Test
    func identityEncodingAndExactBoundsAreAccepted() async throws {
        let fixture = try Fixture.load()
        let client = try fixture.client()
        #expect(try await client.get(fixture.request("/identity-encoding")).data == Data("hello".utf8))
        #expect(try await client.get(fixture.request("/close-delimited")).data == Data("hello".utf8))
        #expect(try await client.get(fixture.request("/header-exact-limit")).data == Data("hello".utf8))
        let body = try await client.get(fixture.request("/body-at-limit"))
        #expect(body.data.count == 512 * 1024)
        #expect(body.data.allSatisfy { $0 == UInt8(ascii: "b") })
    }

    @Test(arguments: ["headers-too-large", "fragmented-headers", "whitespace-too-large", "status-line-too-large"])
    func rawHeaderBudgetIncludesWhitespaceAndStatusLine(path: String) async throws {
        let fixture = try Fixture.load()
        let client = try fixture.client()
        await rejects([.headerTooLarge]) { try await client.get(fixture.request("/\(path)")) }
    }

    @Test(arguments: ["body-over-limit", "advertised-body-over-limit"])
    func bodyBudgetRejectsAdvertisedAndStreamedOverflow(path: String) async throws {
        let fixture = try Fixture.load()
        let client = try fixture.client()
        await rejects([.bodyTooLarge]) { try await client.get(fixture.request("/\(path)")) }
    }

    @Test(arguments: ["malformed-status", "malformed-header", "duplicate-length", "conflicting-length", "duplicate-type", "duplicate-location", "truncated-body"])
    func malformedAndAmbiguousFramingFailsClosed(path: String) async throws {
        let fixture = try Fixture.load()
        let client = try fixture.client()
        await rejects([.malformedResponse, .unsupportedResponse, .connectionFailed]) { try await client.get(fixture.request("/\(path)")) }
    }

    @Test(arguments: ["unsupported-mime", "mime-prefix", "missing-mime", "content-encoding", "transfer-chunked", "transfer-identity", "transfer-gzip", "transfer-trailers", "informational", "upgrade"])
    func unsupportedRepresentationsAndProtocolSwitchesAreRejected(path: String) async throws {
        let fixture = try Fixture.load()
        let client = try fixture.client()
        await rejects([.unsupportedResponse, .malformedResponse]) { try await client.get(fixture.request("/\(path)")) }
    }

    @Test(arguments: ["/slow-head", "/slow-body"])
    func absoluteDeadlineIncludesResponseBody(path: String) async throws {
        let fixture = try Fixture.load()
        let client = try fixture.client()
        let clock = ContinuousClock()
        let start = clock.now
        await rejects([.timeout]) { try await client.get(fixture.request(path, timeout: 0.35)) }
        #expect(start.duration(to: clock.now) < .seconds(2))
        let request = try #require(await fixture.waitFor { $0.event == "request" && $0.path == path })
        #expect(try await fixture.waitFor { $0.event == "peer_closed" && $0.id == request.id } != nil)
    }

    @Test
    func deadlineClosesStalledTLSSetup() async throws {
        let fixture = try Fixture.load()
        let client = try fixture.client()
        let clock = ContinuousClock()
        let start = clock.now
        await rejects([.timeout]) { try await client.get(fixture.request("/unused", port: fixture.tlsStallPort, timeout: 0.35)) }
        #expect(start.duration(to: clock.now) < .seconds(2))
        let accepted = try #require(await fixture.waitFor { $0.event == "accepted" && $0.port == fixture.tlsStallPort })
        #expect(try await fixture.waitFor { $0.event == "peer_closed" && $0.id == accepted.id } != nil)
    }

    @Test
    func fullTCPBacklogEndsPromptlyAccordingToObservedKernelBehavior() async throws {
        let fixture = try Fixture.load()
        let client = try fixture.client()
        try #require(["reset", "pending"].contains(fixture.backlogOutcome))
        if fixture.backlogOutcome == "reset" {
            #expect([Int(ECONNRESET), Int(ECONNREFUSED)].contains(fixture.backlogSocketError))
        } else {
            #expect(fixture.backlogSocketError == 0)
        }
        let clock = ContinuousClock()
        let start = clock.now
        let expected: PinnedHTTPError = fixture.backlogOutcome == "pending" ? .timeout : .connectionFailed
        await rejects([expected]) {
            try await client.get(fixture.request("/unused", port: fixture.backlogPort, timeout: 0.35))
        }
        #expect(start.duration(to: clock.now) < .seconds(2))
        // An immediate kernel reset is connection-failure evidence, not proof
        // that this host induced a stalled TCP handshake or a TCP timeout.
    }

    @Test(arguments: ["deadline", "cancellation"])
    func deadlineAndCancellationCloseOwnedSocketBeforeConnectStarts(cause: String) async throws {
        let fixture = try Fixture.load()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        do {
            let loop = group.next()
            let lifetime = RequestLifetime(loop: loop)
            let created = loop.makePromise(of: (any Channel).self)
            let initializerGate = loop.makePromise(of: Void.self)
            let before = try fixture.events().filter { $0.event == "accepted" }.count
            let bootstrap = ClientBootstrap(group: group).channelInitializer { channel in
                guard lifetime.own(channel) else { return channel.close() }
                channel.closeFuture.whenComplete { _ in
                    initializerGate.fail(ChannelError.ioOnClosedChannel)
                }
                created.succeed(channel)
                // NIO has created a real SocketChannel/descriptor, but cannot
                // register or connect it until this deliberately held stage ends.
                return initializerGate.futureResult
            }
            let connection = bootstrap.connect(to: try SocketAddress(ipAddress: fixture.address, port: Int(fixture.port)))
            let channel = try await created.futureResult.get()
            #expect(try await channel.getOption(ChannelOptions.socket(SOL_SOCKET, SO_TYPE)).get() == SOCK_STREAM)
            #expect(!channel.isActive)
            let operation = Task {
                try await withTaskCancellationHandler {
                    try await lifetime.promise.futureResult.get()
                } onCancel: {
                    lifetime.finish(.failure(CancellationError()))
                }
            }
            let clock = ContinuousClock()
            let start = clock.now
            if cause == "deadline" {
                lifetime.armDeadline(seconds: 0.35)
                await rejects([.timeout]) { try await operation.value }
            } else {
                operation.cancel()
                await #expect(throws: CancellationError.self) { try await operation.value }
            }
            #expect(start.duration(to: clock.now) < .seconds(2))
            try await channel.closeFuture.get()
            await #expect(throws: (any Error).self) { _ = try await connection.get() }
            await #expect(throws: (any Error).self) {
                _ = try await channel.getOption(ChannelOptions.socket(SOL_SOCKET, SO_TYPE)).get()
            }
            #expect(try fixture.events().filter { $0.event == "accepted" }.count == before)
            try await group.shutdownGracefully()
        } catch {
            try? await group.shutdownGracefully()
            throw error
        }
    }

    @Test(arguments: ["/cancel-head", "/cancel-body"])
    func cancellationPromptlyClosesOutstandingHTTPWork(path: String) async throws {
        let fixture = try Fixture.load()
        let client = try fixture.client()
        let request = fixture.request(path)
        let task = Task { try await client.get(request) }
        let observed = try await fixture.waitFor { $0.event == "request" && $0.path == path }
        guard let event = observed else {
            task.cancel()
            Issue.record("Fixture did not observe the owned request before cancellation")
            return
        }
        let clock = ContinuousClock()
        let start = clock.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(start.duration(to: clock.now) < .seconds(1))
        #expect(try await fixture.waitFor { $0.event == "peer_closed" && $0.id == event.id } != nil)
    }

    @Test
    func cancellationDuringTLSSetupClosesTheSocket() async throws {
        let fixture = try Fixture.load()
        let client = try fixture.client()
        let previousIDs = Set(try fixture.events().compactMap(\.id))
        let request = fixture.request("/unused", port: fixture.tlsStallPort)
        let task = Task { try await client.get(request) }
        let accepted = try await fixture.waitFor {
            $0.event == "accepted" && $0.port == fixture.tlsStallPort && $0.id.map { !previousIDs.contains($0) } == true
        }
        guard let event = accepted else {
            task.cancel()
            Issue.record("TLS fixture did not observe the owned socket before cancellation")
            return
        }
        let clock = ContinuousClock()
        let start = clock.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(start.duration(to: clock.now) < .seconds(1))
        #expect(try await fixture.waitFor { $0.event == "peer_closed" && $0.id == event.id } != nil)
    }

    @Test
    func cancellationBeforeGetNeverCreatesASocket() async throws {
        let fixture = try Fixture.load()
        let client = try fixture.client()
        let before = try fixture.events().filter { $0.event == "accepted" }.count
        let request = fixture.request("/already-cancelled")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.get(request)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try fixture.events().filter { $0.event == "accepted" }.count == before)
    }
}

#endif
