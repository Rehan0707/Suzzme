import Foundation
import Darwin

/// A share-sheet URL is a reference, never page content or account authority.
struct SharedWebPage: Codable, Identifiable, Equatable, Sendable {
    let version: Int
    let id: UUID
    let address: String
    let sharedAt: Date
    var url: URL { URL(string: address)! } // Created/decoded only after canonical validation.
    func isFresh(at now: Date) -> Bool {
        sharedAt <= now.addingTimeInterval(60) && now.timeIntervalSince(sharedAt) < SharedWebInbox.retention
    }
}

enum SharedWebInboxError: Error, LocalizedError, Equatable {
    case unavailable, unsupported, busy, full, malformed, expired, changed, timeout, storage
    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "Webpage sharing isn’t available in this build. You can still share selected text or screenshots in the app.")
        case .unsupported: String(localized: "Choose one HTTPS webpage URL. Files, local addresses, sign-in credentials and WhatsApp links aren’t supported.")
        case .busy: String(localized: "Shared pages are busy. Try again in a moment.")
        case .full: String(localized: "The shared-page queue is full. Review or remove earlier pages in Suzme first.")
        case .malformed: String(localized: "Some shared pages couldn’t be opened. Try sharing them again, or clear this queue.")
        case .expired: String(localized: "This shared URL has expired. Share the page again to use it.")
        case .changed: String(localized: "This shared URL changed. Review the queue again before using it.")
        case .timeout: String(localized: "The shared URL wasn’t available in time. Cancel and share the page again.")
        case .storage: String(localized: "This page couldn’t be saved or opened. Try again.")
        }
    }
}

struct SharedWebInbox: Sendable {
    static let retention: TimeInterval = 10 * 60
    static let capacity = 10
    private let directory: URL

    init() throws {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SuzzmeShareAppGroup") as? String,
              !group.isEmpty, group.count <= 255,
              group.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-").contains($0) }),
              group.contains("."),
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw SharedWebInboxError.unavailable
        }
        directory = root.appendingPathComponent("SharedWebPages-v1", isDirectory: true)
    }

    #if SHARE_HANDOFF_CHECKS
    init(testDirectory: URL) { directory = testDirectory }
    #endif

    static func canonicalURL(_ input: String) throws -> URL {
        guard input.utf8.count <= 2_048, !input.contains("\\"),
              !input.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              var value = URLComponents(string: input), value.scheme?.lowercased() == "https",
              value.user == nil, value.password == nil, value.port == nil || value.port == 443,
              let originalHost = value.host?.lowercased() else { throw SharedWebInboxError.unsupported }
        let host = originalHost.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.count <= 253, labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-") && $0.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 } }),
              labels.last?.utf8.contains(where: { (97...122).contains($0) }) == true,
              !["local", "localhost", "internal", "lan", "home", "onion"].contains(String(labels.last!)),
              host != "home.arpa", !host.hasSuffix(".home.arpa"),
              !["whatsapp.com", "whatsapp.net", "wa.me"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else {
            throw SharedWebInboxError.unsupported
        }
        value.scheme = "https"; value.host = host; value.port = nil
        value.query = nil; value.fragment = nil
        guard let url = value.url else { throw SharedWebInboxError.unsupported }
        return url
    }

    func pages(now: Date = .now) throws -> (pages: [SharedWebPage], hasUnreadable: Bool) {
        try locked { directory in
            var pages: [SharedWebPage] = []; var unreadable = false
            for file in try ownedFiles(in: directory) {
                do {
                    let page = try decode(file)
                    if !page.isFresh(at: now), page.sharedAt <= now {
                        try FileManager.default.removeItem(at: file)
                    } else if page.isFresh(at: now) { pages.append(page) }
                    else { unreadable = true }
                } catch { unreadable = true }
            }
            return (pages.sorted { $0.sharedAt > $1.sharedAt }, unreadable)
        }
    }

    @discardableResult
    func enqueue(_ address: String, now: Date = .now) throws -> SharedWebPage {
        let url = try Self.canonicalURL(address)
        return try locked { directory in
            let files = try ownedFiles(in: directory)
            var retained = 0
            for file in files {
                if let old = try? decode(file), old.sharedAt <= now, !old.isFresh(at: now) {
                    try FileManager.default.removeItem(at: file)
                } else {
                    retained += 1
                    if let old = try? decode(file), old.isFresh(at: now), old.address == url.absoluteString { return old }
                }
            }
            guard retained < Self.capacity else { throw SharedWebInboxError.full }
            let page = SharedWebPage(version: 1, id: UUID(), address: url.absoluteString, sharedAt: Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down)))
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(page)
            let file = directory.appendingPathComponent(page.id.uuidString + ".json")
            #if os(iOS)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: file, options: .atomic)
            #endif
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            guard try decode(file) == page else { throw SharedWebInboxError.storage }
            return page
        }
    }

    func resolve(_ id: UUID, now: Date = .now) throws -> SharedWebPage {
        guard let page = try pages(now: now).pages.first(where: { $0.id == id }) else { throw SharedWebInboxError.expired }
        return page
    }
    func resolve(_ expected: SharedWebPage, now: Date = .now) throws -> SharedWebPage {
        let current = try resolve(expected.id, now: now)
        guard current == expected else { throw SharedWebInboxError.changed }
        return current
    }
    func remove(_ id: UUID) throws {
        try locked { directory in
            let file = directory.appendingPathComponent(id.uuidString + ".json")
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
    }
    func clear() throws {
        try locked { directory in for file in try ownedFiles(in: directory, limiting: false) { try FileManager.default.removeItem(at: file) } }
    }

    private func ownedFiles(in root: URL, limiting: Bool = true) throws -> [URL] {
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
        guard !limiting || files.count <= Self.capacity else { throw SharedWebInboxError.full }
        return files
    }
    private func decode(_ file: URL) throws -> SharedWebPage {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? .max) <= 8_192 else { throw SharedWebInboxError.malformed }
        let descriptor = file.path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK) }
        guard descriptor >= 0 else { throw SharedWebInboxError.malformed }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 8_193) ?? Data()
        guard data.count <= 8_192,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["version", "id", "address", "sharedAt"]) else { throw SharedWebInboxError.malformed }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let page = try decoder.decode(SharedWebPage.self, from: data)
        guard page.version == 1, page.id == UUID(uuidString: file.deletingPathExtension().lastPathComponent),
              try Self.canonicalURL(page.address).absoluteString == page.address else { throw SharedWebInboxError.malformed }
        return page
    }
    /// A nonblocking process lock bounds simultaneous extension/app writes.
    private func locked<T>(_ operation: (URL) throws -> T) throws -> T {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw SharedWebInboxError.storage }
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var root = directory; try root.setResourceValues(values)
            let lockURL = directory.appendingPathComponent(".queue.lock")
            let descriptor = lockURL.path.withCString { Darwin.open($0, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600)) }
            guard descriptor >= 0 else { throw SharedWebInboxError.storage }
            defer { _ = Darwin.close(descriptor) }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw SharedWebInboxError.busy }
            defer { _ = flock(descriptor, LOCK_UN) }
            return try operation(directory)
        } catch let error as SharedWebInboxError { throw error }
        catch { throw SharedWebInboxError.storage }
    }
}
