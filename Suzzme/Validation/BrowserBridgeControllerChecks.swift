import Foundation

// Appended to a disposable copy of the production controller. No test hooks ship.
extension MacBrowserBridgeController {
    @MainActor static func acceptanceChecks() async -> Int {
        var passed = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); passed += 1 }
        let bridge = MacBrowserBridgeController()
        let first = bridge.connectionEpoch
        bridge.finishRegistration(accepted: true, epoch: first)
        check(bridge.isReady, "current registration makes the helper ready")
        bridge.finishRegistration(accepted: false, epoch: UUID())
        check(bridge.isReady, "old registration failure cannot disable the current helper")
        bridge.pairingCode = "test-only-pairing-display"
        bridge.connectionLost(epoch: UUID())
        check(bridge.isReady && bridge.pairingCode != nil, "old disconnection cannot retire current pairing")
        bridge.connectionLost(epoch: first)
        check(!bridge.isReady && bridge.pairingCode == nil, "current disconnect retires readiness and pairing display")
        bridge.finishRegistration(accepted: true, epoch: first)
        check(!bridge.isReady, "delayed registration cannot revive a disconnected helper")
        let current = bridge.connectionEpoch
        bridge.finishRegistration(accepted: false, epoch: current)
        check(!bridge.isReady && bridge.status == "Browser helper unavailable.", "current failed registration is truthful")

        let store = HandoffMetadata(), credentials = HandoffCredentials(), provider = HandoffGitHub()
        let integrations = IntegrationController(gateway: IntegrationGateway(store: store, credentials: credentials, github: provider))
        bridge.integrations = integrations
        let request = BrowserBridgeDelivery(kind: .github, pairingID: "pairing-one", taskID: "task-one", contextID: "context-one", version: 1, repository: "owner/repo")
        check(!bridge.deliver(request), "unready native helper cannot invoke Presence")
        bridge.finishRegistration(accepted: true, epoch: current)
        check(bridge.deliver(request), "ready delivery uses the existing GitHub route")
        let firstRequest = integrations.browserHandoff.request?.id
        check(firstRequest != nil && integrations.browserHandoff.request?.repository == "owner/repo", "canonical repository reaches existing request owner")
        let secretLoads = await credentials.loads, secretSaves = await credentials.saves
        let providerCalls = await provider.calls, accountSaves = await store.saves
        check(secretLoads == 0 && secretSaves == 0, "native handoff cannot obtain or grant account credentials")
        check(providerCalls == 0 && accountSaves == 0, "native handoff cannot call a provider or create accounts")
        let other = BrowserBridgeDelivery(kind: .invalidate, pairingID: "other-pairing", taskID: request.taskID, contextID: request.contextID, version: 1, repository: nil)
        check(bridge.deliver(other) && integrations.browserHandoff.request?.id == firstRequest, "another pairing cannot dismiss an owned request")
        let next = BrowserBridgeDelivery(kind: .github, pairingID: "pairing-one", taskID: "task-two", contextID: "context-two", version: 1, repository: "second/repo")
        check(bridge.deliver(next), "a replacement request can be presented")
        let nextRequest = integrations.browserHandoff.request?.id
        check(nextRequest != nil && nextRequest != firstRequest, "replacement has a distinct UI request owner")
        let retired = BrowserBridgeDelivery(kind: .invalidate, pairingID: request.pairingID, taskID: request.taskID, contextID: request.contextID, version: 1, repository: nil)
        check(bridge.deliver(retired) && integrations.browserHandoff.request?.id == nextRequest, "retired context callback cannot dismiss its replacement")
        bridge.connectionLost(epoch: first)
        check(bridge.isReady && integrations.browserHandoff.request?.id == nextRequest, "old IPC disconnect cannot retire the replacement")
        let invalidate = BrowserBridgeDelivery(kind: .invalidate, pairingID: next.pairingID, taskID: next.taskID, contextID: next.contextID, version: 1, repository: nil)
        check(bridge.deliver(invalidate) && integrations.browserHandoff.request == nil, "current authenticated invalidation dismisses its own request")
        check(!bridge.deliver(next), "a dismissed repository request remains dismissed")
        let fresh = BrowserBridgeDelivery(kind: .github, pairingID: "pairing-one", taskID: "task-three", contextID: "context-three", version: 1, repository: "third/repo")
        check(bridge.deliver(fresh), "a fresh repository request can use the same existing controller")
        bridge.stop()
        check(!bridge.isReady && integrations.browserHandoff.request == nil, "stop clears readiness and owned pending request")
        bridge.finishRegistration(accepted: true, epoch: current)
        check(!bridge.isReady, "registration callback after stop cannot reopen the helper")
        print("Browser native controller checks: \(passed) passed / 0 failed. Disposable controller copy; no signed IPC acceptance.")
        return passed
    }
}
