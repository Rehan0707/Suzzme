import Foundation
import Network
import Security
import os

struct PinnedMCPHTTPResponse: Sendable { let status: Int; let headers: [String: String]; let body: Data }

protocol PinnedMCPHTTPPosting: Sendable {
    func post(endpoint: URL, address: String, headers: [String: String], body: Data, responseID: String?) async throws -> PinnedMCPHTTPResponse
}

/// One bounded direct TLS connection per HTTP POST. No DNS, proxy, redirect,
/// cookies, credentials store, image/resource fetch, or arbitrary command.
struct PinnedMCPHTTPClient: PinnedMCPHTTPPosting {
    static let wireLimit = 320 * 1024
    func post(endpoint: URL, address: String, headers: [String: String], body: Data, responseID: String?) async throws -> PinnedMCPHTTPResponse {
        guard CustomMCPPolicy.endpoint(endpoint.absoluteString, address: address) == endpoint,
              let host = endpoint.host, body.count <= 32_768,
              headers.allSatisfy({ $0.key.utf8.allSatisfy { (33...126).contains($0) } && $0.value.utf8.allSatisfy { (32...126).contains($0) } }) else { throw IntegrationFailure.invalidConfiguration }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, host)
        sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, finish in
            let trustRef = sec_trust_copy_ref(trust).takeRetainedValue()
            SecTrustSetPolicies(trustRef, SecPolicyCreateSSL(true, host as CFString))
            finish(SecTrustEvaluateWithError(trustRef, nil))
        }, .global(qos: .utility))
        let connection = NWConnection(host: NWEndpoint.Host(address), port: .https, using: NWParameters(tls: tls, tcp: NWProtocolTCP.Options()))
        let exchange = PinnedMCPExchange(connection: connection)
        var target = endpoint.path.isEmpty ? "/" : endpoint.path
        if let encoded = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)?.percentEncodedPath, !encoded.isEmpty { target = encoded }
        var request = "POST \(target) HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\nContent-Length: \(body.count)\r\n"
        for key in headers.keys.sorted() { request += key + ": " + (headers[key] ?? "") + "\r\n" }
        request += "\r\n"
        var wire = Data(request.utf8); wire.append(body)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { exchange.start(wire: wire, responseID: responseID, continuation: $0) }
        } onCancel: { exchange.finish(.failure(CancellationError())) }
    }
    static func parse(_ wire: Data, ended: Bool, responseID: String?) throws -> PinnedMCPHTTPResponse? {
        guard wire.count <= wireLimit else { throw IntegrationFailure.oversizedResult }
        guard let split = wire.range(of: Data("\r\n\r\n".utf8)) else {
            if wire.count > 16_384 || ended { throw IntegrationFailure.connectorUnavailable }; return nil
        }
        guard split.lowerBound <= 16_384, let header = String(data: wire[..<split.lowerBound], encoding: .utf8) else { throw IntegrationFailure.connectorUnavailable }
        let lines = header.components(separatedBy: "\r\n")
        guard let first = lines.first, first.hasPrefix("HTTP/1.1 "), let status = Int(first.split(separator: " ").dropFirst().first ?? "") else { throw IntegrationFailure.connectorUnavailable }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw IntegrationFailure.connectorUnavailable }
            let key = line[..<colon].lowercased(), value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard headers[key] == nil else { throw IntegrationFailure.connectorUnavailable }; headers[key] = value
        }
        if (300...399).contains(status) { throw IntegrationFailure.policyDenied }
        var payload = Data(wire[split.upperBound...]); var complete = ended
        if let encoding = headers["transfer-encoding"] {
            guard encoding.lowercased() == "chunked", headers["content-length"] == nil else { throw IntegrationFailure.connectorUnavailable }
            var offset = 0, decoded = Data(); complete = false
            while offset < payload.count {
                guard let line = payload.range(of: Data("\r\n".utf8), in: offset..<payload.count),
                      let rawSize = String(data: payload[offset..<line.lowerBound], encoding: .ascii), rawSize.count <= 8,
                      let size = Int(rawSize, radix: 16), size >= 0, size <= wireLimit else { if ended { throw IntegrationFailure.connectorUnavailable }; return nil }
                offset = line.upperBound
                if size == 0 { complete = payload.count >= offset + 2; break }
                guard payload.count >= offset + size + 2 else { if ended { throw IntegrationFailure.connectorUnavailable }; return nil }
                guard payload[offset+size..<offset+size+2] == Data("\r\n".utf8) else { throw IntegrationFailure.connectorUnavailable }
                decoded.append(payload[offset..<offset+size]); offset += size + 2
            }
            payload = decoded
        } else if let raw = headers["content-length"] {
            guard let count = Int(raw), count >= 0, count <= wireLimit else { throw IntegrationFailure.oversizedResult }
            guard payload.count <= count else { throw IntegrationFailure.connectorUnavailable }
            complete = payload.count == count
            if ended, !complete { throw IntegrationFailure.connectorUnavailable }
        }
        if headers["content-type"]?.lowercased().hasPrefix("text/event-stream") == true,
           let expected = responseID, let text = String(data: payload, encoding: .utf8) {
            for event in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n").dropLast(complete ? 0 : 1) {
                let json = event.components(separatedBy: "\n").filter { $0.hasPrefix("data:") }.map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
                if let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any], String(describing: object["id"] ?? "") == expected {
                    var projection = headers; projection["content-type"] = "application/json"
                    return .init(status: status, headers: projection, body: Data(json.utf8))
                }
            }
            if complete { throw IntegrationFailure.connectorUnavailable }; return nil
        }
        guard complete else { return nil }
        return .init(status: status, headers: headers, body: payload)
    }
}

