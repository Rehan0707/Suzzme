import Foundation
import Darwin

private actor ExtractionProgress {
    private var began = false
    func markBegan() { began = true }
    func hasBegun() -> Bool { began }
}

/// Offline checks of the production extractor. No resolver, socket, source store,
/// account, or rendering engine is used by this executable.
@main @MainActor
struct WatchedExtractionChecks {
    static var passed = 0
    static var failed = 0
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func expect(_ condition: Bool, _ label: String) {
        if condition { passed += 1 } else { failed += 1 }
        print("\(condition ? "PASS" : "FAIL") \(label)")
    }
    static func rejects(_ error: WatchedLinkError, _ label: String, _ operation: () throws -> Void) {
        do { try operation(); expect(false, label) }
        catch let actual as WatchedLinkError { expect(actual == error, label) }
        catch { expect(false, label + " returned an unexpected error") }
    }
    static func extract(_ text: String, mime: String = "text/html") throws -> WebPageExtraction {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return try WebContentExtractor.extract(data: Data(text.utf8), mimeType: mime, now: now, calendar: calendar)
    }
    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    static func main() async throws {
        let ordinary = try extract("<html><head><title>Notices &amp; dates</title><script>ignored()</script></head><body><p>Registration deadline tomorrow at 5 PM.</p></body></html>")
        expect(ordinary.title == "Notices & dates", "bounded title is decoded independently of hidden head")
        expect(ordinary.changes.first?.kind == .deadline && ordinary.changes.first?.effectiveAt != nil, "ordinary deadline semantics survive tokenizer change")
        let plain = try extract("Registration deadline tomorrow at 5 PM.", mime: "text/plain; charset=utf-8")
        expect(ordinary.fingerprint == plain.fingerprint, "ordinary HTML and its prior normalized plain text have the same fingerprint")
        expect(ordinary.changes == plain.changes, "ordinary HTML preserves exact local change identity and details")
        let quoted = try extract("<p title='a > b and x < y'>Public notice tomorrow at 9 AM.</p>")
        expect(quoted.changes.first?.detail == "Public notice tomorrow at 9 AM", "quoted angle brackets cannot terminate a tag early")
        let breaks = try extract("<h1>Important notice</h1><p>First public detail</p><ul><li>Second public detail</li></ul><table><tr><td>Third public detail</td></tr></table><br>Fourth public detail")
        expect(breaks.changes.count == 5, "heading, paragraph, list, table and line-break boundaries remain separate")
        let clean = try extract("<main><p>Tomorrow class at 10 AM.</p></main>")
        let boilerplate = try extract("<!doctype html><!-- hidden --><nav>Ignore menu<nav>Nested menu</nav></nav><main><p>Tomorrow class at 10 AM.</p></main><footer><aside>Ignore nested sidebar</aside>Ignore footer</footer><svg><text>Ignore drawing</text></svg><noscript>Ignore fallback</noscript><style>Ignore styles</style><script>const value = '<not-a-tag'; if (1 < 2) { value; }</script>")
        expect(clean.fingerprint == boilerplate.fingerprint, "comments, nested navigation and non-content regions never affect page fingerprint")
        expect(!boilerplate.changes.contains { $0.detail.contains("Ignore") || $0.detail.contains("const") }, "script and suppressed-region text is never retained")
        let escaped = try extract("<p>Literal &lt;script&gt; is shown as text &amp; never retokenized.</p>")
        expect(escaped.changes.first?.detail.contains("<script>") == true, "entity decoding never introduces executable markup")
        let literal = try extract("A text-only page contains <script>literal words</script>.", mime: "text/plain")
        expect(literal.changes.first?.detail.contains("<script>") == true, "text/plain content is never parsed as HTML")
        for mime in ["text/html", "text/plain", "application/xhtml+xml", "TEXT/HTML; charset=UTF-8"] {
            expect((try? extract("A public page with useful ordinary details.", mime: mime)) != nil, "exact supported MIME \(mime)")
        }
        for mime in ["text/html-extra", "text/plaintext", "application/xhtml+xml-malformed", "application/json", "image/png"] {
            rejects(.unsupportedContent, "unsupported MIME \(mime)") { _ = try extract("A useful public page.", mime: mime) }
        }
        rejects(.restrictedContent, "visible credentials remain rejected before retention") { _ = try extract("<p>Never retain the password for this page.</p>") }
        rejects(.restrictedContent, "title credentials remain rejected before retention") { _ = try extract("<head><title>Password notice</title></head><p>Public notice tomorrow.</p>") }
        let lateTitleSecret = "<head><title>" + String(repeating: "Public notice ", count: 1_000) + " password is private</title></head><p>Useful public detail.</p>"
        rejects(.restrictedContent, "title privacy checks precede display truncation and cover the full bounded title") { _ = try extract(lateTitleSecret) }
        let lateSecret = String(repeating: "Public notice. ", count: 2_000) + " The password is private."
        rejects(.restrictedContent, "privacy checks cover visible text beyond the extraction prefix") { _ = try extract(lateSecret, mime: "text/plain") }
        let latin1 = Data([0x43, 0x61, 0x66, 0xe9] + Array(" public notice tomorrow.".utf8))
        let decoded = try WebContentExtractor.extract(data: latin1, mimeType: "text/plain", now: now)
        expect(decoded.changes.first?.detail.hasPrefix("Café") == true, "bounded Latin-1 fallback remains available")
        let boundedTitle = try extract("<head><title>" + String(repeating: "é", count: 2_000) + "</title></head><p>Useful public notice.</p>")
        expect(boundedTitle.title.count == 160, "retained title stays within 160 characters")
        let many = try extract(String(repeating: "<p>Tomorrow public notice at 10 AM.</p>", count: 1_000))
        expect(many.extractedCharacterCount <= WatchedLinkLimits.extractedCharacters && many.changes.count <= WatchedLinkLimits.sections, "extracted text and semantic sections stay bounded")
        rejects(.responseTooLarge, "input above the network byte limit is rejected") {
            _ = try WebContentExtractor.extract(data: Data(repeating: 65, count: WatchedLinkLimits.responseBytes + 1), mimeType: "text/html", now: now)
        }
        for malformed in ["<p>Useful public text.</p><script>unfinished", "<head><title>unfinished", "<!-- unfinished", "<p title='unfinished>", "<nav><aside>hidden</nav></aside>", "<script/>hidden"] {
            rejects(.malformedContent, "unfinished or ambiguous markup fails closed") { _ = try extract(malformed) }
        }
        try adversarialCost()
        try await cancellation()
        print("Watched extraction checks: \(passed) passed, \(failed) failed. Offline production extractor only.")
        if failed > 0 { exit(1) }
    }

