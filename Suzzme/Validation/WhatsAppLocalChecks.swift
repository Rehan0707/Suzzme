import Foundation
import SQLite3

// Minimal collaborators let this test compile the production SQLite reader
// without Firebase, UI, or a user's WhatsApp installation.
enum InformationSourceID: Sendable { case whatsapp }
enum InformationHealthState: Sendable { case permissionRequired, authorizationExpired, unsupported, healthy }
enum InformationKind: Sendable { case generalUpdate }
enum InformationError: Error { case staleCycle }
struct InformationObservation: Sendable {
    let externalID: String
    let title: String
    let entities: [String]
    let modifiedAt: Date
    let effectiveAt: Date?
    let kindHint: InformationKind
}
struct InformationBatch: Sendable {
    let observations: [InformationObservation]
    let complete: Bool
    let window: DateInterval
}
protocol InformationSource: Sendable {
    var id: InformationSourceID { get }
    func authorization() async -> InformationHealthState
    func fetch(now: Date, checkpoint: Date?) async throws -> InformationBatch
    func permits(_ event: InformationEvent, now: Date) async -> Bool
    func didCommit(_ batch: InformationBatch) async
}
struct InformationEvent: Sendable { let externalID: String }
struct PrivacyEngine {
    func classify(_ text: String) -> Decision { .init(policy: .localOnly) }
    struct Decision { let policy: Policy }
    enum Policy { case localOnly, neverProcess }
}
actor SuzzmeUnderstandingPipeline {
    func capability() -> Capability { .init(usesFoundationModels: true) }
    func summarizeGroundedFacts(_ value: String) throws -> Summary { .init(text: value, usedOnDeviceModel: true) }
    struct Capability { let usesFoundationModels: Bool }
    struct Summary { let text: String; let usedOnDeviceModel: Bool }
}

@main struct WhatsAppLocalChecks {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("suzzme-whatsapp-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("ChatStorage.sqlite")
        var database: OpaquePointer?
        guard sqlite3_open(path.path, &database) == SQLITE_OK else { fatalError("Fixture database") }
        defer { if let database { sqlite3_close(database) } }
        let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let recent = now.addingTimeInterval(-3600).timeIntervalSinceReferenceDate
        let old = now.addingTimeInterval(-3 * 86_400).timeIntervalSinceReferenceDate
        let statements = [
            "CREATE TABLE ZWACHATSESSION (Z_PK INTEGER PRIMARY KEY, ZCONTACTJID TEXT, ZPARTNERNAME TEXT, ZSESSIONTYPE INTEGER)",
            "CREATE TABLE ZWAMESSAGE (Z_PK INTEGER PRIMARY KEY, ZCHATSESSION INTEGER, ZMESSAGEDATE REAL, ZISFROMME INTEGER, ZTEXT TEXT, ZPUSHNAME TEXT, ZGROUPMEMBER INTEGER)",
            "CREATE TABLE ZWAGROUPMEMBER (Z_PK INTEGER PRIMARY KEY, ZCONTACTNAME TEXT, ZFIRSTNAME TEXT)",
            "INSERT INTO ZWACHATSESSION VALUES (1, 'alex@s.whatsapp.net', 'Alex', 0)",
            "INSERT INTO ZWACHATSESSION VALUES (2, 'team@g.us', 'Team', 1)",
            "INSERT INTO ZWACHATSESSION VALUES (3, 'news@g.us', 'News', 1)",
            "INSERT INTO ZWACHATSESSION VALUES (4, 'community@g.us', 'News', 4)",
            "INSERT INTO ZWAGROUPMEMBER VALUES (1, 'Sam', '')",
            "INSERT INTO ZWAMESSAGE VALUES (10, 1, \(recent - 60), 0, 'Meeting at three', NULL, NULL)",
            "INSERT INTO ZWAMESSAGE VALUES (11, 1, \(recent), 1, 'I will attend', NULL, NULL)",
            "INSERT INTO ZWAMESSAGE VALUES (12, 2, \(recent), 0, 'Team update', NULL, 1)",
            "INSERT INTO ZWAMESSAGE VALUES (13, 3, \(recent), 0, 'Announcement', NULL, NULL)",
            "INSERT INTO ZWAMESSAGE VALUES (14, 1, \(old), 0, 'Old message', NULL, NULL)"
            ,"INSERT INTO ZWAMESSAGE VALUES (15, 1, \(Calendar.current.startOfDay(for: now).addingTimeInterval(-60).timeIntervalSinceReferenceDate), 0, 'Yesterday message', NULL, NULL)"
            ,"INSERT INTO ZWAMESSAGE VALUES (16, 1, \(now.addingTimeInterval(60).timeIntervalSinceReferenceDate), 0, 'After cutoff message', NULL, NULL)"
        ]
        for sql in statements { guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { fatalError("Fixture SQL") } }
        precondition(sqlite3_exec(database, "PRAGMA journal_mode=WAL; BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK)
        precondition(sqlite3_exec(database, "INSERT INTO ZWAMESSAGE VALUES (99, 1, \(recent + 1), 0, 'Pending transaction', NULL, NULL)", nil, nil, nil) == SQLITE_OK)
        let beforeCommit = directory.appendingPathComponent("before.sqlite")
        try WhatsAppSnapshotDB.backup(source: path, destination: beforeCommit)
        let before = try WhatsAppSnapshotDB(url: beforeCommit).windows(selected: ["alex@s.whatsapp.net"], now: now)
        precondition(before.first?.lastRowID == 11, "Snapshot excludes a live uncommitted transaction")
        precondition(sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK)
        let afterCommit = directory.appendingPathComponent("after.sqlite")
        try WhatsAppSnapshotDB.backup(source: path, destination: afterCommit)
        let after = try WhatsAppSnapshotDB(url: afterCommit).windows(selected: ["alex@s.whatsapp.net"], now: now)
        precondition(after.first?.lastRowID == 99, "Snapshot includes committed WAL records while WhatsApp remains open")
        precondition(sqlite3_exec(database, "DELETE FROM ZWAMESSAGE WHERE Z_PK=99", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(database)
        database = nil

        let reader = try WhatsAppSnapshotDB(url: path)
        let chats = try reader.chats()
        precondition(Set(chats.map(\.id)) == ["alex@s.whatsapp.net", "team@g.us"], "Only real recent chats appear")
        let windows = try reader.windows(selected: ["alex@s.whatsapp.net"], now: now)
        precondition(windows.count == 1 && windows[0].lastRowID == 11, "Only the chosen chat is read")
        precondition(windows[0].text.contains("Alex: Meeting at three") && windows[0].text.contains("You: I will attend"), "Speaker attribution survives")
        precondition(!windows[0].text.contains("Old message") && !windows[0].text.contains("Team update"), "Old and unselected messages stay out")
        precondition(!windows[0].text.contains("Yesterday message") && !windows[0].text.contains("After cutoff message"), "Only messages from today through the cutoff are summarized")
        let group = try reader.windows(selected: ["team@g.us"], now: now)
        precondition(group.count == 1 && group[0].text.contains("Sam: Team update"), "Group sender attribution survives")
        print("WhatsApp local reader checks passed")
    }
}
