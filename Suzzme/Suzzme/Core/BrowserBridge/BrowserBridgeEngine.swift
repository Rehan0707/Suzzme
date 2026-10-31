import Foundation
import CryptoKit
import CoreFoundation

/// Transport-only credentials. Provider accounts and permissions remain in IntegrationGateway.
struct BrowserPairing: Codable, Sendable, Equatable {
    let id: String
    let extensionID: String
    let secret: Data
}
protocol BrowserPairingVault: Sendable {
    func load() async throws -> [BrowserPairing]
    func save(_ records: [BrowserPairing]) async throws
}
struct BrowserBridgeDelivery: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case github, connection, invalidate }
    let kind: Kind
    let pairingID: String
    let taskID: String
    let contextID: String
    let version: Int
    var service: String? = "github"
    let repository: String?
}
struct BrowserBridgeReply: Sendable {
    let data: Data
    let delivery: BrowserBridgeDelivery?
}

/// No tools, page text, model calls, provider tokens or action authorization exist here.
/// One-use challenges bind the literal payload bytes, extension, pairing, session and task.
actor BrowserBridgeEngine {
    static let maximumFrame = 65_536
    private let vault: any BrowserPairingVault
    private let extensions: Set<String>
    private var approval: (extensionID: String, digest: Data, expiry: Date)?
    private var attempts = 0
    private var revision = 0
    private var busy = false
    private struct Challenge {
        let pairingID: String; let extensionID: String; let taskID: String
        let nonce: String; let expires: Int
    }
    private var challenges: [String: Challenge] = [:]
    private var replay: [String: Date] = [:]
    private var contexts: [String: (version: Int, task: String, expiry: Date)] = [:]
    init(vault: any BrowserPairingVault, extensionIDs: Set<String>) {
        self.vault = vault; self.extensions = extensionIDs
    }
    static func encoded(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func decoded(_ value: String) -> Data? {
        guard !value.isEmpty, value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }),
              let data = Data(base64Encoded: value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + String(repeating: "=", count: (4 - value.count % 4) % 4)), encoded(data) == value else { return nil }
        return data
    }
    static func validExtension(_ value: String) -> Bool { value.count == 32 && value.utf8.allSatisfy { (97...112).contains($0) } }
    static func validID(_ value: String) -> Bool {
        guard value.count == 36, UUID(uuidString: value) != nil else { return false }
        let bytes = Array(value.lowercased().utf8)
        return (49...53).contains(bytes[14]) && [56, 57, 97, 98].contains(bytes[19])
    }
    private static func secret() -> Data {
        // SystemRandomNumberGenerator is backed by the platform CSPRNG.
        var generator = SystemRandomNumberGenerator()
        return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
    func approve(extensionID: String, now: Date = .now) throws -> String {
        guard !busy, extensions.contains(extensionID), Self.validExtension(extensionID) else { throw BridgeFailure.unavailable }
        let token = Self.secret()
        approval = (extensionID, Data(SHA256.hash(data: token)), now.addingTimeInterval(120))
        attempts = 0
        return Self.encoded(token)
    }
    func revoke() async throws {
        guard !busy else { throw BridgeFailure.unavailable }
        busy = true; defer { busy = false }
        revision += 1; approval = nil; challenges.removeAll(); contexts.removeAll(); replay.removeAll()
        try await vault.save([])
    }
    func permits(_ delivery: BrowserBridgeDelivery) async -> Bool {
        guard !busy, let context = contexts[delivery.pairingID + ":" + delivery.contextID],
              context.task == delivery.taskID, context.version == delivery.version, context.expiry > .now,
              let records = try? await vault.load() else { return false }
        return records.contains { $0.id == delivery.pairingID } && contexts[delivery.pairingID + ":" + delivery.contextID] != nil
    }
    func exchange(_ data: Data, peerExtension: String, now: Date = .now) async -> BrowserBridgeReply {
        var requestID = ""
        do {
            try Task.checkCancellation()
            guard !busy, data.count <= Self.maximumFrame, extensions.contains(peerExtension), Self.validExtension(peerExtension),
                  let frame = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  number(frame["protocolVersion"]) == 1,
                  let id = frame["requestID"] as? String, Self.validID(id),
                  let task = frame["taskID"] as? String, Self.validID(task),
                  frame["extensionID"] as? String == peerExtension, let method = frame["method"] as? String else { throw BridgeFailure.invalid }
            requestID = id
            // Serialize across vault awaits: revocation, pairing and authentication cannot interleave.
            busy = true; defer { busy = false }
            replay = replay.filter { $0.value > now }
            challenges = challenges.filter { $0.value.expires > Int(now.timeIntervalSince1970) }
            contexts = contexts.filter { $0.value.expiry > now }
            guard replay[id] == nil, replay.count < 512 else { throw BridgeFailure.replay }
            replay[id] = now.addingTimeInterval(180)
            let currentRevision = revision
            let records = try await vault.load()
            try Task.checkCancellation()
            guard currentRevision == revision, records.count <= 4,
                  records.allSatisfy({ Self.validID($0.id) && Self.validExtension($0.extensionID) && $0.secret.count == 32 }) else { throw BridgeFailure.unavailable }
            if method == "pairing.request" {
                guard keys(frame, ["protocolVersion", "requestID", "taskID", "extensionID", "method", "payload"]),
                      let payload = frame["payload"] as? [String: Any], keys(payload, ["pairingToken", "clientNonce"]),
                      secretValue(payload["clientNonce"]) != nil else { throw BridgeFailure.invalid }
                attempts += 1
                guard attempts <= 5, let approved = approval, approved.extensionID == peerExtension, approved.expiry > now,
                      let token = secretValue(payload["pairingToken"]),
                      Data(SHA256.hash(data: token)) == approved.digest else { throw BridgeFailure.pairing }
                approval = nil // burn before persistence; failure requires explicit new approval
                let record = BrowserPairing(id: UUID().uuidString.lowercased(), extensionID: peerExtension, secret: Self.secret())
                let updated = records.filter { $0.extensionID != peerExtension } + [record]
                guard updated.count <= 4 else { throw BridgeFailure.unavailable }
                try await vault.save(updated)
                return try reply(id, payload: ["approved": true, "pairingID": record.id, "pairingCredential": Self.encoded(record.secret), "extensionID": peerExtension])
            }
            if method == "session.hello" {
                guard keys(frame, ["protocolVersion", "requestID", "taskID", "extensionID", "method", "payload"]),
                      let payload = frame["payload"] as? [String: Any], keys(payload, ["pairingID", "clientNonce"]),
                      let pairingID = payload["pairingID"] as? String, let client = payload["clientNonce"] as? String,
                      secretValue(client) != nil, let pair = records.first(where: { $0.id == pairingID && $0.extensionID == peerExtension }), challenges.count < 128 else { throw BridgeFailure.authentication }
                let session = UUID().uuidString.lowercased(), nonce = Self.encoded(Self.secret()), expiry = Int(now.timeIntervalSince1970) + 8
                challenges[session] = Challenge(pairingID: pairingID, extensionID: peerExtension, taskID: task, nonce: nonce, expires: expiry)
                let transcript = ["suzzme-browser-server-v1", peerExtension, pairingID, id, client, session, nonce, String(expiry)].joined(separator: "\n")
                return try reply(id, payload: ["sessionID": session, "serverNonce": nonce, "expiresAt": expiry, "proof": mac(transcript, pair.secret)])
            }
            guard ["github.connection", "integration.connection", "context.invalidate"].contains(method),
                  keys(frame, ["protocolVersion", "requestID", "taskID", "extensionID", "method", "pairingID", "sessionID", "serverNonce", "payloadBytes", "authentication"]),
                  let pairingID = frame["pairingID"] as? String, let session = frame["sessionID"] as? String,
                  let nonce = frame["serverNonce"] as? String, let bytes = frame["payloadBytes"] as? String,
                  let authentication = frame["authentication"] as? String, let signature = Self.decoded(authentication), signature.count == 32,
                  let challenge = challenges.removeValue(forKey: session), challenge.expires > Int(now.timeIntervalSince1970),
                  challenge.pairingID == pairingID, challenge.extensionID == peerExtension, challenge.taskID == task, challenge.nonce == nonce,
                  let pair = records.first(where: { $0.id == pairingID && $0.extensionID == peerExtension }) else { throw BridgeFailure.authentication }
            let transcript = ["suzzme-browser-request-v1", "1", peerExtension, pairingID, session, nonce, id, task, method, bytes].joined(separator: "\n")
            guard HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: Data(transcript.utf8), using: SymmetricKey(data: pair.secret)),
                  let decoded = Self.decoded(bytes), decoded.count <= 4096,
                  let payload = try JSONSerialization.jsonObject(with: decoded) as? [String: Any],
                  let contextID = payload["contextID"] as? String, Self.validID(contextID),
                  let version = number(payload["contextVersion"]), version >= 1, version <= 9_007_199_254_740_991 else { throw BridgeFailure.invalid }
            let contextKey = pairingID + ":" + contextID
            var repository: String?
            var service: String?
            if method == "github.connection" || method == "integration.connection" {
                let allowedServices: Set<String> = ["github", "linkedin", "notion", "slack"]
                if method == "github.connection" {
                guard keys(payload, ["contextID", "contextVersion", "capturedAt", "repository"]),
                      let time = payload["capturedAt"] as? Double, time.isFinite, time <= now.timeIntervalSince1970, now.timeIntervalSince1970 - time <= 30,
                      let name = payload["repository"] as? String, canonicalRepository(name),
                      contexts[contextKey] == nil, contexts.count < 128 else { throw BridgeFailure.invalid }
                repository = name
                    service = "github"
                } else {
                    guard keys(payload, ["contextID", "contextVersion", "capturedAt", "service"]),
                          let time = payload["capturedAt"] as? Double, time.isFinite, time <= now.timeIntervalSince1970, now.timeIntervalSince1970 - time <= 30,
                          let requestedService = payload["service"] as? String,
                          allowedServices.contains(requestedService), contexts[contextKey] == nil, contexts.count < 128 else { throw BridgeFailure.invalid }
                    service = requestedService
                }
                contexts[contextKey] = (version, task, now.addingTimeInterval(180)) // tombstone outlives request lease
            } else {
                guard keys(payload, ["contextID", "contextVersion", "reason"]),
                      let reason = payload["reason"] as? String, ["navigation", "tab_closed", "user", "expired", "replaced"].contains(reason),
                      let owned = contexts[contextKey], owned.version == version, owned.task == task else { throw BridgeFailure.invalid }
                // Retain tombstone: a dismissed request cannot be reopened with new IDs.
            }
            try Task.checkCancellation()
            let accepted: [String: Any] = ["accepted": true, "contextID": contextID, "contextVersion": version,
                "proof": mac(["suzzme-browser-response-v1", session, id, method, "true", contextID, String(version)].joined(separator: "\n"), pair.secret)]
            let kind: BrowserBridgeDelivery.Kind = method == "context.invalidate" ? .invalidate : method == "github.connection" ? .github : .connection
            return try reply(id, payload: accepted, delivery: .init(kind: kind,
                pairingID: pairingID, taskID: task, contextID: contextID, version: version, service: service, repository: repository))
        } catch {
            let code = (error as? BridgeFailure)?.rawValue ?? (error is CancellationError ? "cancelled" : "unavailable")
            let failure: [String: Any] = ["protocolVersion": 1, "requestID": requestID, "ok": false, "error": ["code": code]]
            return BrowserBridgeReply(data: (try? JSONSerialization.data(withJSONObject: failure)) ?? Data(), delivery: nil)
        }
    }
    private func canonicalRepository(_ value: String) -> Bool {
        guard value.utf8.count <= 140 else { return false }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0) } }
    }
    private func number(_ value: Any?) -> Int? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite,
              value.doubleValue.rounded() == value.doubleValue, abs(value.doubleValue) <= 9_007_199_254_740_991 else { return nil }
        return value.intValue
    }
    private func keys(_ value: [String: Any], _ expected: Set<String>) -> Bool { Set(value.keys) == expected }
    private func secretValue(_ value: Any?) -> Data? { guard let text = value as? String, let data = Self.decoded(text), data.count == 32 else { return nil }; return data }
    private func mac(_ text: String, _ secret: Data) -> String { Self.encoded(Data(HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: SymmetricKey(data: secret)))) }
    private func reply(_ id: String, payload: [String: Any], delivery: BrowserBridgeDelivery? = nil) throws -> BrowserBridgeReply {
        .init(data: try JSONSerialization.data(withJSONObject: ["protocolVersion": 1, "requestID": id, "ok": true, "payload": payload]), delivery: delivery)
    }
}
enum BridgeFailure: String, Error { case unavailable, invalid, replay, pairing, authentication }
