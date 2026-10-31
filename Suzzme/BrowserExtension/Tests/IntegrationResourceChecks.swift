import Foundation

@main
enum IntegrationResourceChecks {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), "Resource check failed: \(name)")
            checks += 1
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func resolve(_ url: String) -> IntegrationResolvedResource? {
            IntegrationResourceResolver.resolve(url: url, capturedAt: now)
        }
        let issue = resolve("https://GITHUB.COM/Farzaa/Clicky/issues/0043/?tab=comments#discussion")!
        check(issue.serviceID == .github && issue.kind == .githubIssue, "GitHub issue recognition")
        check(issue.canonicalID == "github:farzaa/clicky/issues/43", "canonical namespace and number")
        check(issue.canonicalURL.absoluteString == "https://github.com/farzaa/clicky/issues/43", "query and fragment excluded")
        check(issue.attributes.owner == "farzaa" && issue.attributes.repository == "clicky" && issue.attributes.number == 43,
              "typed issue attributes")
        check(issue.provenance == .explicitURL && issue.capturedAt == now && issue.contextVersion == 1, "provenance and version")
        check(resolve("https://github.com/Farzaa/Clicky")?.kind == .githubRepository, "repository recognition")
        check(resolve("https://github.com/Farzaa/Clicky/pull/9")?.kind == .githubPullRequest, "PR recognition")
        let sha = String(repeating: "a", count: 40)
        let file = resolve("https://github.com/farzaa/clicky/blob/\(sha)/Sources/File.swift")!
        check(file.kind == .githubFile && file.attributes.ref == sha && file.attributes.file == "Sources/File.swift", "commit file target")
        let branchFile = resolve("https://github.com/farzaa/clicky/blob/feature/ui/File.swift")!
        check(branchFile.attributes.ref == nil && branchFile.attributes.file == nil
              && branchFile.attributes.unresolvedReferenceAndPath == ["feature", "ui", "File.swift"], "ambiguous ref is never guessed")
        check(resolve("https://linkedin.com/in/rehan-test")?.canonicalURL.host == "www.linkedin.com", "LinkedIn canonical origin")
        check(resolve("https://www.linkedin.com/posts/example-activity-123")?.kind == .linkedInPost, "LinkedIn post recognition")
        check(resolve("https://www.linkedin.com/feed/update/urn%3Ali%3Aactivity%3A123/")?.kind == .linkedInPost, "encoded LinkedIn activity")
        check(resolve("https://www.linkedin.com/company/example")?.kind == .linkedInPage, "LinkedIn page recognition")
        for url in [
            "http://github.com/owner/repo", "https://github.com.attacker.example/owner/repo", "https://github-login.example/owner/repo",
            "https://github.com.example.org/owner/repo", "https://github.com./owner/repo", "https://www.github.com/owner/repo",
            "https://github.com@evil.example/owner/repo", "https://attacker@github.com/owner/repo", "https://:secret@github.com/owner/repo",
            "https://github.com:8443/owner/repo", "https://127.0.0.1/owner/repo", "https://[::1]/owner/repo",
            "https://gıthub.com/owner/repo", "https://xn--gthub-9za.com/owner/repo", "https://github.com/owner%2Frepo/issues/1",
            "https://github.com/owner/repo%5Cother/issues/1", "https://github.com/owner/repo/issues/%2531",
            "https://github.com/owner/repo/blob/main/%252e%252e/secret", "https://github.com/owner/repo/blob/main/%2e%2e/secret",
            "https://github.com/owner/repo//issues/1", "https://github.com/owner/repo/issues/0", "https://github.com/owner/repo/issues/-1",
            "https://github.com/owner/repo/issues/99999999999999999999", "https://github.com/owner/repo/issues/1/other",
            "https://github.com/owner/repo/issues/1\n", "https://github.com/owner/repo\\evil", "https://linkedin.com.evil.example/in/example",
            "https://www.linkedin.com/in/example%2Fother", "https://www.linkedin.com/feed/update/urn:li:activity:0"
        ] { check(resolve(url) == nil, "reject \(url)") }
        check(resolve("https://github.com:443/owner/repo") != nil, "default HTTPS port")
        check(resolve("https://github.com/owner/repo/blob/main/a%00b") == nil, "encoded control rejected")

        let contextID = UUID()
        func browser(age: Double = 0, version: UInt64 = 7, title: String = "Issue", selectedText: String? = nil,
                     url: String = "https://github.com/owner/repo/issues/1") -> IntegrationBrowserContext {
            .init(contextID: contextID, contextVersion: version, capturedAt: now.addingTimeInterval(-age),
                  tabID: 2, windowID: 3, url: url, title: title, selectedText: selectedText)
        }
        check(browser().isCurrent(now: now), "fresh context")
        check(browser(age: 30).isCurrent(now: now), "TTL boundary")
        check(!browser(age: 30.01).isCurrent(now: now), "stale context")
        check(!browser(age: -0.01).isCurrent(now: now), "future context")
        check(!browser(version: 0).isCurrent(now: now), "zero version")
        check(!browser(version: IntegrationBrowserContext.maximumVersion + 1).isCurrent(now: now), "unsafe JS version")
        check(!browser(title: String(repeating: "é", count: 257)).isCurrent(now: now), "UTF-8 title bound")
        check(!browser(selectedText: String(repeating: "é", count: 4097)).isCurrent(now: now), "UTF-8 selection bound")
        check(!browser(title: "bad\0title").isCurrent(now: now), "null title rejected")
        if case .resolved(let target) = IntegrationResourceResolver.resolve(explicitURL: nil, browser: browser(), consequential: false, now: now) {
            check(target.contextID == contextID && target.contextVersion == 7 && target.provenance == .browserURL, "fresh browser provenance preserved")
        } else { preconditionFailure("fresh browser not resolved") }
        check(IntegrationResourceResolver.resolve(explicitURL: nil, browser: browser(age: 31), consequential: false, now: now) == .unavailable, "stale browser ignored")
        check(IntegrationResourceResolver.resolve(explicitURL: "https://github.com.attacker.example/owner/repo", browser: browser(), consequential: false, now: now) == .unavailable,
              "invalid explicit target never falls back")
        if case .resolved(let target) = IntegrationResourceResolver.resolve(explicitURL: "https://github.com/other/repo/issues/9", browser: browser(), consequential: false, now: now) {
            check(target.provenance == .explicitURL && target.attributes.owner == "other", "explicit target wins for read")
        } else { preconditionFailure("explicit target not resolved") }
        if case .ambiguous = IntegrationResourceResolver.resolve(explicitURL: "https://github.com/other/repo/issues/9", browser: browser(), consequential: true, now: now) {
            check(true, "consequential conflict requires clarification")
        } else { preconditionFailure("consequential conflict accepted") }
        if case .resolved = IntegrationResourceResolver.resolve(explicitURL: "https://github.com/owner/repo/issues/1", browser: browser(), consequential: true, now: now) {
            check(true, "matching target does not introduce ambiguity")
        } else { preconditionFailure("matching target not resolved") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let original = browser()
        let roundtrip = try decoder.decode(IntegrationBrowserContext.self, from: encoder.encode(original))
        check(roundtrip == original, "browser wire roundtrip")
        print("PASS: \(checks) integration resource checks")
    }
}
