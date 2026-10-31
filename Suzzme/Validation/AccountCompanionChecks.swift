import Foundation
import os

private struct FixturePayload: Codable, Equatable {
    let version: Int
    let narration: String
}

private final class SummaryProtocol: URLProtocol, @unchecked Sendable {
    struct State: Sendable {
        var rows: [String: Data] = [:]
        var requests = 0
        var nextStatus: Int?
        var oversizedResponse = false
        var lastRequest: URLRequest?
    }
    static let state = OSAllocatedUnfairLock(initialState: State())

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "summary.suzzme.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            var data = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                guard count > 0 else { break }
                data.append(contentsOf: bytes.prefix(count))
            }
            body = data
        }
        let requestBody = body
        let (status, data) = Self.state.withLock { state -> (Int, Data) in
            state.requests += 1
            state.lastRequest = request
            if let status = state.nextStatus { state.nextStatus = nil; return (status, Data()) }
            if state.oversizedResponse { state.oversizedResponse = false; return (200, Data(repeating: 0, count: 65_537)) }
            guard request.url?.path == "/rest/v1/companion_summaries",
                  request.value(forHTTPHeaderField: "apikey") == "fixture-key" else { return (404, Data()) }
            let owner: String
            switch request.value(forHTTPHeaderField: "Authorization") {
            case "Bearer fixture-token-a": owner = "account-a"
            case "Bearer fixture-token-b": owner = "account-b"
            default: return (401, Data())
            }
            let query = Dictionary(uniqueKeysWithValues:
                (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                    .map { ($0.name, $0.value ?? "") })
            switch request.httpMethod {
            case "GET":
                guard query["firebase_uid"] == "eq.\(owner)", query["limit"] == "1",
                      query["select"] == "firebase_uid,payload" else { return (200, Data("[]".utf8)) }
                guard let row = state.rows[owner] else { return (200, Data("[]".utf8)) }
                return (200, Data("[".utf8) + row + Data("]".utf8))
            case "POST":
                guard query["on_conflict"] == "firebase_uid", let body = requestBody,
                      let row = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                      row["firebase_uid"] as? String == owner else { return (403, Data()) }
                state.rows[owner] = body
                return (201, Data())
            case "DELETE":
                guard query["firebase_uid"] == "eq.\(owner)" else { return (403, Data()) }
                state.rows.removeValue(forKey: owner)
                return (204, Data())
            default: return (405, Data())
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@main @MainActor struct AccountCompanionChecks {
    static var passed = 0
    static func check(_ value: Bool, _ label: String) {
        guard value else { print("FAIL \(label)"); exit(1) }
        passed += 1
        print("PASS \(label)")
    }
    static func main() async throws {
        let domain = "dev.suzzme.account-companion-checks.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: "suzzme.auth.continueAsGuest")
        defaults.set(true, forKey: "suzzme.mascot.didChooseColor")
        defaults.set(true, forKey: "hasCompletedWelcome")
        check(AccountWelcomeProgress.launchPhase(uid: nil, defaults: defaults) == .authentication,
              "remembered guest and onboarding flags cannot skip sign-in on a new launch")
        check(AccountWelcomeProgress.phase(uid: nil, guest: true, defaults: defaults) == .app,
              "an explicit guest choice still permits local use for this launch")
        check(AccountWelcomeProgress.launchPhase(uid: "account-a", defaults: defaults) == .mascotSelection,
              "a new authenticated account receives its own setup")
        defaults.set(true, forKey: AccountWelcomeProgress.colorChosenKey(for: "account-a"))
        check(AccountWelcomeProgress.launchPhase(uid: "account-a", defaults: defaults) == .onboarding,
              "global guest onboarding does not complete account onboarding")
        defaults.set(true, forKey: AccountWelcomeProgress.onboardingCompleteKey(for: "account-a"))
        check(AccountWelcomeProgress.launchPhase(uid: "account-a", defaults: defaults) == .app,
              "a restored signed-in account opens the app without requesting another login")
        check(AccountWelcomeProgress.launchPhase(uid: "account-b", defaults: defaults) == .mascotSelection,
              "switching accounts cannot reuse another account's setup")
        check(CompanionSummaryOwnership.permits(currentUID: "account-a", ownerUID: "account-a"), "summary presentation permits its signed-in owner")
        check(!CompanionSummaryOwnership.permits(currentUID: "account-b", ownerUID: "account-a"), "account switch immediately hides the prior account's summary")
        check(!CompanionSummaryOwnership.permits(currentUID: nil, ownerUID: "account-a"), "sign-out immediately hides the prior account's summary")

        func session() -> URLSession {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [SummaryProtocol.self]
            return URLSession(configuration: config)
        }
        let macSession = session(), phoneSession = session()
        defer { macSession.invalidateAndCancel(); phoneSession.invalidateAndCancel() }
        let url = URL(string: "https://summary.suzzme.invalid")!
        let mac = CompanionSummaryTransport(projectURL: url, publishableKey: "fixture-key", uid: "account-a",
                                           token: "fixture-token-a", session: macSession)
        let phone = CompanionSummaryTransport(projectURL: url, publishableKey: "fixture-key", uid: "account-a",
                                             token: "fixture-token-a", session: phoneSession)
        let other = CompanionSummaryTransport(projectURL: url, publishableKey: "fixture-key", uid: "account-b",
                                             token: "fixture-token-b", session: phoneSession)
        let payload = FixturePayload(version: 1, narration: "Your review is at eleven.")
        check(try await phone.load() == Data("[]".utf8), "no published summary remains a healthy empty response")
        try await mac.publish(payload)
        struct Row: Decodable { let firebase_uid: String; let payload: FixturePayload }
        let rows = try JSONDecoder().decode([Row].self, from: await phone.load())
        check(rows.count == 1 && rows[0].firebase_uid == "account-a" && rows[0].payload == payload,
              "separate Mac and iPhone sessions retrieve the same account's published summary")
        check(try await other.load() == Data("[]".utf8), "a different account cannot see the Mac summary")
        var spoof = other
        spoof = CompanionSummaryTransport(projectURL: url, publishableKey: "fixture-key", uid: "account-b",
                                         token: "fixture-token-a", session: phoneSession)
        check(try await spoof.load() == Data("[]".utf8), "a token cannot read another UID by changing the query")
        do { try await spoof.publish(payload); check(false, "foreign UID publication rejected") }
        catch CompanionSummaryStoreError.unavailable { check(true, "a token cannot publish another account's row") }
        try await other.publish(FixturePayload(version: 1, narration: "Other account."))
        try await mac.remove()
        check(try await phone.load() == Data("[]".utf8), "disabling Mac sharing removes the iPhone's server copy")
        check(try JSONDecoder().decode([Row].self, from: await other.load()).count == 1,
              "removal preserves other accounts' summaries")
        let calls = SummaryProtocol.state.withLock { $0.requests }
        do {
            try await mac.publish(FixturePayload(version: 1, narration: String(repeating: "x", count: 40_000)))
            check(false, "oversized publication rejected")
        } catch CompanionSummaryStoreError.invalidResponse {
            check(SummaryProtocol.state.withLock { $0.requests } == calls,
                  "oversized summaries are rejected before any upload")
        }
        SummaryProtocol.state.withLock { $0.nextStatus = 503 }
        do { _ = try await phone.load(); check(false, "outage rejected") }
        catch CompanionSummaryStoreError.unavailable { check(true, "an outage is an error rather than a fake empty summary") }
        SummaryProtocol.state.withLock { $0.oversizedResponse = true }
        do { _ = try await phone.load(); check(false, "oversized response rejected") }
        catch CompanionSummaryStoreError.invalidResponse { check(true, "oversized server responses are withheld") }
        _ = try await phone.load()
        let last = SummaryProtocol.state.withLock { $0.lastRequest! }
        check(last.timeoutInterval == 20 && last.cachePolicy == .reloadIgnoringLocalCacheData,
              "foreground refresh is bounded and bypasses stale HTTP caches")

        let queue = CompanionSummaryMutationQueue()
        var events: [String] = []
        var release: CheckedContinuation<Void, Never>?
        let upload = Task { await queue.run {
            events.append("upload-start")
            await withCheckedContinuation { release = $0 }
            events.append("upload-end")
        } }
        for _ in 0..<1000 where release == nil { await Task.yield() }
        check(release != nil, "in-flight upload fixture reaches suspension")
        let removal = Task { await queue.run { events.append("delete") } }
        for _ in 0..<50 { await Task.yield() }
        check(events == ["upload-start"], "turning sharing off waits for an in-flight upload")
        release?.resume()
        await upload.value
        await removal.value
        check(events == ["upload-start", "upload-end", "delete"],
              "delete finishes after upload so sharing cannot be resurrected")
        let formatter = ISO8601DateFormatter()
        let early = formatter.date(from: "2026-10-29T07:30:00Z")!
        let due = formatter.date(from: "2026-10-29T08:00:00Z")!
        let later = formatter.date(from: "2026-10-29T08:15:00Z")!
        let day = formatter.date(from: "2026-10-29T00:00:00Z")!
        let schedule = CompanionSummarySchedule(enabled: true, hour: 8, minute: 0, timeZoneIdentifier: "UTC")
        check(CompanionDeliveryPolicy.routineKey(schedule: schedule, generatedAt: early, localDay: day, now: early) == nil,
              "routine summary does not speak before the chosen time")
        let urgent = CompanionUrgentUpdate(id: "urgent-1", text: "A Mac-prepared urgent update.", createdAt: early,
                                          expiresAt: early.addingTimeInterval(900))
        check(CompanionDeliveryPolicy.urgentUpdates([urgent], alreadySpoken: [], now: early).count == 1,
              "urgent updates bypass the routine summary time")
        check(CompanionDeliveryPolicy.urgentUpdates([urgent], alreadySpoken: [urgent.id], now: early).isEmpty,
              "repeated polling cannot repeat an already spoken urgent update")
        check(CompanionDeliveryPolicy.urgentUpdates([urgent], alreadySpoken: [], now: later).isEmpty,
              "expired urgent updates are not spoken on a later app opening")
        check(CompanionDeliveryPolicy.routineKey(schedule: schedule, generatedAt: early, localDay: day, now: later) == nil,
              "a pre-schedule snapshot cannot masquerade as the scheduled summary")
        let key = CompanionDeliveryPolicy.routineKey(schedule: schedule, generatedAt: due, localDay: day, now: later)
        check(key != nil, "a fresh Mac-prepared summary is eligible after the chosen time")
        check(key == CompanionDeliveryPolicy.routineKey(schedule: schedule, generatedAt: later, localDay: day, now: later),
              "updated publications retain one routine readout key per scheduled day")
        check(CompanionDeliveryPolicy.routineKey(schedule: schedule, generatedAt: due, localDay: day.addingTimeInterval(-86400), now: later) == nil,
              "yesterday's summary cannot trigger today's routine narration")
        let indianSchedule = CompanionSummarySchedule(enabled: true, hour: 8, minute: 0, timeZoneIdentifier: "Asia/Kolkata")
        let indiaDue = formatter.date(from: "2026-10-29T02:30:00Z")!
        check(CompanionDeliveryPolicy.routineKey(schedule: indianSchedule, generatedAt: indiaDue,
              localDay: formatter.date(from: "2026-10-28T18:30:00Z")!, now: indiaDue) != nil,
              "the Mac's summary time zone controls the scheduled readout")
        CompanionPlaybackPreferences.markRoutine(key!, for: "account-a", defaults: defaults)
        CompanionPlaybackPreferences.markUrgent([urgent.id], for: "account-a", defaults: defaults)
        check(CompanionPlaybackPreferences.lastRoutine(for: "account-b", defaults: defaults) == nil
              && CompanionPlaybackPreferences.urgentIDs(for: "account-b", defaults: defaults).isEmpty,
              "readout receipts stay isolated between accounts")
        CompanionPlaybackPreferences.setUrgent(false, for: "account-a", defaults: defaults)
        check(!CompanionPlaybackPreferences.urgentEnabled(for: "account-a", defaults: defaults)
              && CompanionPlaybackPreferences.urgentEnabled(for: "account-b", defaults: defaults),
              "urgent speech preferences are scoped to each account")
        print("Account and companion checks: \(passed) passed. No live account or network used.")
    }
}
