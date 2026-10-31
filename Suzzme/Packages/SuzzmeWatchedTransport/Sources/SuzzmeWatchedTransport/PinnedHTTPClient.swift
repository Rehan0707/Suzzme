import Foundation
import Darwin
import Dispatch
import NIOCore
import NIOPosix
import NIOConcurrencyHelpers
import NIOHTTP1
import NIOTLS
import NIOSSL

/// Exactly one anonymous HTTPS GET. Resolution and redirect decisions belong to
/// the caller; this transport never takes a hostname through a socket resolver.
public struct PinnedHTTPRequest: Sendable {
    public let hostname: String
    public let numericIPAddress: String
    public let port: UInt16
    public let pathAndQuery: String
    public let etag: String?
    public let lastModified: String?
    public let timeout: TimeInterval

    public init(hostname: String, numericIPAddress: String, port: UInt16 = 443,
                pathAndQuery: String, etag: String? = nil, lastModified: String? = nil,
                timeout: TimeInterval = 15) {
        self.hostname = hostname; self.numericIPAddress = numericIPAddress
        self.port = port; self.pathAndQuery = pathAndQuery
        self.etag = etag; self.lastModified = lastModified; self.timeout = timeout
    }
}

public struct PinnedHTTPResponse: Sendable {
    public let statusCode: Int
    /// Lowercase field names. Cookies are discarded, and sensitive duplicate
    /// fields fail closed instead of being interpreted by different parsers.
    public let headers: [String: [String]]
    public let data: Data
    public let peerIPAddress: String
    public let peerPort: UInt16
}

public enum PinnedHTTPError: Error, Sendable, Equatable {
    case invalidRequest, prohibitedAddress, peerMismatch, connectionFailed
    case tlsVerificationFailed, timeout, headerTooLarge, bodyTooLarge
    case unsupportedResponse, malformedResponse
}

enum TransportLimits {
    static let headerBytes = 8_192
    static let bodyBytes = 512 * 1_024
    static let pieceBytes = 4_096
    static let wireBytes = 1_048_576
    static let plaintextBytes = headerBytes + bodyBytes + pieceBytes
    static let certificateCount = 8
    static let certificateBytes = 65_536
}

private enum TransportLoop {
    // One process-lifetime event loop, with no HTTP connection pool or cache.
    static let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
}

public struct PinnedHTTPClient: Sendable {
    private let trust = ServerTrustConfiguration()
    #if WATCHED_TRANSPORT_CONNECTION_TESTS
    private var testTrust: ServerTrustConfiguration?
    #endif

    public init() {}

    #if WATCHED_TRANSPORT_CONNECTION_TESTS
    /// This symbol and all root/loopback configuration are absent from normal
    /// products. It does not change a device's trust store or hostname policy.
    public static func connectionTestClient(rootCertificateDER: Data) throws -> Self {
        var client = Self()
        client.testTrust = try ServerTrustConfiguration(connectionTestRoot: rootCertificateDER)
        return client
    }
    #endif