/// NWConnection callbacks run on a serial queue. Only completion ownership is
/// shared with task cancellation; the mutex makes finishing exactly once safe.
private final class PinnedMCPExchange: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "suzzme.mcp.pinned-http")
    private let state = OSAllocatedUnfairLock(initialState: (finished: false, continuation: nil as CheckedContinuation<PinnedMCPHTTPResponse, any Error>?))
    private var buffer = Data() // serial callback queue only
    init(connection: NWConnection) { self.connection = connection }
    func start(wire: Data, responseID: String?, continuation: CheckedContinuation<PinnedMCPHTTPResponse, any Error>) {
        let active = state.withLock { value in
            guard !value.finished else { return false }; value.continuation = continuation; return true
        }
        guard active else { continuation.resume(throwing: CancellationError()); return }
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.connection.send(content: wire, completion: .contentProcessed { [weak self] error in
                    guard let self else { return }
                    if error != nil { self.finish(.failure(IntegrationFailure.connectorUnavailable)) }
                    else { self.receive(responseID: responseID) }
                })
            case .failed, .cancelled: self.finish(.failure(IntegrationFailure.connectorUnavailable))
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 25) { [weak self] in self?.finish(.failure(IntegrationFailure.connectorUnavailable)) }
    }
    private func receive(responseID: String?) {
        guard !state.withLock({ $0.finished }) else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, ended, error in
            guard let self, !self.state.withLock({ $0.finished }) else { return }
            if let data { self.buffer.append(data) }
            do {
                if let result = try PinnedMCPHTTPClient.parse(self.buffer, ended: ended || error != nil, responseID: responseID) { self.finish(.success(result)) }
                else if error != nil { self.finish(.failure(IntegrationFailure.connectorUnavailable)) }
                else { self.receive(responseID: responseID) }
            } catch { self.finish(.failure(error)) }
        }
    }
    func finish(_ result: Result<PinnedMCPHTTPResponse, any Error>) {
        let continuation = state.withLock { value in
            guard !value.finished else { return nil as CheckedContinuation<PinnedMCPHTTPResponse, any Error>? }
            value.finished = true; let continuation = value.continuation; value.continuation = nil; return continuation
        }
        connection.cancel(); continuation?.resume(with: result)
    }
}
