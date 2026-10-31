import Foundation
import CryptoKit

/// Explicit resource identifiers only. OAuth credentials stay in GoogleSignIn's
/// existing Keychain-backed owner; no new account or token database is created.
enum GoogleProviderScopeStore {
    static func load(_ service: IntegrationID, accountID: String?) -> [String: String] {
        if let accountID, let data = UserDefaults.standard.data(forKey: selectedKey(service, accountID)),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["enabled"] as? Bool == true, let resources = object["resources"] as? [String: String] { return resources }
        guard let accountID, let recipe = ProviderReadRecipe.find(service), recipe.googleScope != nil,
              let value = UserDefaults.standard.dictionary(forKey: key(service, accountID: accountID)) as? [String: String], recipe.validates(value) else { return [:] }
        return value
    }
    static func save(_ value: [String: String], service: IntegrationID, accountID: String) throws {
        guard let recipe = ProviderReadRecipe.find(service), recipe.googleScope != nil, recipe.validates(value) else { throw IntegrationFailure.invalidConfiguration }
        UserDefaults.standard.set(value, forKey: key(service, accountID: accountID))
    }
    static func remove(_ service: IntegrationID, accountID: String) { UserDefaults.standard.removeObject(forKey: key(service, accountID: accountID)) }
    private static func selectedKey(_ service: IntegrationID, _ accountID: String) -> String {
        let hash = SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined()
        return "suzzme.integrations.google.selected." + hash + "." + service.rawValue
    }
    private static func key(_ service: IntegrationID, accountID: String) -> String {
        let namespace = SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined()
        return "suzzme.integrations.google.scope." + namespace + "." + service.rawValue
    }
}