    public func get(_ request: PinnedHTTPRequest) async throws -> PinnedHTTPResponse {
        try Task.checkCancellation()
        #if WATCHED_TRANSPORT_CONNECTION_TESTS
        let configuration = testTrust ?? trust
        #else
        let configuration = trust
        #endif
        let address = try RequestValidation.address(for: request, allowLoopback: configuration.permitsLoopback)
        let loop = TransportLoop.group.next()
        let lifetime = RequestLifetime(loop: loop)
        lifetime.armDeadline(seconds: request.timeout)

        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                var tls = TLSConfiguration.makeClientConfiguration()
                tls.minimumTLSVersion = .tlsv12
                tls.certificateVerification = .fullVerification
                tls.trustRoots = .default
                tls.applicationProtocols = ["http/1.1"]
                tls.renegotiationSupport = .none
                // Cancelled/finished one-shot reads must not wait for a peer's
                // close_notify before closing the underlying TCP descriptor.
                tls.shutdownTimeout = .nanoseconds(0)
                let context = try NIOSSLContext(configuration: tls)
                let bootstrap = ClientBootstrap(group: TransportLoop.group)
                    .connectTimeout(.nanoseconds(Int64(min(request.timeout, 5) * 1_000_000_000)))
                    .channelOption(ChannelOptions.recvAllocator, value: FixedSizeRecvByteBufferAllocator(capacity: TransportLimits.pieceBytes))
                    .channelOption(ChannelOptions.maxMessagesPerRead, value: 1)
                    .channelInitializer { channel in
                        // Install ownership before connect/TLS, including when
                        // cancellation races the bootstrap initializer.
                        guard lifetime.own(channel) else { return channel.close() }
                        do {
                            let state = ResponseState()
                            var limits = NIOHTTPDecoderLimitConfiguration()
                            limits.maxHeaderFieldSize = TransportLimits.headerBytes
                            limits.maxHeaderListSize = TransportLimits.headerBytes
                            limits.maxHeaderFieldCount = 64
                            let ssl = try NIOSSLClientHandler(context: context, serverHostname: request.hostname,
                                customVerificationCallback: { chain, promise in
                                    configuration.verify(chain: chain, hostname: request.hostname,
                                                         lifetime: lifetime, promise: promise)
                                })
                            // The bootstrap invokes this initializer on the
                            // channel event loop. Handlers never cross threads.
                            channel.eventLoop.preconditionInEventLoop()
                            try channel.pipeline.syncOperations.addHandlers([
                                PeerGate(expected: address, lifetime: lifetime),
                                ssl,
                                HTTPWireBudget(state: state, lifetime: lifetime),
                                HTTPRequestEncoder(),
                                ByteToMessageHandler(HTTPResponseDecoder(
                                    informationalResponseStrategy: .forward, limitConfiguration: limits)),
                                ResponseCollector(request: request, state: state, lifetime: lifetime),
                            ])
                            return channel.eventLoop.makeSucceededVoidFuture()
                        } catch {
                            lifetime.finish(.failure(PinnedHTTPError.tlsVerificationFailed))
                            return channel.eventLoop.makeFailedFuture(PinnedHTTPError.tlsVerificationFailed)
                        }
                    }
                bootstrap.connect(to: address).whenFailure { error in
                    lifetime.finish(.failure((error as? PinnedHTTPError) ?? .connectionFailed))
                }
                return try await lifetime.promise.futureResult.get()
            } catch {
                lifetime.finish(.failure(error))
                throw error
            }
        } onCancel: {
            lifetime.finish(.failure(CancellationError()))
        }
    }
}

/// Only synchronized ownership lives here. Protocol parser state stays on the
/// channel's event loop. Finishing once closes TCP, TLS, and all pending reads.
final class RequestLifetime: Sendable {
    private struct State {
        var finished = false
        var channel: (any Channel)?
        var deadline: Scheduled<Void>?
        var handshakeDeadline: Scheduled<Void>?
    }
    private let state = NIOLockedValueBox(State())
    let promise: EventLoopPromise<PinnedHTTPResponse>
    private let loop: any EventLoop

    init(loop: any EventLoop) { self.loop = loop; promise = loop.makePromise() }

    var isFinished: Bool { state.withLockedValue { $0.finished } }

    func own(_ channel: any Channel) -> Bool {
        state.withLockedValue {
            guard !$0.finished else { return false }
            $0.channel = channel; return true
        }
    }

    func armDeadline(seconds: Double) {
        let timer = loop.scheduleTask(in: .nanoseconds(Int64(seconds * 1_000_000_000))) { [self] in
            finish(.failure(PinnedHTTPError.timeout))
        }
        let cancel = state.withLockedValue { value in
            guard !value.finished else { return true }
            value.deadline = timer; return false
        }
        if cancel { timer.cancel() }
    }

    func armHandshakeDeadline() {
        let timer = loop.scheduleTask(in: .seconds(5)) { [self] in finish(.failure(PinnedHTTPError.timeout)) }
        let cancel = state.withLockedValue { value in
            guard !value.finished else { return true }
            value.handshakeDeadline = timer; return false
        }
        if cancel { timer.cancel() }
    }

