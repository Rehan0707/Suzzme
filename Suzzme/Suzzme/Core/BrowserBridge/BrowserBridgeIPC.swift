#if os(macOS)
import Foundation
import Security

@objc protocol BrowserEndpointRegistration {
    func register(_ endpoint: NSXPCListenerEndpoint, reply: @escaping @Sendable (Bool) -> Void)
}
@objc protocol BrowserEndpointLookup {
    func endpoint(reply: @escaping @Sendable (NSXPCListenerEndpoint?) -> Void)
}
@objc protocol BrowserMessageExchange {
    func exchange(_ message: Data, origin: String, reply: @escaping @Sendable (Data) -> Void)
}
struct BrowserBridgeConfiguration: Codable, Sendable {
    let teamID: String
    let appGroup: String
    let extensionIDs: [String]
    static let appID = "rehan.Suzzme"
    static let hostID = "rehan.Suzzme.BrowserHost"
    static let brokerID = "rehan.Suzzme.BrowserBroker"
    var valid: Bool {
        teamID.count == 10 && teamID.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) }
        && appGroup.hasPrefix(teamID + ".") && appGroup.utf8.count <= 160
        && appGroup.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [46, 45].contains($0) }
        && !extensionIDs.isEmpty && extensionIDs.count <= 4 && extensionIDs.allSatisfy(BrowserBridgeEngine.validExtension)
    }
    var registrationService: String { appGroup + ".browser.registration" }
    var hostService: String { appGroup + ".browser.host" }
    func requirement(_ identifier: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamID)\""
    }
    static func load(bundle: Bundle = .main, verifyIdentity: String) throws -> Self {
        guard let url = bundle.url(forResource: "BrowserBridge", withExtension: "json"),
              let data = try? Data(contentsOf: url), data.count <= 4096 else { throw BridgeFailure.unavailable }
        let configuration = try JSONDecoder().decode(Self.self, from: data)
        guard configuration.valid else { throw BridgeFailure.unavailable }
        var ownCode: SecCode?
        guard SecCodeCopySelf([], &ownCode) == errSecSuccess, let ownCode else { throw BridgeFailure.unavailable }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(configuration.requirement(verifyIdentity) as CFString, [], &requirement) == errSecSuccess,
              let requirement, SecCodeCheckValidity(ownCode, [], requirement) == errSecSuccess else { throw BridgeFailure.unavailable }
        return configuration
    }
}
#endif
