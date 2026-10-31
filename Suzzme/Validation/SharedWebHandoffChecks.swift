import Foundation
import Darwin
import Synchronization

@main struct SharedWebHandoffChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SuzmeShareChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var passed = 0
        func check(_ condition: Bool, _ name: String) { precondition(condition, name); passed += 1; print("PASS \(name)") }
        func rejects(_ name: String, _ body: () throws -> Void) {
            do { try body(); preconditionFailure(name) } catch { passed += 1; print("PASS \(name)") }
        }
        for value in ["", "file:///private/example.txt", "http://example.com", "https://user:secret@example.com", "https://@example.com", "https://example.com:8443", "https://localhost", "https://127.0.0.1", "https://127.1", "https://2130706433", "https://0x7f000001", "https://[::1]", "https://printer.local", "https://example.internal", "https://router.home.arpa", "https://web.whatsapp.com", "https://wa.me/123", "https://sub.whatsapp.net", "https://example.com/\npath", "https://example.com\\evil", "https://bad..example.com", "https://-bad.example.com", "https://example.com/" + String(repeating: "x", count: 2_049)] {
            rejects("unsupported URL rejected before staging") { _ = try SharedWebInbox.canonicalURL(value) }
        }
        let clean = try SharedWebInbox.canonicalURL("https://Example.COM:443/path?token=fixture#fragment")
        check(clean.absoluteString == "https://example.com/path", "scheme/host/port normalized and query/fragment stripped")
        let store = SharedWebInbox(testDirectory: root.appendingPathComponent("queue"))
        let now = Date(timeIntervalSince1970: 1_800_000_000.625)
        let page = try store.enqueue(clean.absoluteString, now: now)
        let resolved = try store.resolve(page.id, now: now)
        check(resolved == page, "atomic write verifies exact round trip with fractional caller time")
        let duplicate = try store.enqueue(clean.absoluteString, now: now.addingTimeInterval(1))
        let duplicatePages = try store.pages(now: now).pages
        check(duplicate.id == page.id && duplicatePages.count == 1, "repeated sharing is idempotent")
        let changed = SharedWebPage(version: page.version, id: page.id, address: "https://example.com/another", sharedAt: page.sharedAt)
        rejects("a changed review token cannot silently use a different URL") { _ = try store.resolve(changed, now: now) }
        let reopened = SharedWebInbox(testDirectory: root.appendingPathComponent("queue"))
        check(try reopened.resolve(page.id, now: now).address == clean.absoluteString, "new store instance sees staged URL")
        rejects("expired URL cannot open or become a question") { _ = try reopened.resolve(page.id, now: now.addingTimeInterval(601)) }
        check(try reopened.pages(now: now.addingTimeInterval(601)).pages.isEmpty, "expired queue entry removed on next check")
        for index in 0..<SharedWebInbox.capacity { try store.enqueue("https://example.com/\(index)", now: now) }
        rejects("queue hard capacity enforced") { try store.enqueue("https://example.com/overflow", now: now) }
        let lockPath = root.appendingPathComponent("queue/.queue.lock").path
        let descriptor = lockPath.withCString { Darwin.open($0, O_RDWR | O_NOFOLLOW) }
        precondition(descriptor >= 0 && flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        rejects("another process lock fails promptly without writing") { _ = try store.pages(now: now) }
        _ = flock(descriptor, LOCK_UN); _ = Darwin.close(descriptor)
        try store.clear(); check(try store.pages(now: now).pages.isEmpty, "explicit queue clear leaves no staged URLs")
        let unknown = try store.enqueue(clean.absoluteString, now: now)
        let unknownFile = root.appendingPathComponent("queue/\(unknown.id.uuidString).json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: unknownFile)) as! [String: Any]
        object["version"] = 2; try JSONSerialization.data(withJSONObject: object).write(to: unknownFile)
        let future = try store.pages(now: now.addingTimeInterval(700))
        check(future.pages.isEmpty && future.hasUnreadable && FileManager.default.fileExists(atPath: unknownFile.path), "future schema fails closed and preserves original until explicit clear")
        try store.clear()
        let outside = root.appendingPathComponent("outside.txt"); try Data("not a shared page".utf8).write(to: outside)
        let symlink = root.appendingPathComponent("queue/\(UUID()).json")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
        let linked = try store.pages(now: now)
        check(linked.pages.isEmpty && linked.hasUnreadable, "symlink cannot import outside data")
        try store.clear(); check(FileManager.default.fileExists(atPath: outside.path), "queue clear never deletes symlink target")
        let oversized = root.appendingPathComponent("queue/\(UUID()).json")
        try Data(repeating: 65, count: 8_193).write(to: oversized)
        check(try store.pages(now: now).hasUnreadable, "oversized file withheld")
        try store.clear()
        let concurrent = SharedWebInbox(testDirectory: root.appendingPathComponent("parallel"))
        let outcome = Mutex((writes: 0, unexpected: 0))
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            do { try concurrent.enqueue("https://example.com/item/\(index)", now: now); outcome.withLock { $0.writes += 1 } }
            catch SharedWebInboxError.busy { }
            catch SharedWebInboxError.full { }
            catch { outcome.withLock { $0.unexpected += 1 } }
        }
        let parallel = try concurrent.pages(now: now)
        check(outcome.withLock { $0.writes > 0 && $0.unexpected == 0 } && parallel.pages.count <= SharedWebInbox.capacity && !parallel.hasUnreadable, "concurrent staging never corrupts or exceeds queue capacity")
        print("Shared web handoff: \(passed) passed / 0 failed")
    }
}
