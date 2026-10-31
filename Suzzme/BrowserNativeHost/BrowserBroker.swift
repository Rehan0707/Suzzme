import Foundation
import os

/// XPC delegates execute on Foundation queues. The only mutable state is guarded
/// by OSAllocatedUnfairLock; no lock is held during an XPC call or across an await.
final class EndpointRegistry: @unchecked Sendable {
    private let endpointLock = OSAllocatedUnfairLock<(UUID, NSXPCListenerEndpoint)?>(initialState: nil)
    func set(_ endpoint: NSXPCListenerEndpoint, owner: UUID) { endpointLock.withLock { $0 = (owner, endpoint) } }
    func clear(owner: UUID) { endpointLock.withLock { if $0?.0 == owner { $0 = nil } } }
    func get() -> NSXPCListenerEndpoint? { endpointLock.withLock { $0?.1 } }
}
final class Registration: NSObject, BrowserEndpointRegistration {
    let registry: EndpointRegistry; let owner = UUID()
    init(_ registry: EndpointRegistry) { self.registry = registry }
    func register(_ endpoint: NSXPCListenerEndpoint, reply: @escaping @Sendable (Bool) -> Void) {
        registry.set(endpoint, owner: owner); reply(true)
    }
}
final class Lookup: NSObject, BrowserEndpointLookup {
    let registry: EndpointRegistry
    init(_ registry: EndpointRegistry) { self.registry = registry }
    func endpoint(reply: @escaping @Sendable (NSXPCListenerEndpoint?) -> Void) { reply(registry.get()) }
}
final class BrokerDelegate: NSObject, NSXPCListenerDelegate {
    let registry: EndpointRegistry; let registration: Bool
    init(_ registry: EndpointRegistry, registration: Bool) { self.registry = registry; self.registration = registration }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if registration {
            let object = Registration(registry)
            connection.exportedInterface = NSXPCInterface(with: BrowserEndpointRegistration.self)
            connection.exportedObject = object
            let owner = object.owner, registry = registry
            connection.invalidationHandler = { registry.clear(owner: owner) }
        } else {
            connection.exportedInterface = NSXPCInterface(with: BrowserEndpointLookup.self)
            connection.exportedObject = Lookup(registry)
        }
        connection.resume()
        return true
    }
}
@main struct BrowserBroker {
    static func main() throws {
        // Executable is embedded in Contents/MacOS; Bundle.main for a CLI is not the enclosing app.
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        guard let bundle = Bundle(url: executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()) else { throw BridgeFailure.unavailable }
        let configuration = try BrowserBridgeConfiguration.load(bundle: bundle, verifyIdentity: BrowserBridgeConfiguration.brokerID)
        let registry = EndpointRegistry()
        let registrationDelegate = BrokerDelegate(registry, registration: true), hostDelegate = BrokerDelegate(registry, registration: false)
        let registration = NSXPCListener(machServiceName: configuration.registrationService), host = NSXPCListener(machServiceName: configuration.hostService)
        registration.setConnectionCodeSigningRequirement(configuration.requirement(BrowserBridgeConfiguration.appID))
        host.setConnectionCodeSigningRequirement(configuration.requirement(BrowserBridgeConfiguration.hostID))
        registration.delegate = registrationDelegate; host.delegate = hostDelegate
        registration.resume(); host.resume()
        withExtendedLifetime((registrationDelegate, hostDelegate, registration, host)) { RunLoop.current.run() }
    }
}