    func handshakeCompleted() {
        let timer = state.withLockedValue { value in
            defer { value.handshakeDeadline = nil }
            return value.handshakeDeadline
        }
        timer?.cancel()
    }

    func finish(_ result: Result<PinnedHTTPResponse, any Error>) {
        let resources = state.withLockedValue { value -> State? in
            guard !value.finished else { return nil }
            let resources = value
            value = State(finished: true)
            return resources
        }
        guard let resources else { return }
        resources.deadline?.cancel(); resources.handshakeDeadline?.cancel()
        resources.channel?.close(promise: nil)
        promise.completeWith(result)
    }
}

private enum RequestValidation {
    static func address(for request: PinnedHTTPRequest, allowLoopback: Bool) throws -> SocketAddress {
        let host = request.hostname
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard request.timeout.isFinite, request.timeout > 0, request.timeout <= 15,
              request.port > 0, host.utf8.count <= 253, host == host.lowercased(), labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-") &&
                  $0.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 } }),
              labels.last?.utf8.contains(where: { (97...122).contains($0) }) == true,
              request.pathAndQuery.hasPrefix("/"), !request.pathAndQuery.hasPrefix("//"),
              request.pathAndQuery.utf8.count <= 2_048,
              request.pathAndQuery.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 && $0 != 35 && $0 != 92 }),
              [request.etag, request.lastModified].allSatisfy({ value in
                  value.map { $0.utf8.count <= 1_024 && $0.utf8.allSatisfy { $0 >= 32 && $0 < 127 } } ?? true
              }) else { throw PinnedHTTPError.invalidRequest }
        guard let bytes = numericBytes(request.numericIPAddress),
              globallyRoutable(bytes) || allowLoopback && loopback(bytes) else { throw PinnedHTTPError.prohibitedAddress }
        return try SocketAddress(ipAddress: request.numericIPAddress, port: Int(request.port))
    }

    private static func numericBytes(_ text: String) -> [UInt8]? {
        guard text.utf8.count <= 45, !text.contains("%"), !text.contains("[") else { return nil }
        var v4 = in_addr(); var v6 = in6_addr()
        if inet_pton(AF_INET, text, &v4) == 1 { return withUnsafeBytes(of: v4) { Array($0) } }
        if inet_pton(AF_INET6, text, &v6) == 1 { return withUnsafeBytes(of: v6) { Array($0) } }
        return nil
    }

    private static func loopback(_ bytes: [UInt8]) -> Bool {
        if bytes.count == 4 { return bytes[0] == 127 }
        return bytes.count == 16 && bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
    }

    /// Defense in depth at the public package boundary. The application also
    /// validates every DNS answer, rejecting mixed answers before selecting one.
    private static func globallyRoutable(_ b: [UInt8]) -> Bool {
        if b.count == 4 {
            let a = Int(b[0]), second = Int(b[1]), third = Int(b[2])
            return !(a == 0 || a == 10 || a == 127 || a >= 224 ||
                a == 100 && (64...127).contains(second) || a == 169 && second == 254 ||
                a == 172 && (16...31).contains(second) || a == 192 && second == 168 ||
                a == 192 && second == 0 && (third == 0 || third == 2) ||
                a == 192 && second == 88 && third == 99 || a == 198 && (second == 18 || second == 19) ||
                a == 198 && second == 51 && third == 100 || a == 203 && second == 0 && third == 113)
        }
        guard b.count == 16 else { return false }
        // Match the application's conservative IANA allocated-unicast snapshot;
        // future/unallocated and transition prefixes require a policy review.
        // https://www.iana.org/assignments/ipv6-unicast-address-assignments/
        let first = UInt16(b[0]) << 8 | UInt16(b[1])
        let second = UInt16(b[2]) << 8 | UInt16(b[3])
        if first == 0x2001 {
            if second == 0x0db8 { return false }
            return (0x0200...0x0fff).contains(second) || (0x1200...0x4dff).contains(second)
                || (0x5000...0x5fff).contains(second) || (0x8000...0xbfff).contains(second)
        }
        if first == 0x2003 { return second <= 0x3fff }
        return (0x2400...0x241f).contains(first) || (0x2600...0x2611).contains(first)
            || (0x2620...0x2621).contains(first) || (0x2630...0x263f).contains(first)
            || (0x2800...0x280f).contains(first) || (0x2a00...0x2a1f).contains(first)
            || (0x2c00...0x2c0f).contains(first)
    }
}

