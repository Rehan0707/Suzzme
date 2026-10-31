import Foundation
import Darwin

// Foundation does not mark NSXPCConnection Sendable. These immutable holders
// retain already configured/resumed connections only; callbacks never mutate them.
private final class ConnectionLifetime: @unchecked Sendable {
    private let connection: NSXPCConnection
    init(_ connection: NSXPCConnection) { self.connection = connection }
}
@main struct NativeMessagingHost {
    static func main() {
        // One sendNativeMessage → one bounded exchange. Process exit bounds all XPC waits.
        alarm(5)
        do {
            guard CommandLine.arguments.count >= 2 else { throw BridgeFailure.invalid }
            let origin = CommandLine.arguments[1]
            let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            guard let bundle = Bundle(url: executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()) else { throw BridgeFailure.unavailable }
            let config = try BrowserBridgeConfiguration.load(bundle: bundle, verifyIdentity: BrowserBridgeConfiguration.hostID)
            guard origin.hasPrefix("chrome-extension://"), origin.hasSuffix("/") else { throw BridgeFailure.authentication }
            let extensionID = String(origin.dropFirst("chrome-extension://".count).dropLast())
            guard config.extensionIDs.contains(extensionID), BrowserBridgeEngine.validExtension(extensionID) else { throw BridgeFailure.authentication }
            let data = try NativeFrame.read(fd: STDIN_FILENO, deadline: .now.addingTimeInterval(4))
            let broker = NSXPCConnection(machServiceName: config.hostService)
            broker.setCodeSigningRequirement(config.requirement(BrowserBridgeConfiguration.brokerID))
            broker.remoteObjectInterface = NSXPCInterface(with: BrowserEndpointLookup.self); broker.resume()
            guard let lookup = broker.remoteObjectProxyWithErrorHandler({ _ in _exit(1) }) as? BrowserEndpointLookup else { throw BridgeFailure.unavailable }
            let brokerLifetime = ConnectionLifetime(broker)
            lookup.endpoint { endpoint in
                guard let endpoint else { _exit(1) }
                let app = NSXPCConnection(listenerEndpoint: endpoint)
                app.setCodeSigningRequirement(config.requirement(BrowserBridgeConfiguration.appID))
                app.remoteObjectInterface = NSXPCInterface(with: BrowserMessageExchange.self); app.resume()
                guard let remote = app.remoteObjectProxyWithErrorHandler({ _ in _exit(1) }) as? BrowserMessageExchange else { _exit(1) }
                let appLifetime = ConnectionLifetime(app)
                remote.exchange(data, origin: extensionID) { response in
                    do { try NativeFrame.write(response, fd: STDOUT_FILENO) } catch { _exit(1) }
                    // Keep connections alive until the response has been emitted.
                    withExtendedLifetime((appLifetime, brokerLifetime)) { _exit(0) }
                }
            }
            withExtendedLifetime(broker) { RunLoop.current.run() }
        } catch { _exit(1) } // No input, credentials or error bodies in stdout/stderr.
    }
}
