#if os(macOS)
import AppKit
import Observation
import ServiceManagement
import os

private final class BrowserExchangeReceiver: NSObject, BrowserMessageExchange, Sendable {
    private struct State { var started = false; var cancelled = false; var task: Task<Void, Never>? }
    private let state = OSAllocatedUnfairLock(initialState: State())
    func cancel() {
        let task = state.withLock { value in value.cancelled = true; let task = value.task; value.task = nil; return task }
        task?.cancel()
    }
    let engine: BrowserBridgeEngine
    let deliver: @MainActor @Sendable (BrowserBridgeDelivery) -> Bool
    init(engine: BrowserBridgeEngine, deliver: @escaping @MainActor @Sendable (BrowserBridgeDelivery) -> Bool) {
        self.engine = engine; self.deliver = deliver
    }
    func exchange(_ message: Data, origin: String, reply: @escaping @Sendable (Data) -> Void) {
        let admitted = state.withLock { value in
            guard !value.started, !value.cancelled else { return false }
            value.started = true; return true
        }
        guard admitted else { reply(Data()); return }
        let engine = engine, deliver = deliver, state = state
        let task = Task {
            defer { state.withLock { $0.task = nil } }
            let result = await engine.exchange(message, peerExtension: origin)
            if let delivery = result.delivery {
                guard !Task.isCancelled, await engine.permits(delivery), !Task.isCancelled, await deliver(delivery) else {
                    // Never acknowledge success when the app cannot route the request.
                    let failure = (try? JSONSerialization.jsonObject(with: result.data)) as? [String: Any]
                    let data = try? JSONSerialization.data(withJSONObject: ["protocolVersion": 1, "requestID": failure?["requestID"] as? String ?? "", "ok": false, "error": ["code": "unavailable"]])
                    reply(data ?? Data()); return
                }
            }
            reply(result.data)
        }
        state.withLock { value in
            if value.cancelled { task.cancel() } else { value.task = task }
        }
    }
}
private final class BrowserAppListener: NSObject, NSXPCListenerDelegate {
    let receiver: BrowserExchangeReceiver
    init(_ receiver: BrowserExchangeReceiver) { self.receiver = receiver }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: BrowserMessageExchange.self)
        let receiver = BrowserExchangeReceiver(engine: receiver.engine, deliver: receiver.deliver)
        connection.exportedObject = receiver
        connection.invalidationHandler = { receiver.cancel() }
        connection.interruptionHandler = { receiver.cancel() }
        connection.resume()
        return true // Listener enforces the designated code requirement before this delegate runs.
    }
}
@MainActor @Observable final class MacBrowserBridgeController {
    private(set) var status = "Signed browser bridge configuration is required."
    private(set) var pairingCode: String?
    private(set) var isReady = false
    private(set) var allowedExtensions: [String] = []
    private var engine: BrowserBridgeEngine?
    private var listener: NSXPCListener?
    private var delegate: BrowserAppListener?
    private var broker: NSXPCConnection?
    private weak var integrations: IntegrationController?
    private var expiry: Task<Void, Never>?
    private var pairingExpiry: Task<Void, Never>?
    private var connectionEpoch = UUID()
    private var requestOwner: (pairing: String, context: String, version: Int, request: UUID)?
    private let service = SMAppService.agent(plistName: "rehan.Suzzme.BrowserBroker.plist")
    func prepare(integrations: IntegrationController) {
        self.integrations = integrations
        guard engine == nil else { return }
        guard let configuration = try? BrowserBridgeConfiguration.load(verifyIdentity: BrowserBridgeConfiguration.appID) else { return }
        allowedExtensions = configuration.extensionIDs
        engine = BrowserBridgeEngine(vault: BrowserPairingKeychain(), extensionIDs: Set(configuration.extensionIDs))
        if service.status == .enabled { start(configuration) }
        else { status = "Enable the browser helper to pair this Mac." }
    }
    func enable() async {
        guard let configuration = try? BrowserBridgeConfiguration.load(verifyIdentity: BrowserBridgeConfiguration.appID), engine != nil else { return }
        do {
            try service.register()
            guard service.status == .enabled else { status = "Approve Suzzme’s browser helper in Login Items, then try again."; return }
            start(configuration)
        } catch { status = "The browser helper could not be enabled. Check Login Items and the signed build configuration." }
    }
    private func start(_ configuration: BrowserBridgeConfiguration) {
        guard broker == nil, let engine else { return }
        let epoch = UUID(); connectionEpoch = epoch
        let receiver = BrowserExchangeReceiver(engine: engine) { [weak self] delivery in
            guard self?.connectionEpoch == epoch else { return false }
            return self?.deliver(delivery) ?? false
        }
        let delegate = BrowserAppListener(receiver)
        let listener = NSXPCListener.anonymous()
        listener.setConnectionCodeSigningRequirement(configuration.requirement(BrowserBridgeConfiguration.hostID))
        listener.delegate = delegate; listener.resume()
        self.listener = listener; self.delegate = delegate
        let broker = NSXPCConnection(machServiceName: configuration.registrationService)
        broker.setCodeSigningRequirement(configuration.requirement(BrowserBridgeConfiguration.brokerID))
        broker.remoteObjectInterface = NSXPCInterface(with: BrowserEndpointRegistration.self)
        broker.invalidationHandler = { [weak self] in Task { @MainActor in self?.connectionLost(epoch: epoch) } }
        broker.interruptionHandler = { [weak self] in Task { @MainActor in self?.connectionLost(epoch: epoch) } }
        broker.resume(); self.broker = broker
        guard let remote = broker.remoteObjectProxyWithErrorHandler({ [weak self] _ in Task { @MainActor in self?.connectionLost(epoch: epoch) } }) as? BrowserEndpointRegistration else { connectionLost(epoch: epoch); return }
        remote.register(listener.endpoint) { [weak self] accepted in
            Task { @MainActor in
                self?.finishRegistration(accepted: accepted, epoch: epoch)
            }
        }
    }
    private func finishRegistration(accepted: Bool, epoch: UUID) {
        guard connectionEpoch == epoch else { return }
        isReady = accepted
        status = accepted ? "Browser helper ready. Pair only your installed extension." : "Browser helper unavailable."
    }
    private func connectionLost(epoch: UUID? = nil) {
        if let epoch, epoch != connectionEpoch { return }
        connectionEpoch = UUID()
        isReady = false; status = "Browser helper disconnected. Re-enable it to reconnect."
        pairingExpiry?.cancel(); pairingCode = nil
        broker?.invalidationHandler = nil; broker?.interruptionHandler = nil; broker?.invalidate(); broker = nil
        listener?.invalidate(); listener = nil; delegate = nil
        retireRequest()
    }
    func approve(extensionID: String) async {
        guard isReady, let engine else { return }
        let epoch = connectionEpoch
        do {
            let code = try await engine.approve(extensionID: extensionID)
            guard connectionEpoch == epoch, isReady else { return }
            pairingCode = code
            pairingExpiry?.cancel()
            pairingExpiry = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(120)) } catch { return }
                self?.pairingCode = nil
            }
        } catch {
            guard connectionEpoch == epoch else { return }
            status = "Pairing could not be approved. Try again when the current request finishes."
        }
    }
    func revoke() async {
        guard let engine else { return }
        connectionLost()
        let epoch = connectionEpoch
        do {
            try await engine.revoke()
            guard connectionEpoch == epoch else { return }
            pairingCode = nil; pairingExpiry?.cancel(); retireRequest()
            if let config = try? BrowserBridgeConfiguration.load(verifyIdentity: BrowserBridgeConfiguration.appID) { start(config) }
            status = "All browser pairings revoked. GitHub accounts were unchanged."
        } catch {
            guard connectionEpoch == epoch else { return }
            status = "Pairings could not be revoked. Try again when the current browser operation finishes."
        }
    }
    private func deliver(_ value: BrowserBridgeDelivery) -> Bool {
        guard isReady, let integrations else { return false }
        if value.kind == .invalidate {
            if requestOwner?.pairing == value.pairingID, requestOwner?.context == value.contextID, requestOwner?.version == value.version { retireRequest() }
            return true
        }
        guard let rawService = value.service, let service = IntegrationID(rawValue: rawService),
              let url = BrowserIntegrationRoute.url(for: .requestConnection, service: service, repository: value.repository) else { return false }
        retireRequest()
        integrations.receiveBrowserURL(url)
        guard let request = integrations.browserHandoff.request else { return false }
        requestOwner = (value.pairingID, value.contextID, value.version, request.id)
        expiry = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            self?.retireRequest()
        }
        return true
    }
    private func retireRequest() {
        expiry?.cancel(); expiry = nil
        if let owner = requestOwner, integrations?.browserHandoff.request?.id == owner.request { integrations?.clearBrowserHandoff() }
        requestOwner = nil
    }
    func stop() {
        pairingExpiry?.cancel(); pairingCode = nil; connectionLost()
    }
}
#endif
