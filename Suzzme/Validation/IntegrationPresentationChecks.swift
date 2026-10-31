import Foundation

@main struct IntegrationPresentationChecks {
    static func main() {
        var passed = 0
        func expect(_ value: Bool, _ message: String) {
            precondition(value, message); passed += 1; print("PASS \(message)")
        }
        let github = IntegrationDescriptor.catalog.first { $0.id == .github }!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func account(state: IntegrationConnectionState = .ready, verified: Date? = now,
                     selected: Bool = false, repositories: [String] = ["owner/repo"], service: IntegrationID = .github) -> IntegrationAccount {
            .init(id: UUID(), service: service, providerID: "123", login: "owner", displayName: "Personal",
                  state: state, allowedRepositories: repositories, isDefault: selected, generation: UUID(),
                  lastVerifiedAt: verified, toolDigests: [:])
        }
        expect(IntegrationCatalogGroup.group(for: github, accounts: []) == .available, "GitHub with no account is available, not connected")
        expect(IntegrationCatalogGroup.group(for: github, accounts: [account()]) == .connected, "only ready verified account grouped connected")
        expect(IntegrationCatalogGroup.group(for: github, accounts: [account(verified: nil)]) == .attention, "ready without verification needs attention")
        for state in IntegrationConnectionState.allPresentationStates {
            expect(IntegrationCatalogGroup.group(for: github, accounts: [account(state: state)]) == .attention, "\(state) never healthy catalog")
        }
        expect(IntegrationCatalogGroup.group(for: github, accounts: [account(), account(state: .authExpired)]) == .attention, "mixed account health needs attention")
        expect(IntegrationCatalogGroup.group(for: github, accounts: [account(service: .notion)]) == .available, "unrelated account does not connect GitHub")
        for descriptor in IntegrationDescriptor.catalog where !descriptor.supportsRead {
            expect(IntegrationCatalogGroup.group(for: descriptor, accounts: []) == .setup, "\(descriptor.id) never falsely offered Connect")
            expect(IntegrationCatalogGroup.group(for: descriptor, accounts: [account(service: descriptor.id)]) == .setup,
                   "stored metadata cannot make unsupported \(descriptor.id) connected")
        }
        for descriptor in IntegrationDescriptor.catalog where descriptor.supportsRead {
            expect(IntegrationCatalogGroup.group(for: descriptor, accounts: []) == .available,
                   "implemented \(descriptor.id) offers setup without claiming account access")
            expect(IntegrationCatalogGroup.group(for: descriptor, accounts: [account(state: .authExpired, service: descriptor.id)]) == .attention,
                   "expired \(descriptor.id) never appears connected")
        }
        let notion = IntegrationDescriptor.catalog.first { $0.id == .notion }!
        expect(IntegrationCatalogGroup.group(for: notion, accounts: []) == .available, "implemented Notion requires explicit connection before Connected")
        let question = "Summarize https://github.com/Owner/Repo/issues/1"
        let invitation = IntegrationConnectionSuggestion.make(question: question, accounts: [])
        expect(invitation?.repository == "owner/repo" && invitation?.hasSavedAccount == false, "explicit resource yields scoped invitation")
        expect(IntegrationConnectionSuggestion.make(question: question, accounts: [account()]) == nil, "ready allowed account needs no invitation")
        expect(IntegrationConnectionSuggestion.make(question: question, accounts: [account(repositories: ["other/repo"])])?.hasSavedAccount == true, "scope denial asks review rather than new silent access")
        expect(IntegrationConnectionSuggestion.make(question: question, accounts: [account(state: .authExpired)])?.hasSavedAccount == true, "expired account asks explicit recovery")
        expect(IntegrationConnectionSuggestion.make(question: question, accounts: [account(), account()])?.hasSavedAccount == true, "multiple unselected accounts require review")
        expect(IntegrationConnectionSuggestion.make(question: question, accounts: [account(selected: true), account()]) == nil, "explicit ready default resolves ambiguity")
        expect(IntegrationConnectionSuggestion.make(question: question, accounts: [account(state: .authExpired, selected: true), account()]) != nil, "expired default cannot silently switch account")
        for invalid in ["", "Connect GitHub", "https://github.com", "https://github.com.evil.test/owner/repo", "https://evil.test/github.com/owner/repo", "https://user:secret@github.com/owner/repo", "http://github.com/owner/repo", "https://github.com:8443/owner/repo", "https://www.linkedin.com/in/person", "https://github.com/owner/repo https://github.com/other/repo", String(repeating: "x", count: 4_097) + question] {
            expect(IntegrationConnectionSuggestion.make(question: invalid, accounts: []) == nil, "invalid, ambiguous or unsupported explicit context rejected")
        }
        for verb in ["create", "delete", "publish", "send", "merge", "update", "edit", "close", "reopen", "write", "remember", "save"] {
            expect(IntegrationConnectionSuggestion.make(question: verb + " " + question, accounts: []) == nil, "\(verb) cannot become connection invitation")
        }
        expect(IntegrationConnectionSuggestion.make(question: "Explain https://github.com/owner/repo/blob/main/Sources/Test.swift", accounts: []) != nil, "invitation does not pretend ambiguous file ref was retrieved")
        print("Integration Presentation: \(passed) passed / 0 failed")
    }
}

private extension IntegrationConnectionState {
    static var allPresentationStates: [Self] { [.unconfigured, .authorizing, .connecting, .authExpired, .unavailable, .disabled] }
}
