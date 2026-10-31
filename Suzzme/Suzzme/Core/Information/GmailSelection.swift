import Foundation
import CryptoKit

struct GmailSelection: Codable, Sendable, Equatable {
    enum Mode: String, Codable, CaseIterable, Sendable {
        case recentInbox, unreadInbox, importantInbox
        var title: String {
            switch self { case .recentInbox: "Recent inbox"; case .unreadInbox: "Unread inbox"; case .importantInbox: "Important inbox" }
        }
        var labelIDs: [String] {
            switch self { case .recentInbox: ["INBOX"]; case .unreadInbox: ["INBOX", "UNREAD"]; case .importantInbox: ["INBOX", "IMPORTANT"] }
        }
    }
    let mode: Mode
    let generation: UUID
    let includeBodies: Bool
    init(mode: Mode, generation: UUID, includeBodies: Bool = false) {
        self.mode = mode
        self.generation = generation
        self.includeBodies = includeBodies
    }
    private enum CodingKeys: String, CodingKey { case mode, generation, includeBodies }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = try values.decode(Mode.self, forKey: .mode)
        generation = try values.decode(UUID.self, forKey: .generation)
        includeBodies = try values.decodeIfPresent(Bool.self, forKey: .includeBodies) ?? false
    }
    var prefix: String { "selection:" + generation.uuidString + ":" }
}
enum GmailSelectionStore {
    static func load(accountID: String, defaults: UserDefaults = .standard) -> GmailSelection? {
        guard let data = defaults.data(forKey: key(accountID)), data.count <= 1024 else { return nil }
        return try? JSONDecoder().decode(GmailSelection.self, from: data)
    }
    static func save(mode: GmailSelection.Mode, includeBodies: Bool = false, accountID: String, defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(GmailSelection(mode: mode, generation: UUID(), includeBodies: includeBodies)), forKey: key(accountID))
    }
    static func remove(accountID: String, defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key(accountID)) }
    private static func key(_ id: String) -> String {
        "suzzme.gmail.selection." + SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
