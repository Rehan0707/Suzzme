import Foundation
import Dispatch
import NIOCore
import NIOSSL
@preconcurrency import Security

/// The supported NIOSSL whole-chain callback delegates certificate and hostname
/// validation to Security.framework. No network fetch or relaxed X.509 policy.
struct ServerTrustConfiguration: Sendable {
    #if WATCHED_TRANSPORT_CONNECTION_TESTS
    private let connectionTestRoot: Data?
    init() { connectionTestRoot = nil }
    init(connectionTestRoot: Data) throws {
        guard !connectionTestRoot.isEmpty, connectionTestRoot.count <= 32_768,
              SecCertificateCreateWithData(nil, connectionTestRoot as CFData) != nil else {
            throw PinnedHTTPError.invalidRequest
        }
        self.connectionTestRoot = connectionTestRoot
    }
    var permitsLoopback: Bool { connectionTestRoot != nil }
    #else
    init() {}
    var permitsLoopback: Bool { false }
    #endif

    func verify(chain: [NIOSSLCertificate], hostname: String, lifetime: RequestLifetime,
                promise: EventLoopPromise<NIOSSLVerificationResult>) {
        guard !lifetime.isFinished, !chain.isEmpty, chain.count <= TransportLimits.certificateCount else {
            promise.succeed(.failed); return
        }
        do {
            var total = 0
            let encoded = try chain.map { certificate -> Data in
                let bytes = try certificate.toDERBytes()
                guard !bytes.isEmpty, bytes.count <= 32_768,
                      total <= TransportLimits.certificateBytes - bytes.count else {
                    throw PinnedHTTPError.tlsVerificationFailed
                }
                total += bytes.count
                return Data(bytes)
            }
            // Security evaluation runs away from the NIO event loop. With
            // network fetching disabled it cannot start AIA/OCSP connections.
            DispatchQueue.global(qos: .utility).async {
                guard !lifetime.isFinished else { promise.succeed(.failed); return }
                let valid = evaluate(encoded, hostname: hostname)
                promise.succeed(valid && !lifetime.isFinished ? .certificateVerified : .failed)
            }
        } catch { promise.succeed(.failed) }
    }

    private func evaluate(_ encoded: [Data], hostname: String) -> Bool {
        let certificates = encoded.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        guard certificates.count == encoded.count else { return false }
        let policy = SecPolicyCreateSSL(true, hostname as CFString)
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(certificates as CFArray, policy, &trust) == errSecSuccess,
              let trust, SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess else { return false }
        #if WATCHED_TRANSPORT_CONNECTION_TESTS
        if let connectionTestRoot {
            guard let root = SecCertificateCreateWithData(nil, connectionTestRoot as CFData),
                  SecTrustSetAnchorCertificates(trust, [root] as CFArray) == errSecSuccess,
                  SecTrustSetAnchorCertificatesOnly(trust, false) == errSecSuccess else { return false }
        }
        #endif
        var error: CFError?
        return SecTrustEvaluateWithError(trust, &error)
    }
}
