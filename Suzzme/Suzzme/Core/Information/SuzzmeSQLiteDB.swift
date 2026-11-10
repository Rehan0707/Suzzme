import Foundation
import SQLite3

/// Bounded SQLite read utilities for local on-device database sources (Notes, Messages, WhatsApp).
/// Live databases are open by macOS system processes in WAL mode, so we never query them in place:
/// a snapshot copy of the DB and its `-wal` / `-shm` siblings is made in a private temp directory (0o700),
/// read into memory, and deleted immediately so plaintext user data does not linger on disk.
nonisolated enum SuzzmeSQLiteDB {
    enum DBError: Error, CustomStringConvertible {
        case missingFile(String)
        case open(String)
        case prepare(String)
        case step(Int32)

        var description: String {
            switch self {
            case .missingFile(let path):
                return "Database not found at: \(path)"
            case .open(let message):
                return "SQLite open failed: \(message)"
            case .prepare(let message):
                return "SQLite prepare failed: \(message)"
            case .step(let code):
                return "SQLite read failed with code \(code)"
            }
        }
    }

    /// Creates a WAL-safe snapshot copy in a secure private temporary directory.
    /// The caller is responsible for deleting `dir` when finished.
    static func walSafeCopy(of dbPath: String) throws -> (db: URL, dir: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: dbPath) else {
            throw DBError.missingFile(dbPath)
        }

        let dir = fileManager.temporaryDirectory
            .appendingPathComponent("suzzme-db-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        var completed = false
        defer {
            if !completed {
                try? fileManager.removeItem(at: dir)
            }
        }

        let fileName = URL(fileURLWithPath: dbPath).lastPathComponent
        let destination = dir.appendingPathComponent(fileName)
        try fileManager.copyItem(atPath: dbPath, toPath: destination.path)

        for sidecar in ["-wal", "-shm"] {
            let sidecarPath = dbPath + sidecar
            if fileManager.fileExists(atPath: sidecarPath) {
                try? fileManager.copyItem(atPath: sidecarPath, toPath: destination.path + sidecar)
            }
        }

        completed = true
        return (destination, dir)
    }
}

/// Lightweight SQLite reader for querying copied local snapshots.
nonisolated final class SuzzmeSQLiteReader {
    private var db: OpaquePointer?

    init(path: String) throws {
        // Open read-write on the temporary copy to allow WAL replay if needed
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            db = nil
            throw SuzzmeSQLiteDB.DBError.open(msg)
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func forEachRow(_ sql: String, _ handler: (Row) throws -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown prepare error"
            throw SuzzmeSQLiteDB.DBError.prepare(msg)
        }
        defer { sqlite3_finalize(stmt) }

        while true {
            let stepResult = sqlite3_step(stmt)
            switch stepResult {
            case SQLITE_ROW:
                guard let validStmt = stmt else { return }
                try handler(Row(validStmt))
            case SQLITE_DONE:
                return
            default:
                throw SuzzmeSQLiteDB.DBError.step(stepResult)
            }
        }
    }

    struct Row {
        private let stmt: OpaquePointer

        init(_ stmt: OpaquePointer) {
            self.stmt = stmt
        }

        func int(_ index: Int32) -> Int64 {
            sqlite3_column_int64(stmt, index)
        }

        func double(_ index: Int32) -> Double {
            sqlite3_column_double(stmt, index)
        }

        func text(_ index: Int32) -> String? {
            guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
                  let cString = sqlite3_column_text(stmt, index) else {
                return nil
            }
            return String(cString: cString)
        }

        func blob(_ index: Int32) -> Data? {
            guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
                  let bytes = sqlite3_column_blob(stmt, index) else {
                return nil
            }
            let count = Int(sqlite3_column_bytes(stmt, index))
            return Data(bytes: bytes, count: count)
        }
    }
}