private final class PeerGate: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer
    private let expected: SocketAddress
    private let lifetime: RequestLifetime
    private var wireBytes = 0
    init(expected: SocketAddress, lifetime: RequestLifetime) { self.expected = expected; self.lifetime = lifetime }

    func channelActive(context: ChannelHandlerContext) {
        guard context.channel.remoteAddress == expected else {
            lifetime.finish(.failure(PinnedHTTPError.peerMismatch)); return
        }
        guard !lifetime.isFinished else { context.close(promise: nil); return }
        lifetime.armHandshakeDeadline()
        // The TLS handler cannot start ClientHello before this identity check.
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        guard buffer.readableBytes <= TransportLimits.pieceBytes,
              wireBytes <= TransportLimits.wireBytes - buffer.readableBytes else {
            lifetime.finish(.failure(PinnedHTTPError.bodyTooLarge)); return
        }
        wireBytes += buffer.readableBytes
        context.fireChannelRead(data)
    }
}

private final class ResponseState {
    var finalHeadReceived = false
    var handshakeComplete = false
}

private final class HTTPWireBudget: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    private let state: ResponseState
    private let lifetime: RequestLifetime
    private var beforeHead = 0
    private var total = 0
    init(state: ResponseState, lifetime: RequestLifetime) { self.state = state; self.lifetime = lifetime }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var bytes = unwrapInboundIn(data)
        while !lifetime.isFinished, bytes.readableBytes > 0 {
            let size = min(bytes.readableBytes, TransportLimits.pieceBytes)
            guard total <= TransportLimits.plaintextBytes - size,
                  let piece = bytes.readSlice(length: size) else {
                lifetime.finish(.failure(PinnedHTTPError.bodyTooLarge)); return
            }
            total += size
            if !state.finalHeadReceived {
                // Count before invoking the maintained decoder: its response
                // head cannot allocate an unbounded set of strings. Counting
                // a partial body in this last piece is conservative.
                guard beforeHead <= TransportLimits.headerBytes - size else {
                    lifetime.finish(.failure(PinnedHTTPError.headerTooLarge)); return
                }
                beforeHead += size
            }
            context.fireChannelRead(NIOAny(piece))
        }
    }
}

