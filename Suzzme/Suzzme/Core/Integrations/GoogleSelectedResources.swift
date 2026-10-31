import Foundation
import CryptoKit

/// One explicit bounded selection per service under the SDK-owned Google account.
/// No OAuth token, account copy, raw snapshot, or parallel information database.
struct GoogleResourceSelection: Codable, Sendable, Equatable {
    var resources: [String: String]
    var enabled: Bool
    var generation: UUID
    var lastSuccess: Date?
    var health: InformationHealthState = .permissionRequired
}

enum GoogleSelectionPolicy {
    static let services: [IntegrationID] = [.googleCalendar, .googleDrive, .googleDocs, .googleSheets, .googleTasks]
    static func fields(_ service: IntegrationID) -> [ProviderReadRecipe.Scope] {
        switch service {
        case .googleCalendar: [.init(key: "calendar", label: "Selected calendar ID (primary or exact ID)")]
        case .googleDrive: [.init(key: "file", label: "Selected file ID")]
        case .googleDocs: [.init(key: "document", label: "Selected document ID")]
        case .googleSheets: [.init(key: "spreadsheet", label: "Selected spreadsheet ID"), .init(key: "range", label: "Selected tab and range (for example Sheet1!A1:D20)")]
        case .googleTasks: [.init(key: "list", label: "Selected task list ID")]
        default: []
        }
    }
    static func validates(_ resources: [String: String], service: IntegrationID) -> Bool {
        guard services.contains(service), Set(resources.keys) == Set(fields(service).map(\.key)) else { return false }
        return resources.allSatisfy { key, value in
            guard !value.isEmpty, value.utf8.count <= 256, !value.contains(where: { $0.isNewline }) else { return false }
            if key == "range" {
                // Require an explicit tab, rectangular positive range, <= 500 cells.
                guard let bang = value.lastIndex(of: "!"), bang != value.startIndex else { return false }
                let parts = value[value.index(after: bang)...].split(separator: ":", omittingEmptySubsequences: false)
                guard parts.count == 2, let a = cell(String(parts[0])), let b = cell(String(parts[1])),
                      b.0 >= a.0, b.1 >= a.1 else { return false }
                return (b.0 - a.0 + 1) * (b.1 - a.1 + 1) <= 500
            }
            return value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,95,64,46].contains($0) }
        }
    }
    private static func cell(_ value: String) -> (Int, Int)? {
        let letters = value.prefix { $0.isASCII && $0.isUppercase }
        let digits = value.dropFirst(letters.count)
        guard !letters.isEmpty, letters.count <= 3, !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let row = Int(digits), (1...10000).contains(row) else { return nil }
        let column = letters.utf8.reduce(0) { $0 * 26 + Int($1 - 64) }
        return (column, row)
    }
    static func namespace(accountID: String, service: IntegrationID, generation: UUID) -> String {
        let hash = SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined()
        return "google:" + hash + ":" + service.rawValue + ":" + generation.uuidString + ":"
    }
}

extension GoogleProviderScopeStore {
    private static let selectionLock = NSLock()
    static func selection(_ service: IntegrationID, accountID: String, defaults: UserDefaults = .standard) -> GoogleResourceSelection? {
        guard let data = defaults.data(forKey: selectionKey(service, accountID)), data.count <= 8192,
              let value = try? JSONDecoder().decode(GoogleResourceSelection.self, from: data),
              GoogleSelectionPolicy.validates(value.resources, service: service),
              value.lastSuccess.map({ $0.timeIntervalSince1970.isFinite }) ?? true else { return nil }
        return value
    }
    static func select(_ resources: [String: String], enabled: Bool, service: IntegrationID, accountID: String, defaults: UserDefaults = .standard) throws {
        guard GoogleSelectionPolicy.validates(resources, service: service) else { throw IntegrationFailure.invalidConfiguration }
        let value = GoogleResourceSelection(resources: resources, enabled: enabled, generation: UUID())
        selectionLock.lock(); defer { selectionLock.unlock() }
        defaults.set(try JSONEncoder().encode(value), forKey: selectionKey(service, accountID))
    }
    static func clearSelection(_ service: IntegrationID, accountID: String, defaults: UserDefaults = .standard) {
        selectionLock.lock(); defer { selectionLock.unlock() }
        defaults.removeObject(forKey: selectionKey(service, accountID))
    }
    static func record(_ service: IntegrationID, accountID: String, generation: UUID, health: InformationHealthState, success: Date?, defaults: UserDefaults = .standard) {
        selectionLock.lock(); defer { selectionLock.unlock() }
        guard var value = selection(service, accountID: accountID, defaults: defaults), value.generation == generation else { return }
        value.health = health
        if let success { value.lastSuccess = success }
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: selectionKey(service, accountID)) }
    }
    private static func selectionKey(_ service: IntegrationID, _ accountID: String) -> String {
        let hash = SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined()
        return "suzzme.integrations.google.selected." + hash + "." + service.rawValue
    }
}
