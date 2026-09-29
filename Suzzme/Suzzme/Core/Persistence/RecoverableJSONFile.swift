import Foundation

/// One bounded recovery copy for app-owned JSON stores. Recovery never bypasses
/// the caller's full schema/privacy validation or downgrades a future schema.
/// A previous recovery copy is retired before replacement, including deletion,
/// so an interrupted delete cannot later resurrect data from an older copy.
enum RecoverableJSONFile {
    enum Boundary: Sendable { case temporaryWritten, recoveryRetired, primaryReplaced, recoveryWritten }
    enum Failure: Error { case invalid, futureVersion }
    static let maximumBytes = 2_000_000

    static func recoveryURL(for url: URL) -> URL { url.appendingPathExtension("recovery") }
    static func temporaryURL(for url: URL) -> URL { url.appendingPathExtension("pending") }

    static func read(from url: URL, validate: (Data) throws -> Void) throws -> Data? {
        let manager = FileManager.default
        let recovery = recoveryURL(for: url)
        let primaryExists = manager.fileExists(atPath: url.path)
        if primaryExists {
            do {
                let data = try boundedRead(url)
                try rejectFutureVersion(data)
                try validate(data)
                return data
            } catch Failure.futureVersion { throw Failure.futureVersion }
            catch { /* A malformed current format may use a validated recovery. */ }
        }
        guard manager.fileExists(atPath: recovery.path) else {
            if primaryExists { throw Failure.invalid }
            return nil
        }
        let data = try boundedRead(recovery)
        try rejectFutureVersion(data)
        try validate(data)
        // Repair only after validation; leave both files intact on failure.
        try data.write(to: url, options: .atomic)
        return data
    }

    static func write(_ data: Data, to url: URL, checkpoint: ((Boundary) throws -> Void)? = nil) throws {
        guard data.count <= maximumBytes else { throw Failure.invalid }
        try rejectFutureVersion(data)
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pending = temporaryURL(for: url)
        let recovery = recoveryURL(for: url)
        try Task.checkCancellation()
        try data.write(to: pending, options: .atomic)
        defer { try? manager.removeItem(at: pending) }
        try checkpoint?(.temporaryWritten)
        try Task.checkCancellation()
        if manager.fileExists(atPath: recovery.path) { try manager.removeItem(at: recovery) }
        try checkpoint?(.recoveryRetired)
        try Task.checkCancellation()
        try data.write(to: url, options: .atomic)
        try checkpoint?(.primaryReplaced)
        // Once primary is replaced, it is committed. Failure/cancellation must
        // not cause callers to claim rollback of the on-disk state.
        try data.write(to: recovery, options: .atomic)
        try checkpoint?(.recoveryWritten)
        try Task.checkCancellation()
    }

    private static func boundedRead(_ url: URL) throws -> Data {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= maximumBytes else { throw Failure.invalid }
        return try Data(contentsOf: url)
    }
    private static func rejectFutureVersion(_ data: Data) throws {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let version = object["schemaVersion"] as? Int, version > 1 { throw Failure.futureVersion }
    }
}
