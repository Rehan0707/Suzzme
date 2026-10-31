import Foundation

@main struct BrowserGitHubHandoffChecks {
    struct Fixture: Decodable { let url: String; let repository: String? }
    static func main() throws {
        var passed = 0
        func check(_ value: Bool, _ name: String) { precondition(value, name); passed += 1 }
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        for fixture in fixtures { check(BrowserIntegrationRoute.repository(in: fixture.url) == fixture.repository, "recognition \(fixture.url)") }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let requestURL = BrowserIntegrationRoute.url(for: .requestConnection, repository: "Owner/Repo")!
        let setupURL = BrowserIntegrationRoute.url(for: .openConnectionSetup, repository: "owner/repo")!
        check(BrowserIntegrationRoute.parse(requestURL)?.repository == "owner/repo", "canonical request roundtrip")
        check(BrowserIntegrationRoute.parse(setupURL)?.action == .openConnectionSetup, "setup roundtrip")
        let query = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)!.queryItems!
        check(query.count == 1 && query.first?.value == "owner/repo", "handoff only contains slug")
        for raw in ["suzzme://browser/github?repository=owner/repo&token=secret", "suzzme://browser/github?repository=owner/repo&repository=other/repo", "suzzme://browser/github?repository=owner/repo/issues/1", "suzzme://browser/github?repository=owner/repo#secret", "suzzme://browser/github?repository=owner%252Frepo", "suzzme://secret@browser/github?repository=owner/repo", "suzzme://browser:443/github?repository=owner/repo", "suzzme://evil/github?repository=owner/repo", "suzzme://browser/github?repository=owner/repo%3Ftoken=secret", "com.googleusercontent.apps.fixture:/oauth2redirect?code=private", "suzzme://ask", "suzzme://browser/github?repository=search/code"] {
            check(BrowserIntegrationRoute.parse(URL(string: raw)!) == nil, "malformed/non-browser route rejected")
        }
        for slug in ["owner/repo/", "owner/repo?token=secret", "owner/repo#fragment", "owner/repo/issues/1"] {
            check(BrowserIntegrationRoute.url(for: .requestConnection, repository: slug) == nil, "builder requires a canonical slug")
        }
        func account(_ state: IntegrationConnectionState = .ready, verified: Date? = now, allowed: [String] = ["owner/repo"], selected: Bool = false) -> IntegrationAccount {
            .init(id: UUID(), service: .github, providerID: UUID().uuidString, login: "test-account", displayName: "Test", state: state,
                  allowedRepositories: allowed, isDefault: selected, generation: UUID(), lastVerifiedAt: verified, toolDigests: [:])
        }
        var handoff = BrowserGitHubHandoff()
        check(handoff.receive(requestURL, now: now), "one route accepted")
        let first = handoff.request!
        check(handoff.phase == .queued, "launch delivery remains queued")
        check(!handoff.receive(requestURL, now: now), "duplicate delivery ignored")
        check(handoff.request?.id == first.id, "duplicate retains owner")
        handoff.resolve(id: UUID(), accounts: [], now: now)
        check(handoff.phase == .queued, "stale load cannot resolve replacement")
        handoff.resolve(id: first.id, accounts: [], now: now)
        check(handoff.phase == .review, "no account presents review")
        check(!handoff.decide(id: UUID(), openSetup: true, now: now), "stale Yes cannot open setup")
        check(handoff.decide(id: first.id, openSetup: true, now: now), "current Yes opens setup")
        check(handoff.phase == .setup, "Yes has no authorization state")
        let setup = handoff.takeSetup(now: now)
        check(setup?.repository == "owner/repo" && handoff.takeSetup(now: now) == nil, "setup prefill consumed exactly once")
        check(!handoff.receive(requestURL, now: now.addingTimeInterval(1)), "replay after Yes does not reopen sheet")
        for decision in [false, false] {
            handoff = BrowserGitHubHandoff(); _ = handoff.receive(requestURL, now: now)
            let request = handoff.request!; handoff.resolve(id: request.id, accounts: [], now: now)
            check(handoff.decide(id: request.id, openSetup: decision, now: now), "No/Not now accepted")
            check(handoff.request == nil && handoff.takeSetup(now: now) == nil, "dismissal cannot create setup")
            check(!handoff.receive(requestURL, now: now), "dismissed request does not resurrect")
        }
        let states: [IntegrationConnectionState] = [.unconfigured, .authorizing, .connecting, .authExpired, .unavailable, .disabled]
        for state in states {
            handoff = BrowserGitHubHandoff(); _ = handoff.receive(requestURL, now: now)
            handoff.resolve(id: handoff.request!.id, accounts: [account(state)], now: now)
            check(handoff.phase == .review, "\(state) cannot skip review")
        }
        for accounts in [[account(verified: nil)], [account(verified: now.addingTimeInterval(-31))], [account(verified: now.addingTimeInterval(1))], [account(allowed: ["other/repo"])], [account(), account()], [account(.authExpired, selected: true), account()]] {
            handoff = BrowserGitHubHandoff(); _ = handoff.receive(requestURL, now: now)
            handoff.resolve(id: handoff.request!.id, accounts: accounts, now: now)
            check(handoff.phase == .review, "unverified/stale/ambiguous/disallowed account needs review")
        }
        for accounts in [[account()], [account(selected: true), account()]] {
            handoff = BrowserGitHubHandoff(); _ = handoff.receive(requestURL, now: now)
            let id = handoff.request!.id; handoff.resolve(id: id, accounts: accounts, now: now)
            check(handoff.phase == .alreadyAllowed, "verified selected account avoids redundant prompt")
            check(handoff.decide(id: id, openSetup: true, now: now) && handoff.request == nil, "already allowed callback cannot open new setup")
        }
        handoff = BrowserGitHubHandoff(); _ = handoff.receive(requestURL, now: now)
        let old = handoff.request!.id; handoff.resolve(id: old, accounts: [], now: now)
        let otherURL = BrowserIntegrationRoute.url(for: .requestConnection, repository: "other/repo")!
        check(handoff.receive(otherURL, now: now), "new route replaces request")
        let replacement = handoff.request!.id
        check(!handoff.decide(id: old, openSetup: true, now: now), "old callback never acts on new repository")
        handoff.expire(id: old, now: now.addingTimeInterval(180)); check(handoff.request?.id == replacement, "old timeout cannot remove replacement")
        handoff.resolve(id: replacement, accounts: [], now: now)
        check(!handoff.decide(id: replacement, openSetup: true, now: now.addingTimeInterval(180)), "expired Yes denied")
        check(handoff.request == nil, "expired decision immediately retires request before timer")
        handoff.expire(id: replacement, now: now.addingTimeInterval(180)); check(handoff.request == nil, "expiry clears request")
        handoff = BrowserGitHubHandoff(); _ = handoff.receive(requestURL, now: now)
        handoff.resolve(id: handoff.request!.id, accounts: [], now: now.addingTimeInterval(180))
        check(handoff.request == nil, "late launch resolution retires expired queue")
        handoff = BrowserGitHubHandoff(); _ = handoff.receive(setupURL, now: now)
        handoff.resolve(id: handoff.request!.id, accounts: [], now: now)
        check(handoff.takeSetup(now: now.addingTimeInterval(180)) == nil && handoff.request == nil, "expired setup cannot remain pending or prefill sheet")
        handoff = BrowserGitHubHandoff(); _ = handoff.receive(setupURL, now: now)
        handoff.resolve(id: handoff.request!.id, accounts: [], now: now)
        check(handoff.takeSetup(now: now)?.repository == "owner/repo", "explicit setup URL remains setup-only")
        _ = handoff.receive(requestURL, now: now.addingTimeInterval(61))
        check(!handoff.receive(URL(string: "suzzme://browser/github?repository=bad")!, now: now.addingTimeInterval(61)) && handoff.request == nil, "invalid delivery clears pending request")
        print("GitHub Browser Handoff Swift: \(passed) passed / 0 failed (no provider calls)")
    }
}
