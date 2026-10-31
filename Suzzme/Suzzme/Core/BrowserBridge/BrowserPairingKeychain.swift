import Foundation
import Security

actor BrowserPairingKeychain: BrowserPairingVault {
    private let service = "rehan.Suzzme.browser-pairing.v1"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "approved-extensions", kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: false]
    }
    func load() throws -> [BrowserPairing] {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = result as? Data, data.count <= 4096 else { throw BridgeFailure.unavailable }
        return try JSONDecoder().decode([BrowserPairing].self, from: data)
    }
    func save(_ records: [BrowserPairing]) throws {
        guard records.count <= 4 else { throw BridgeFailure.invalid }
        if records.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw BridgeFailure.unavailable }
            return
        }
        let data = try JSONEncoder().encode(records)
        let attributes = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as [String: Any]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw BridgeFailure.unavailable }
    }
}