    static func adversarialCost() throws {
        let limit = WatchedLinkLimits.responseBytes
        let cases = [
            String(repeating: "<script>", count: limit / 8),
            String(repeating: "<title>", count: limit / 7) + String(repeating: "x", count: limit % 7),
            "<!--" + String(repeating: "x", count: limit - 4),
            "<p title='" + String(repeating: "x", count: limit - 10),
        ]
        let clock = ContinuousClock()
        for (index, text) in cases.enumerated() {
            let data = Data(text.utf8)
            expect(data.count == limit, "adversarial fixture \(index) reaches the full 512 KiB input boundary")
            let began = clock.now
            rejects(.malformedContent, "repeated or unfinished markup \(index) fails closed") {
                _ = try WebContentExtractor.extract(data: data, mimeType: "text/html", now: now)
            }
            let elapsed = seconds(began.duration(to: clock.now))
            expect(elapsed < 5, "full-size malformed fixture \(index) finishes within five seconds (\(String(format: "%.3f", elapsed))s)")
        }
    }

    static func cancellation() async throws {
        let reference = now
        let preCancelled = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try WebContentExtractor.extract(data: Data("Useful public text.".utf8), mimeType: "text/html", now: reference)
        }
        do { _ = try await preCancelled.value; expect(false, "pre-cancelled extraction") }
        catch is CancellationError { expect(true, "pre-cancelled extraction returns cancellation before decoding") }
        catch { expect(false, "pre-cancelled extraction returned another error") }

        // The repeated full-size workload cannot finish before the cancellation
        // signal. No test-only parser hooks or production overrides are added.
        let progress = ExtractionProgress()
        let input = Data(("<!--" + String(repeating: "x", count: WatchedLinkLimits.responseBytes - 50) + "--><p>Useful public notice.</p>").utf8)
        let work = Task.detached {
            await progress.markBegan()
            for _ in 0..<1_000 { _ = try WebContentExtractor.extract(data: input, mimeType: "text/html", now: reference) }
        }
        let startClock = ContinuousClock(), startDeadline = startClock.now.advanced(by: .seconds(2))
        while !(await progress.hasBegun()), startClock.now < startDeadline { await Task.yield() }
        expect(await progress.hasBegun(), "background extraction workload began")
        try await Task.sleep(for: .milliseconds(2))
        let clock = ContinuousClock(), cancelledAt = clock.now
        work.cancel()
        do { try await work.value; expect(false, "active extraction cancellation") }
        catch is CancellationError { expect(true, "active extraction workload observes cancellation") }
        catch { expect(false, "active extraction cancellation returned another error") }
        let elapsed = seconds(cancelledAt.duration(to: clock.now))
        expect(elapsed < 1, "active extraction cancellation returns within one second (\(String(format: "%.4f", elapsed))s)")
    }
}
