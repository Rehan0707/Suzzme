import Foundation
import CryptoKit
import Darwin
import Security

private actor PairingFixture: BrowserPairingVault {
    var values: [BrowserPairing] = []
    func load() -> [BrowserPairing] { values }
    func save(_ records: [BrowserPairing]) { values = records }
}
@main struct BrowserBridgeChecks {
    static func main() async throws {
        var passed = 0, failed = 0
        func expect(_ value: Bool, _ name: String) {
            if value { passed += 1; print("PASS \(name)") } else { failed += 1; print("FAIL \(name)") }
        }
        let vault = PairingFixture(), ext = String(repeating: "a", count: 32), other = String(repeating: "b", count: 32)
        let engine = BrowserBridgeEngine(vault: vault, extensionIDs: [ext])
        let now = Date.now
        func object(_ data: Data) throws -> [String: Any] { try JSONSerialization.jsonObject(with: data) as! [String: Any] }
        func send(_ frame: [String: Any], origin: String? = nil, time: Date? = nil) async throws -> BrowserBridgeReply {
            await engine.exchange(try JSONSerialization.data(withJSONObject: frame), peerExtension: origin ?? ext, now: time ?? now)
        }
        func envelope(_ method: String, _ payload: [String: Any], task: String = UUID().uuidString.lowercased()) -> [String: Any] {
            ["protocolVersion": 1, "requestID": UUID().uuidString.lowercased(), "taskID": task, "extensionID": ext, "method": method, "payload": payload]
        }
        let nonce = BrowserBridgeEngine.encoded(Data(repeating: 7, count: 32))
        var frame = envelope("pairing.request", ["pairingToken": nonce, "clientNonce": nonce])
        expect(try object(await send(frame).data)["ok"] as? Bool == false, "pairing requires explicit native approval")
        do { _ = try await engine.approve(extensionID: other, now: now); expect(false, "unknown extension approval") }
        catch { expect(true, "unknown extension cannot be approved") }
        let code = try await engine.approve(extensionID: ext, now: now)
        frame = envelope("pairing.request", ["pairingToken": code, "clientNonce": nonce])
        expect(try object(await send(frame, origin: other).data)["ok"] as? Bool == false, "unconfigured origin rejected")
        let paired = try object(await send(frame).data)
        expect(paired["ok"] as? Bool == true, "approved origin pairs")
        let payload = paired["payload"] as! [String: Any], pairingID = payload["pairingID"] as! String
        let secret = BrowserBridgeEngine.decoded(payload["pairingCredential"] as! String)!
        expect(secret.count == 32 && payload["extensionID"] as? String == ext, "pairing secret and extension identity bound")
        expect(try object(await send(frame).data)["ok"] as? Bool == false, "pairing callback replay rejected")
        expect(try object(await send(envelope("pairing.request", ["pairingToken": code, "clientNonce": nonce])).data)["ok"] as? Bool == false, "pairing code is single use")
        let expiryCode = try await engine.approve(extensionID: ext, now: now)
        expect(try object(await send(envelope("pairing.request", ["pairingToken": expiryCode, "clientNonce": nonce]), time: now.addingTimeInterval(121)).data)["ok"] as? Bool == false, "pairing code expires")
        func authenticated(_ method: String, payload: [String: Any], task: String = UUID().uuidString.lowercased()) async throws -> [String: Any] {
            let hello = envelope("session.hello", ["pairingID": pairingID, "clientNonce": nonce], task: task)
            let challenge = try object(await send(hello).data)["payload"] as! [String: Any]
            let transcript = ["suzzme-browser-server-v1", ext, pairingID, hello["requestID"] as! String, nonce,
                challenge["sessionID"] as! String, challenge["serverNonce"] as! String, String(challenge["expiresAt"] as! Int)].joined(separator: "\n")
            expect(HMAC<SHA256>.isValidAuthenticationCode(BrowserBridgeEngine.decoded(challenge["proof"] as! String)!, authenticating: Data(transcript.utf8), using: SymmetricKey(data: secret)), "native challenge proves pairing")
            var request: [String: Any] = ["protocolVersion": 1, "extensionID": ext, "pairingID": pairingID,
                "sessionID": challenge["sessionID"]!, "serverNonce": challenge["serverNonce"]!, "requestID": UUID().uuidString.lowercased(),
                "taskID": task, "method": method, "payloadBytes": BrowserBridgeEngine.encoded(try JSONSerialization.data(withJSONObject: payload))]
            let text = ["suzzme-browser-request-v1", "1", ext, pairingID, request["sessionID"] as! String, request["serverNonce"] as! String,
                request["requestID"] as! String, task, method, request["payloadBytes"] as! String].joined(separator: "\n")
            request["authentication"] = BrowserBridgeEngine.encoded(Data(HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: SymmetricKey(data: secret))))
            return request
        }
        let context = UUID().uuidString.lowercased(), task = UUID().uuidString.lowercased()
        let resource: [String: Any] = ["contextID": context, "contextVersion": 1, "capturedAt": now.timeIntervalSince1970, "repository": "example/project"]
        var request = try await authenticated("github.connection", payload: resource, task: task)
        let accepted = try await send(request)
        expect(try object(accepted.data)["ok"] as? Bool == true && accepted.delivery?.repository == "example/project", "authenticated metadata reaches typed delivery")
        expect(accepted.delivery?.pairingID == pairingID && accepted.delivery?.taskID == task, "delivery preserves pairing and task ownership")
        expect(await engine.permits(accepted.delivery!), "delivery authorization rechecked")
        let responsePayload = try object(accepted.data)["payload"] as! [String: Any]
        let responseText = ["suzzme-browser-response-v1", request["sessionID"] as! String, request["requestID"] as! String, "github.connection", "true", context, "1"].joined(separator: "\n")
        expect(HMAC<SHA256>.isValidAuthenticationCode(BrowserBridgeEngine.decoded(responsePayload["proof"] as! String)!, authenticating: Data(responseText.utf8), using: SymmetricKey(data: secret)), "acknowledgment authenticates exact accepted context")
        expect(try object(await send(request).data)["ok"] as? Bool == false, "duplicate callback cannot deliver twice")
        request["requestID"] = UUID().uuidString.lowercased()
        expect(try object(await send(request).data)["ok"] as? Bool == false, "challenge cannot be reused with new request ID")
        let reopen = try await authenticated("github.connection", payload: resource, task: task)
        expect(try object(await send(reopen).data)["ok"] as? Bool == false, "dismissed context tombstone prevents reopening")
        var invalidate = try await authenticated("context.invalidate", payload: ["contextID": context, "contextVersion": 1, "reason": "user"])
        expect(try object(await send(invalidate).data)["ok"] as? Bool == false, "other task cannot invalidate context")
        invalidate = try await authenticated("context.invalidate", payload: ["contextID": context, "contextVersion": 1, "reason": "user"], task: task)
        expect(try object(await send(invalidate).data)["ok"] as? Bool == true, "owning task invalidates its context")
        for (label, replacement) in [("private host", "http://localhost"), ("path traversal", "../project"), ("extra path", "example/project/issues/1"), ("encoded path", "example/%2f") ] {
            let bad: [String: Any] = ["contextID": UUID().uuidString.lowercased(), "contextVersion": 1, "capturedAt": now.timeIntervalSince1970, "repository": replacement]
            expect(try object(await send(authenticated("github.connection", payload: bad)).data)["ok"] as? Bool == false, "reject \(label)")
        }
        for age in [-1.0, 31.0] {
            let bad: [String: Any] = ["contextID": UUID().uuidString.lowercased(), "contextVersion": 1, "capturedAt": now.timeIntervalSince1970 - age, "repository": "example/project"]
            expect(try object(await send(authenticated("github.connection", payload: bad)).data)["ok"] as? Bool == false, "reject future or expired browser observation")
        }
        var tampered = try await authenticated("github.connection", payload: resource)
        tampered["payloadBytes"] = BrowserBridgeEngine.encoded(Data("{}".utf8))
        expect(try object(await send(tampered).data)["ok"] as? Bool == false, "payload tampering invalidates HMAC")
        var malformed = envelope("session.hello", ["pairingID": pairingID, "clientNonce": nonce])
        malformed["protocolVersion"] = true
        expect(try object(await send(malformed).data)["ok"] as? Bool == false, "JSON boolean cannot masquerade as protocol version")
        malformed["protocolVersion"] = 2
        expect(try object(await send(malformed).data)["ok"] as? Bool == false, "future protocol rejected")
        malformed["protocolVersion"] = 1; malformed["unexpected"] = "data"
        expect(try object(await send(malformed).data)["ok"] as? Bool == false, "unknown envelope keys rejected")
        let oversized = await engine.exchange(Data(repeating: 32, count: 65_537), peerExtension: ext, now: now)
        expect(try object(oversized.data)["ok"] as? Bool == false, "oversize rejected before JSON decode")
        expect(try object(await engine.exchange(Data("not json".utf8), peerExtension: ext).data)["ok"] as? Bool == false, "malformed JSON rejected")
        let cancelled = Task { await engine.exchange(Data("{}".utf8), peerExtension: ext) }; cancelled.cancel()
        expect(try object(await cancelled.value.data)["ok"] as? Bool == false, "cancellation cannot deliver")
        let pending = try await authenticated("github.connection", payload: resource)
        try await engine.revoke()
        expect(await vault.load().isEmpty, "revocation deletes transport credentials")
        expect(!(await engine.permits(accepted.delivery!)), "revocation retires cached delivery")
        expect(try object(await send(pending).data)["ok"] as? Bool == false, "revocation rejects delayed authenticated callback")
        // Real POSIX framing, using isolated pipes only.
        var pipes: [Int32] = [0, 0]
        guard pipe(&pipes) == 0 else { throw BridgeFailure.unavailable }
        defer { close(pipes[0]); close(pipes[1]) }
        try NativeFrame.write(Data("{}".utf8), fd: pipes[1])
        expect(try NativeFrame.read(fd: pipes[0], deadline: .now.addingTimeInterval(1)) == Data("{}".utf8), "native framing round trip")
        var length = UInt32(65_537)
        _ = withUnsafeBytes(of: &length) { Darwin.write(pipes[1], $0.baseAddress, 4) }
        do { _ = try NativeFrame.read(fd: pipes[0], deadline: .now.addingTimeInterval(1)); expect(false, "oversized frame") }
        catch { expect(true, "native frame size checked before allocation") }
        do { _ = try NativeFrame.read(fd: pipes[0], deadline: .now.addingTimeInterval(0.01)); expect(false, "deadline") }
        catch { expect(true, "silent native input times out") }
        var truncatedPipes: [Int32] = [0, 0]
        guard pipe(&truncatedPipes) == 0 else { throw BridgeFailure.unavailable }
        var truncatedLength = UInt32(4)
        _ = withUnsafeBytes(of: &truncatedLength) { Darwin.write(truncatedPipes[1], $0.baseAddress, 4) }
        _ = Darwin.write(truncatedPipes[1], "x", 1); close(truncatedPipes[1])
        do { _ = try NativeFrame.read(fd: truncatedPipes[0], deadline: .now.addingTimeInterval(1)); expect(false, "truncated frame") }
        catch { expect(true, "truncated native payload rejected") }
        close(truncatedPipes[0])
        let configured = BrowserBridgeConfiguration(teamID: "ABCDEFGHIJ", appGroup: "ABCDEFGHIJ.group.suzzme", extensionIDs: [ext])
        expect(configured.valid, "valid configuration syntax accepted without claiming signing")
        expect(!BrowserBridgeConfiguration(teamID: "", appGroup: "", extensionIDs: []).valid, "missing distribution configuration fails closed")
        expect(!BrowserBridgeConfiguration(teamID: "ABCDEFGHIJ", appGroup: "other.group", extensionIDs: [ext]).valid, "foreign App Group rejected")
        expect(!BrowserBridgeConfiguration(teamID: "ABCDEFGHIJ", appGroup: "ABCDEFGHIJ.group.suzzme", extensionIDs: ["bad"]).valid, "invalid extension identifier rejected")
        for identifier in [BrowserBridgeConfiguration.appID, BrowserBridgeConfiguration.hostID, BrowserBridgeConfiguration.brokerID] {
            var requirement: SecRequirement?
            expect(SecRequirementCreateWithString(configured.requirement(identifier) as CFString, [], &requirement) == errSecSuccess, "installed macOS Security accepts exact peer code requirement")
        }
        do { _ = try BrowserBridgeConfiguration.load(verifyIdentity: BrowserBridgeConfiguration.appID); expect(false, "unsigned identity") }
        catch { expect(true, "unsigned unconfigured harness cannot activate bridge") }
        print("Browser bridge checks: \(passed) passed, \(failed) failed. Transport fixtures, not signed installation acceptance.")
        if failed > 0 { exit(1) }
    }
}
