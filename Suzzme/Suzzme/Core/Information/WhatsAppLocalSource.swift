#if os(macOS)
import Foundation
import CryptoKit
import SQLite3

struct WhatsAppChatChoice: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let lastMessage: Date
    let messageCount: Int
}

struct WhatsAppWindow: Sendable {
    let chatID: String
    let name: String
    let lastRowID: Int64
    let lastMessage: Date
    let text: String
}

enum WhatsAppLocalError: Error {
    case access, schema, selection, unavailable
}

/// Owns the user's security-scoped folder grant and selected chat IDs. No
/// message content is persisted here; a read returns bounded in-memory text.
actor WhatsAppLocalAccess {
    static let shared = WhatsAppLocalAccess()
    private let bookmarkKey = "whatsapp.local.folder.bookmark.v1"
    private let chatsKey = "whatsapp.local.selected.chats.v1"
    private let highWaterKey = "whatsapp.local.committed.rows.v1"
    private var generation = UUID()

    func hasFolder() -> Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }
    func canRead() -> Bool {
        (try? withSavedFolder { folder in
            guard folder.startAccessingSecurityScopedResource() else { return false }
            defer { folder.stopAccessingSecurityScopedResource() }
            return FileManager.default.isReadableFile(atPath: folder.appendingPathComponent("ChatStorage.sqlite").path)
        }) == true
    }
    func selectedChatIDs() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: chatsKey) ?? []) }
    func currentGeneration() -> UUID { generation }

    func connect(folder: URL) throws -> [WhatsAppChatChoice] {
        guard folder.lastPathComponent == "group.net.whatsapp.WhatsApp.shared" else { throw WhatsAppLocalError.access }
        let chats = try withSnapshot(folder: folder) { db in try db.chats() }
        let bookmark = try folder.bookmarkData(options: .withSecurityScope,
            includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: chatsKey)
        UserDefaults.standard.removeObject(forKey: highWaterKey)
        generation = UUID()
        return chats
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: chatsKey)
        UserDefaults.standard.removeObject(forKey: highWaterKey)
        generation = UUID()
    }

    func select(_ ids: Set<String>) throws {
        guard ids.count <= 20, ids.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 }) else {
            throw WhatsAppLocalError.selection
        }
        let available = Set(try chats().map(\.id))
        guard ids.isSubset(of: available) else { throw WhatsAppLocalError.selection }
        UserDefaults.standard.set(ids.sorted(), forKey: chatsKey)
        UserDefaults.standard.removeObject(forKey: highWaterKey)
        generation = UUID()
    }

    func chats() throws -> [WhatsAppChatChoice] {
        try withSavedFolder { folder in try withSnapshot(folder: folder) { db in try db.chats() } }
    }

    func windows(now: Date, calendar: Calendar = .current, includeCommitted: Bool = false) throws -> (generation: UUID, values: [WhatsAppWindow]) {
        let selected = selectedChatIDs()
        guard !selected.isEmpty else { throw WhatsAppLocalError.selection }
        let owner = generation
        let values = try withSavedFolder { folder in
            try withSnapshot(folder: folder) { db in try db.windows(selected: selected, now: now, calendar: calendar) }
        }
        if includeCommitted { return (owner, values) }
        let committed = committedRows()
        return (owner, values.filter { $0.lastRowID > committed[Self.hash($0.chatID), default: 0] })
    }

    func markCommitted(_ observations: [InformationObservation]) {
        let selected = Set(selectedChatIDs().map(Self.hash))
        var committed = committedRows()
        for observation in observations {
            let fields = observation.externalID.split(separator: ":")
            guard fields.count == 3, fields[0] == "chat", selected.contains(String(fields[1])),
                  let row = Int64(fields[2]), row > 0 else { continue }
            let key = String(fields[1])
            committed[key] = max(row, committed[key, default: 0])
        }
        UserDefaults.standard.set(committed, forKey: highWaterKey)
    }

    private func committedRows() -> [String: Int64] {
        (UserDefaults.standard.dictionary(forKey: highWaterKey) ?? [:]).compactMapValues {
            ($0 as? NSNumber)?.int64Value
        }
    }

    func isCurrent(_ owner: UUID) -> Bool { owner == generation && !selectedChatIDs().isEmpty && canRead() }

    func permits(_ externalID: String) -> Bool {
        guard canRead() else { return false }
        return selectedChatIDs().contains { id in
            externalID.hasPrefix("chat:" + Self.hash(id) + ":")
        }
    }

    private func withSavedFolder<T>(_ work: (URL) throws -> T) throws -> T {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { throw WhatsAppLocalError.access }
        var stale = false
        let folder = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
            relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale, folder.lastPathComponent == "group.net.whatsapp.WhatsApp.shared" else {
            throw WhatsAppLocalError.access
        }
        return try work(folder)
    }

    private func withSnapshot<T>(folder: URL, work: (WhatsAppSnapshotDB) throws -> T) throws -> T {
        guard folder.startAccessingSecurityScopedResource() else { throw WhatsAppLocalError.access }
        defer { folder.stopAccessingSecurityScopedResource() }
        let source = folder.appendingPathComponent("ChatStorage.sqlite")
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { throw WhatsAppLocalError.access }
        let temporary = fm.temporaryDirectory.appendingPathComponent("suzzme-whatsapp-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: temporary) }
        let copy = temporary.appendingPathComponent("ChatStorage.sqlite")
        try WhatsAppSnapshotDB.backup(source: source, destination: copy)
        let database = try WhatsAppSnapshotDB(url: copy)
        return try work(database)
    }

    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// SQLite is touched only on the temporary copy. Static SQL and bound chat IDs
/// keep message text and unselected chats out of the app's durable store.
final class WhatsAppSnapshotDB {
    private var handle: OpaquePointer?

    /// SQLite's backup API takes a consistent view including committed WAL
    /// records while WhatsApp continues writing. The source stays read-only.
    static func backup(source: URL, destination: URL) throws {
        var input: OpaquePointer?, output: OpaquePointer?
        defer { sqlite3_close(input); sqlite3_close(output) }
        guard sqlite3_open_v2(source.path, &input, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              sqlite3_open_v2(destination.path, &output, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let operation = sqlite3_backup_init(output, "main", input, "main") else {
            throw WhatsAppLocalError.access
        }
        let deadline = ContinuousClock.now + .seconds(5)
        var result: Int32
        repeat {
            result = sqlite3_backup_step(operation, 128)
            if result == SQLITE_BUSY || result == SQLITE_LOCKED { sqlite3_sleep(20) }
        } while [SQLITE_OK, SQLITE_BUSY, SQLITE_LOCKED].contains(result) && ContinuousClock.now < deadline
        let finished = sqlite3_backup_finish(operation)
        guard result == SQLITE_DONE, finished == SQLITE_OK else { throw WhatsAppLocalError.unavailable }
    }

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            throw WhatsAppLocalError.unavailable
        }
        sqlite3_busy_timeout(handle, 2_000)
    }
    deinit { sqlite3_close(handle) }

    func chats() throws -> [WhatsAppChatChoice] {
        let floor = Date().addingTimeInterval(-90 * 86_400).timeIntervalSinceReferenceDate
        let sql = """
        SELECT s.ZCONTACTJID, COALESCE(s.ZPARTNERNAME, ''), COUNT(m.Z_PK), MAX(m.ZMESSAGEDATE)
        FROM ZWACHATSESSION s JOIN ZWAMESSAGE m ON m.ZCHATSESSION = s.Z_PK
        WHERE s.ZSESSIONTYPE IN (0, 1) AND s.ZCONTACTJID IS NOT NULL
          AND NOT (s.ZSESSIONTYPE = 1 AND s.ZPARTNERNAME IS NOT NULL AND s.ZPARTNERNAME IN
              (SELECT ZPARTNERNAME FROM ZWACHATSESSION
               WHERE ZSESSIONTYPE = 4 AND ZPARTNERNAME IS NOT NULL))
          AND m.ZTEXT IS NOT NULL AND length(m.ZTEXT) > 0
          AND m.ZMESSAGEDATE >= \(floor)
        GROUP BY s.Z_PK ORDER BY MAX(m.ZMESSAGEDATE) DESC LIMIT 100
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var result: [WhatsAppChatChoice] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            defer { step = sqlite3_step(statement) }
            guard let jid = text(statement, 0), !jid.isEmpty else { continue }
            let name = text(statement, 1).flatMap { $0.isEmpty ? nil : $0 } ?? "WhatsApp chat"
            result.append(.init(id: jid, name: String(name.prefix(100)),
                                lastMessage: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 3)),
                                messageCount: Int(sqlite3_column_int64(statement, 2))))
        }
        guard step == SQLITE_DONE else { throw WhatsAppLocalError.unavailable }
        return result
    }

    func windows(selected: Set<String>, now: Date, calendar: Calendar = .current) throws -> [WhatsAppWindow] {
        guard !selected.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: selected.count).joined(separator: ",")
        let sql = """
        SELECT s.ZCONTACTJID, COALESCE(s.ZPARTNERNAME, ''), m.Z_PK,
               m.ZMESSAGEDATE, m.ZISFROMME, m.ZTEXT,
               m.ZPUSHNAME, gm.ZCONTACTNAME, gm.ZFIRSTNAME
        FROM ZWAMESSAGE m JOIN ZWACHATSESSION s ON m.ZCHATSESSION = s.Z_PK
        LEFT JOIN ZWAGROUPMEMBER gm ON m.ZGROUPMEMBER = gm.Z_PK
        WHERE s.ZSESSIONTYPE IN (0, 1) AND s.ZCONTACTJID IN (\(placeholders))
          AND NOT (s.ZSESSIONTYPE = 1 AND s.ZPARTNERNAME IS NOT NULL AND s.ZPARTNERNAME IN
              (SELECT ZPARTNERNAME FROM ZWACHATSESSION
               WHERE ZSESSIONTYPE = 4 AND ZPARTNERNAME IS NOT NULL))
          AND m.ZTEXT IS NOT NULL AND length(m.ZTEXT) > 0
          AND m.ZMESSAGEDATE >= ? AND m.ZMESSAGEDATE <= ?
        ORDER BY m.ZMESSAGEDATE DESC LIMIT 400
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, id) in selected.sorted().enumerated() {
            guard id.withCString({ sqlite3_bind_text(statement, Int32(index + 1), $0, -1, transient) }) == SQLITE_OK else {
                throw WhatsAppLocalError.unavailable
            }
        }
        guard sqlite3_bind_double(statement, Int32(selected.count + 1), calendar.startOfDay(for: now).timeIntervalSinceReferenceDate) == SQLITE_OK,
              sqlite3_bind_double(statement, Int32(selected.count + 2), now.timeIntervalSinceReferenceDate) == SQLITE_OK else {
            throw WhatsAppLocalError.unavailable
        }
        var grouped: [String: [(row: Int64, date: Date, text: String)]] = [:]
        var names: [String: String] = [:]
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            defer { step = sqlite3_step(statement) }
            guard let jid = text(statement, 0), let body = text(statement, 5),
                  !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let name = text(statement, 1).flatMap { $0.isEmpty ? nil : $0 } ?? "WhatsApp chat"
            names[jid] = String(name.prefix(100))
            let speaker: String
            if sqlite3_column_int(statement, 4) == 1 { speaker = "You" }
            else if jid.hasSuffix("@g.us") {
                speaker = Self.cleanName(text(statement, 6))
                    ?? Self.cleanName(text(statement, 7))
                    ?? Self.cleanName(text(statement, 8))
                    ?? "Group member"
            } else { speaker = names[jid]! }
            let line = "\(speaker): \(String(body.prefix(500)))"
            if grouped[jid, default: []].count < 30 {
                grouped[jid, default: []].append((sqlite3_column_int64(statement, 2),
                                                   Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 3)), line))
            }
        }
        guard step == SQLITE_DONE else { throw WhatsAppLocalError.unavailable }
        return grouped.compactMap { jid, rows in
            guard let newest = rows.first, let lastRowID = rows.map(\.row).max() else { return nil }
            let body = rows.reversed().map(\.text).joined(separator: "\n")
            return WhatsAppWindow(chatID: jid, name: names[jid] ?? "WhatsApp chat",
                                  lastRowID: lastRowID, lastMessage: newest.date,
                                  text: String(body.prefix(4_000)))
        }.sorted { $0.lastMessage > $1.lastMessage }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw WhatsAppLocalError.schema
        }
        return statement
    }
    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let raw = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: raw)
    }
    private static func cleanName(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if !value.contains(" ") && (value.contains("/") || value.count > 24) { return nil }
        return String(value.filter { !$0.isNewline && !$0.isControl }.prefix(80))
    }
}