private final class ResponseCollector: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart
    private let request: PinnedHTTPRequest
    private let state: ResponseState
    private let lifetime: RequestLifetime
    private var head: HTTPResponseHead?
    private var headers: [String: [String]] = [:]
    private var body = Data()
    private var expectedLength: Int?

    init(request: PinnedHTTPRequest, state: ResponseState, lifetime: RequestLifetime) {
        self.request = request; self.state = state; self.lifetime = lifetime
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if case let TLSUserEvent.handshakeCompleted(negotiatedProtocol) = event {
            guard negotiatedProtocol == nil || negotiatedProtocol == "http/1.1", !lifetime.isFinished else {
                lifetime.finish(.failure(PinnedHTTPError.unsupportedResponse)); return
            }
            state.handshakeComplete = true
            lifetime.handshakeCompleted()
            var fields = HTTPHeaders()
            fields.add(name: "Host", value: request.hostname + (request.port == 443 ? "" : ":\(request.port)"))
            fields.add(name: "Accept", value: "text/html, text/plain, application/xhtml+xml")
            fields.add(name: "Accept-Encoding", value: "identity")
            fields.add(name: "Connection", value: "close")
            if let value = request.etag { fields.add(name: "If-None-Match", value: value) }
            if let value = request.lastModified { fields.add(name: "If-Modified-Since", value: value) }
            let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: request.pathAndQuery, headers: fields)
            context.write(wrapOutboundOut(.head(head)), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !lifetime.isFinished else { return }
        switch unwrapInboundIn(data) {
        case .head(let response):
            guard head == nil, response.version == .http1_1 || response.version == .http1_0,
                  (200...599).contains(response.status.code) else {
                lifetime.finish(.failure(PinnedHTTPError.unsupportedResponse)); return
            }
            let unique = Set(["content-length", "content-type", "location", "etag", "last-modified", "transfer-encoding", "content-encoding", "connection", "trailer"])
            for field in response.headers {
                let name = field.name.lowercased()
                if unique.contains(name), headers[name] != nil {
                    lifetime.finish(.failure(PinnedHTTPError.malformedResponse)); return
                }
                if name == "set-cookie" { continue }
                headers[name, default: []].append(field.value)
            }
            guard headers["transfer-encoding"] == nil, headers["trailer"] == nil,
                  headers["content-encoding"]?.first.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() == "identity" }) ?? true else {
                lifetime.finish(.failure(PinnedHTTPError.unsupportedResponse)); return
            }
            if let raw = headers["content-length"]?.first {
                guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }), let length = Int(raw) else {
                    lifetime.finish(.failure(PinnedHTTPError.malformedResponse)); return
                }
                guard length <= TransportLimits.bodyBytes else { lifetime.finish(.failure(PinnedHTTPError.bodyTooLarge)); return }
                expectedLength = length
            }
            head = response; state.finalHeadReceived = true
            if response.status.code != 200 { succeed(context: context); return }
            let mime = headers["content-type"]?.first?.split(separator: ";", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespaces).lowercased()
            guard mime.map({ ["text/html", "text/plain", "application/xhtml+xml"].contains($0) }) == true else {
                lifetime.finish(.failure(PinnedHTTPError.unsupportedResponse)); return
            }
        case .body(let piece):
            guard head != nil, piece.readableBytes <= TransportLimits.bodyBytes - body.count else {
                lifetime.finish(.failure(PinnedHTTPError.bodyTooLarge)); return
            }
            body.append(contentsOf: piece.readableBytesView)
        case .end(let trailers):
            guard head != nil, trailers == nil || trailers?.isEmpty == true,
                  expectedLength.map({ $0 == body.count }) ?? true else {
                lifetime.finish(.failure(PinnedHTTPError.malformedResponse)); return
            }
            succeed(context: context)
        }
    }

    private func succeed(context: ChannelHandlerContext) {
        guard let head, let remote = context.channel.remoteAddress, let ip = remote.ipAddress,
              let port = remote.port, let peerPort = UInt16(exactly: port) else {
            lifetime.finish(.failure(PinnedHTTPError.peerMismatch)); return
        }
        lifetime.finish(.success(.init(statusCode: Int(head.status.code), headers: headers, data: body,
                                      peerIPAddress: ip, peerPort: peerPort)))
    }

    func channelInactive(context: ChannelHandlerContext) {
        if !lifetime.isFinished {
            lifetime.finish(.failure(state.handshakeComplete ? PinnedHTTPError.malformedResponse : .tlsVerificationFailed))
        }
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        if let failure = error as? PinnedHTTPError { lifetime.finish(.failure(failure)) }
        else if let parser = error as? HTTPParserError {
            if case .headerOverflow = parser { lifetime.finish(.failure(PinnedHTTPError.headerTooLarge)) }
            else { lifetime.finish(.failure(PinnedHTTPError.malformedResponse)) }
        }
        else if let ssl = error as? NIOSSLError, case .uncleanShutdown = ssl, state.handshakeComplete {
            lifetime.finish(.failure(PinnedHTTPError.malformedResponse))
        }
        else { lifetime.finish(.failure(state.handshakeComplete ? PinnedHTTPError.connectionFailed : .tlsVerificationFailed)) }
    }
}
