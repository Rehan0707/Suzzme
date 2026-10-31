import Foundation
import Security
import OSLog

/// The credential boundary for account integrations. No model or UI
/// projection receives this object or its returned credential.
actor IntegrationCredentialStore: IntegrationCredentialStoring {
    // Keep the established namespace so existing GitHub credentials remain accessible.
    // Every service uses its unique account UUID as the Keychain item key.
    private let service = "rehan.Suzzme.integrations.github"
    private let logger = Logger(subsystem: "rehan.Suzzme", category: "IntegrationCredentials")
    private func unavailable(_ status: OSStatus, operation: String) -> IntegrationFailure {
        logger.error("Secure credential \(operation, privacy: .public) failed (OSStatus \(status, privacy: .public)).")
        return .credentialUnavailable
    }
    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString,
         kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }
    func save(_ secret: String, accountID: UUID) throws {
        guard !secret.isEmpty, secret.utf8.count <= 16_384 else { throw IntegrationFailure.invalidConfiguration }
        let attributes: [String: Any] = [kSecValueData as String: Data(secret.utf8)]
        let status = SecItemUpdate(query(accountID) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(accountID)
            item.merge(attributes) { _, value in value }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw unavailable(added, operation: "save") }
        } else if status != errSecSuccess { throw unavailable(status, operation: "update") }
    }
    func load(accountID: UUID) throws -> String {
        var item = query(accountID)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { throw IntegrationFailure.credentialUnavailable }
        guard status == errSecSuccess else { throw unavailable(status, operation: "load") }
        guard let data = result as? Data, data.count <= 16_384,
              let secret = String(data: data, encoding: .utf8), !secret.isEmpty else { throw IntegrationFailure.credentialUnavailable }
        return secret
    }
    func loadIfPresent(accountID: UUID) throws -> String? {
        var item = query(accountID)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw unavailable(status, operation: "load") }
        guard let data = result as? Data, data.count <= 16_384,
              let secret = String(data: data, encoding: .utf8), !secret.isEmpty else { throw IntegrationFailure.credentialUnavailable }
        return secret
    }
    func remove(accountID: UUID) throws {
        let status = SecItemDelete(query(accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw unavailable(status, operation: "remove") }
    }
}