private extension Character {
    var isControl: Bool { unicodeScalars.allSatisfy(CharacterSet.controlCharacters.contains) }
}

struct WhatsAppLocalSource: InformationSource {
    let id: InformationSourceID = .whatsapp
    let access: WhatsAppLocalAccess
    let understanding: SuzzmeUnderstandingPipeline

    func authorization() async -> InformationHealthState {
        guard await access.hasFolder() else { return .permissionRequired }
        guard !(await access.selectedChatIDs()).isEmpty else { return .permissionRequired }
        guard await access.canRead() else { return .authorizationExpired }
        guard await understanding.capability().usesFoundationModels else { return .unsupported }
        return .healthy
    }

    func fetch(now: Date, checkpoint: Date?) async throws -> InformationBatch {
        try await fetchWindow(now: now, calendar: .current, includeCommitted: false)
    }

    func fetchForBriefing(now: Date, checkpoint: Date?, cutoff: Date, calendar: Calendar) async throws -> InformationBatch {
        try await fetchWindow(now: cutoff, calendar: calendar, includeCommitted: true)
    }

    private func fetchWindow(now: Date, calendar: Calendar, includeCommitted: Bool) async throws -> InformationBatch {
        let result = try await access.windows(now: now, calendar: calendar, includeCommitted: includeCommitted)
        var observations: [InformationObservation] = []
        for window in result.values.prefix(20) {
            try Task.checkCancellation()
            guard PrivacyEngine().classify(window.text).policy != .neverProcess else { continue }
            let summary = try await understanding.summarizeGroundedFacts(window.text)
            guard summary.usedOnDeviceModel,
                  PrivacyEngine().classify(summary.text).policy != .neverProcess else { continue }
            let title = "WhatsApp · \(window.name): \(summary.text)"
            observations.append(.init(
                externalID: "chat:\(WhatsAppLocalAccess.hash(window.chatID)):\(window.lastRowID)",
                title: String(title.prefix(240)),
                entities: ["whatsapp"], modifiedAt: window.lastMessage, effectiveAt: window.lastMessage,
                kindHint: .generalUpdate
            ))
        }
        guard await access.isCurrent(result.generation) else { throw InformationError.staleCycle }
        return .init(observations: observations, complete: false,
                     window: .init(start: calendar.startOfDay(for: now), end: now))
    }

    func permits(_ event: InformationEvent, now: Date) async -> Bool {
        await access.permits(event.externalID)
    }

    func didCommit(_ batch: InformationBatch) async {
        await access.markCommitted(batch.observations)
    }
}
#endif
