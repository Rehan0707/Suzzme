import Foundation
import SwiftData

private actor GmailRequestLog {
    private(set) var formats: [String] = []
    func record(_ request: URLRequest) {
        if let value = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "format" })?.value { formats.append(value) }
    }
}

actor TestGmailAccount: GmailAuthorizationProviding {
    var identity = "account-A"
    var generation = UUID()
    var state = InformationHealthState.healthy
    var refreshFails = false
    private var selection = GmailSelection(mode: .recentInbox,
        generation: UUID(uuidString: "ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB")!)
    private var bodyAccess = false
    func gmailSelection() -> GmailSelection? { selection }
    func gmailBodyAccess() -> Bool { bodyAccess }
    func setBodyAccess(_ enabled: Bool) {
        bodyAccess = enabled
        selection = GmailSelection(mode: .recentInbox, generation: UUID(), includeBodies: enabled)
    }
    func revokeBodyAccess() { bodyAccess = false }
    func authorization() -> InformationHealthState { selection.includeBodies && !bodyAccess ? .permissionRequired : state }
    func accessGrant() throws -> GmailAccessGrant {
        guard authorization() == .healthy else { throw InformationError.authorizationRequired }
        if refreshFails { state = .authorizationExpired; throw InformationError.authorizationExpired }
        return .init(token: "test-only", accountNamespace: GmailAccessGrant.namespace(for: identity), generation: generation)
    }
    func validate(_ grant: GmailAccessGrant) throws {
        guard grant.generation == generation, grant.accountNamespace == GmailAccessGrant.namespace(for: identity) else { throw InformationError.staleCycle }
        guard state == .healthy else { throw InformationError.authorizationExpired }
    }
    func invalidate(_ grant: GmailAccessGrant, state: InformationHealthState) {
        if (try? validate(grant)) != nil { self.state = state }
    }
    func permitsGmailEvent(_ event: InformationEvent) -> Bool {
        authorization() == .healthy && event.externalID.hasPrefix(GmailAccessGrant.namespace(for: identity))
    }
    func switchAccount() { identity = "account-B"; generation = UUID(); state = .healthy }
    func revoke() { state = .permissionDenied }
    func failRefresh() { refreshFails = true }
}

/// Local synthetic observations exercise the production engine's selected
/// source boundary. No EventKit permission or network transport is involved.
actor IsolatedRefreshSource: InformationSource {
    let id: InformationSourceID
    private var fetches = 0
    private var permission: InformationHealthState = .healthy
    init(_ id: InformationSourceID) { self.id = id }
    func authorization() -> InformationHealthState { permission }
    func setPermission(_ value: InformationHealthState) { permission = value }
    func count() -> Int { fetches }
    func fetch(now: Date, checkpoint: Date?) -> InformationBatch {
        fetches += 1
        let observation = InformationObservation(externalID: "scoped-\(id.rawValue)",
                                                 title: "Selected \(id.title) fixture", modifiedAt: now)
        return .init(observations: [observation], complete: false,
                     window: DateInterval(start: now.addingTimeInterval(-86400), end: now))
    }
}

@main @MainActor struct ConnectorAcceptanceChecks {
    static var passed = 0
    static var failed = 0
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static func check(_ value: Bool, _ label: String) {
        if value { passed += 1; print("PASS \(label)") }
        else { failed += 1; print("FAIL \(label)") }
    }
    static func container(url: URL? = nil, readOnly: Bool = false) throws -> ModelContainer {
        let schema = Schema([StoredInformationEvent.self, StoredInformationSource.self])
        let configuration: ModelConfiguration
        if let url { configuration = ModelConfiguration(schema: schema, url: url, allowsSave: !readOnly, cloudKitDatabase: .none) }
        else { configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true) }
        return try ModelContainer(for: schema, configurations: configuration)
    }
    static func source(_ account: TestGmailAccount, status: Int = 200,
                       duringRequest: (@Sendable () async -> Void)? = nil) -> GmailInformationSource {
        GmailInformationSource(account: account, transport: { request in
            if let duringRequest { await duringRequest() }
            let url = request.url!
            let payload: String
            if url.path.hasSuffix("/messages") { payload = #"{"messages":[{"id":"mail-1"}]}"# }
            else { payload = #"{"id":"mail-1","internalDate":"1800000000000","labelIds":["INBOX"],"payload":{"headers":[{"name":"Subject","value":"Project review tomorrow"}]}}"# }
            return (Data(payload.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
    }
    static func main() async throws {
        let temporaryDirectory = ProcessInfo.processInfo.environment["SUZZME_VALIDATION_TMPDIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        let root = temporaryDirectory.appendingPathComponent("SuzzmeConnectorChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("information.sqlite")
        let store = InformationStore(modelContainer: try container(url: url))
        let engine = InformationEngine(registry: .init([UserSelectedMessageSource()]), store: store)
        let long = String(repeating: "Design review notes. ", count: 32)
        check(long.count > 240 && long.count <= InformationLimits.selectedMessageCharacters, "long-import boundary fixture")
        check(try await engine.importSelectedMessage(long, now: now) == .imported, "long import reports success")
        let saved = try await engine.retrieve(.init(sources: [.messages]), now: now)
        check(saved.count == 1 && saved.first?.title == long.trimmingCharacters(in: .whitespacesAndNewlines), "long import survives production pruning and retrieval")
        check(try await engine.importSelectedMessage(long, now: now.addingTimeInterval(1)) == .imported, "duplicate import is a successful no-op")
        check(try await engine.retrieve(.init(sources: [.messages]), now: now.addingTimeInterval(1)).count == 1, "duplicate creates exactly one current record")
        let restarted = InformationStore(modelContainer: try container(url: url))
        check(try await restarted.retrieve(.init(sources: [.messages]), now: now.addingTimeInterval(1)).first?.title == saved.first?.title, "long import persists after container restart")
        check(try await engine.importSelectedMessage("My password is secret", now: now.addingTimeInterval(2)) == .rejected, "protected message is rejected")
        do { _ = try await engine.importSelectedMessage("", now: now); check(false, "empty import rejected") }
        catch { check(true, "empty import rejected") }
        do { _ = try await engine.importSelectedMessage(String(repeating: "x", count: InformationLimits.selectedMessageCharacters + 1), now: now); check(false, "oversized import rejected") }
        catch { check(true, "oversized import rejected") }
        let readOnly = InformationStore(modelContainer: try container(url: url, readOnly: true))
        do { try await readOnly.removeAllObjects(source: .messages); check(false, "failed deletion propagates persistence error") }
        catch { check(true, "failed deletion propagates persistence error") }
        let afterFailure = InformationStore(modelContainer: try container(url: url))
        check(try await afterFailure.retrieve(.init(sources: [.messages]), now: now.addingTimeInterval(1)).count == 1, "failed deletion preserves persisted data")
        try await engine.removeAllObjects(source: .messages)
        check(try await engine.retrieve(.init(sources: [.messages]), now: now).isEmpty, "successful deletion removes imports")

        let account = TestGmailAccount()
        let gmailStore = InformationStore(modelContainer: try container())
        let gmail = InformationEngine(registry: .init([source(account)]), store: gmailStore)
        try await gmail.setEnabled(.gmail, enabled: true)
        try await gmail.refresh(force: true, now: now)
        let original = try await gmail.retrieve(.init(sources: [.gmail]), now: now)
        check(original.count == 1, "Gmail headers reach production store")
        check(original.first?.externalID.hasPrefix(GmailAccessGrant.namespace(for: "account-A")) == true, "Gmail records are account-scoped")
        let bodyAccount = TestGmailAccount()
        await bodyAccount.setBodyAccess(true)
        let encoded = Data("Project review moved to 3 PM. Bring the brief.".utf8).base64EncodedString()
        let full = """
        {"id":"mail-1","internalDate":"1800000000000","labelIds":["INBOX"],
        "payload":{"mimeType":"text/plain","headers":[{"name":"Subject","value":"Project review"}],
        "body":{"data":"\(encoded)"}}}
        """
        let metadata = #"{"id":"mail-1","internalDate":"1800000000000","labelIds":["INBOX"],"payload":{"headers":[{"name":"Subject","value":"Project review"}]}}"#
        let bodyRequests = GmailRequestLog()
        let bodySource = GmailInformationSource(account: bodyAccount, transport: { request in
            await bodyRequests.record(request)
            let payload = request.url!.path.hasSuffix("/messages") ? #"{"messages":[{"id":"mail-1"}]}"# : request.url!.query?.contains("format=full") == true ? full : metadata
            return (Data(payload.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, canSummarize: { true }, summarize: { input in
            GmailBodySummary(text: input.contains("moved to 3 PM") ? "Review moved to 3 PM" : "", usedOnDeviceModel: true)
        })
        let bodyEngine = InformationEngine(registry: .init([bodySource]), store: InformationStore(modelContainer: try container()))
        try await bodyEngine.setEnabled(.gmail, enabled: true)
        try await bodyEngine.refresh(force: true, now: now)
        let bodyEvents = try await bodyEngine.retrieve(.init(sources: [.gmail]), now: now)
        check(bodyEvents.count == 1 && bodyEvents[0].title.contains("Review moved to 3 PM"), "Gmail full message reaches on-device summary path")
        check(!bodyEvents[0].title.contains("Bring the brief"), "raw email body is not retained")
        check(await bodyRequests.formats == ["metadata", "full"], "message body is fetched only after recent metadata validation")
        let oversizedBodySource = GmailInformationSource(account: bodyAccount, transport: { request in
            let payload: Data
            if request.url!.path.hasSuffix("/messages") { payload = Data(#"{"messages":[{"id":"mail-1"}]}"#.utf8) }
            else if request.url!.query?.contains("format=full") == true { payload = Data(repeating: 65, count: GmailLimits.responseBytes + 1) }
            else { payload = Data(#"{"id":"mail-1","internalDate":"1800000000000","payload":{"headers":[{"name":"Subject","value":"Project review"}]}}"#.utf8) }
            return (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, canSummarize: { true }, summarize: { _ in GmailBodySummary(text: "", usedOnDeviceModel: false) })
        let oversizedBatch = try await oversizedBodySource.fetch(now: now, checkpoint: nil)
        check(oversizedBatch.observations.count == 1 && oversizedBatch.observations[0].title == "Project review",
              "oversized Gmail body falls back to bounded headers")
        let oldDate = Int(now.addingTimeInterval(-8 * 86_400).timeIntervalSince1970 * 1_000)
        let oldMetadata = """
        {"id":"mail-1","internalDate":"\(oldDate)","payload":{"headers":[{"name":"Subject","value":"Old message"}]}}
        """
        let oldRequests = GmailRequestLog()
        let oldSource = GmailInformationSource(account: bodyAccount, transport: { request in
            await oldRequests.record(request)
            let payload = request.url!.path.hasSuffix("/messages") ? #"{"messages":[{"id":"mail-1"}]}"# : oldMetadata
            return (Data(payload.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, canSummarize: { true }, summarize: { _ in GmailBodySummary(text: "Unexpected", usedOnDeviceModel: true) })
        let oldBatch = try await oldSource.fetch(now: now, checkpoint: nil)
        let oldFormats = await oldRequests.formats
        check(oldBatch.observations.isEmpty && oldFormats == ["metadata"],
              "old Gmail messages are excluded before any body request")
        await bodyAccount.revokeBodyAccess()
        check(await bodySource.authorization() == .permissionRequired, "revoked body scope blocks source")
        check(try await bodyEngine.retrieve(.init(sources: [.gmail]), now: now).isEmpty, "revoked body scope hides cached summary")
        let html = "<html><head><style>secret</style></head><body><p>Meeting &amp; notes</p><script>unsafe</script></body></html>"
        let htmlEncoded = Data(html.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        let htmlResponse = try JSONDecoder().decode(GmailMessageMetadataResponse.self, from: Data("""
        {"id":"mail-2","payload":{"mimeType":"text/html","body":{"data":"\(htmlEncoded)"}}}
        """.utf8))
        check(htmlResponse.readableBody()?.contains("Meeting & notes") == true && htmlResponse.readableBody()?.contains("unsafe") == false,
              "HTML-only Gmail body is decoded without scripts or styles")
        await account.switchAccount()
        check(try await gmail.retrieve(.init(sources: [.gmail]), now: now).isEmpty, "new account cannot retrieve previous account cache")
        try await gmail.refresh(force: true, now: now.addingTimeInterval(1))
        let newAccount = try await gmail.retrieve(.init(sources: [.gmail]), now: now.addingTimeInterval(1))
        check(newAccount.count == 1 && newAccount.first?.externalID != original.first?.externalID, "same Gmail message ID is isolated across accounts")
        await account.revoke()
        check(try await gmail.retrieve(.init(sources: [.gmail]), now: now).isEmpty, "revocation immediately blocks cached retrieval")

        for (status, expected) in [(401, InformationHealthState.authorizationExpired), (403, .permissionDenied)] {
            let owner = TestGmailAccount()
            let pipeline = InformationEngine(registry: .init([source(owner, status: status)]), store: InformationStore(modelContainer: try container()))
            try await pipeline.setEnabled(.gmail, enabled: true)
            try await pipeline.refresh(force: true, now: now)
            check(try await pipeline.health(now: now).first(where: { $0.source == .gmail })?.state == expected, "HTTP \(status) updates source health")
            check(try await pipeline.retrieve(.init(sources: [.gmail]), now: now).isEmpty, "HTTP \(status) cannot expose data")
        }
        let expired = TestGmailAccount()
        await expired.failRefresh()
        let expiredPipeline = InformationEngine(registry: .init([source(expired)]), store: InformationStore(modelContainer: try container()))
        try await expiredPipeline.setEnabled(.gmail, enabled: true)
        try await expiredPipeline.refresh(force: true, now: now)
        check(try await expiredPipeline.health(now: now).first(where: { $0.source == .gmail })?.state == .authorizationExpired, "token refresh failure becomes authorization-expired")

        for revoke in [false, true] {
            let owner = TestGmailAccount()
            let racing = source(owner, duringRequest: { if revoke { await owner.revoke() } else { await owner.switchAccount() } })
            let pipeline = InformationEngine(registry: .init([racing]), store: InformationStore(modelContainer: try container()))
            try await pipeline.setEnabled(.gmail, enabled: true)
            try await pipeline.refresh(force: true, now: now)
            check(try await pipeline.retrieve(.init(sources: [.gmail]), now: now).isEmpty, revoke ? "in-flight permission revocation cannot commit" : "in-flight account switch cannot commit")
        }

        let localCalendar = IsolatedRefreshSource(.calendar)
        let localReminders = IsolatedRefreshSource(.reminders)
        let externalMail = IsolatedRefreshSource(.gmail)
        let externalPage = IsolatedRefreshSource(.watchedWeb)
        let scopedStore = InformationStore(modelContainer: try container())
        let scoped = InformationEngine(registry: .init([localCalendar, localReminders, externalMail, externalPage]),
                                       store: scopedStore)
        for id in [InformationSourceID.calendar, .reminders, .gmail, .watchedWeb] {
            try await scoped.setEnabled(id, enabled: true)
        }
        try await scoped.refresh(source: .calendar, force: true, now: now)
        var calls = await [localCalendar.count(), localReminders.count(), externalMail.count(), externalPage.count()]
        check(calls == [1, 0, 0, 0], "Calendar-only refresh cannot fetch another enabled local or external source")
        let scopedRecords = try await scoped.retrieve(now: now)
        check(scopedRecords.count == 1 && scopedRecords.first?.source == .calendar,
              "selected Calendar refresh persists only its own observation")
        let firstHealth = try await scoped.health(now: now)
        check(firstHealth.filter { $0.source != .calendar }.allSatisfy { $0.lastAttempt == nil && $0.lastSuccess == nil },
              "a selected refresh leaves unrelated source checkpoints and health attempts untouched")
        try await scoped.refresh(source: .reminders, force: true, now: now.addingTimeInterval(1))
        calls = await [localCalendar.count(), localReminders.count(), externalMail.count(), externalPage.count()]
        check(calls == [1, 1, 0, 0], "Reminder-only refresh cannot trigger Calendar or enabled external intake")
        await localCalendar.setPermission(.permissionDenied)
        try await scoped.refresh(source: .calendar, force: true, now: now.addingTimeInterval(2))
        calls = await [localCalendar.count(), localReminders.count(), externalMail.count(), externalPage.count()]
        let deniedCalendarHealth = try await scoped.health(now: now.addingTimeInterval(2)).first { $0.source == .calendar }
        check(calls == [1, 1, 0, 0]
              && deniedCalendarHealth?.state == .authorizationExpired,
              "denied selected-source refresh reports access change without fetching other sources")
        try await scoped.setEnabled(.calendar, enabled: false)
        await localCalendar.setPermission(.healthy)
        try await scoped.refresh(source: .calendar, force: true, now: now.addingTimeInterval(3))
        calls = await [localCalendar.count(), localReminders.count(), externalMail.count(), externalPage.count()]
        let disabledCalendarHealth = try await scoped.health(now: now.addingTimeInterval(3)).first { $0.source == .calendar }
        check(calls == [1, 1, 0, 0]
              && disabledCalendarHealth?.enabled == false,
              "authorized Calendar refresh preserves the separate disabled intake opt-in")
        try await scoped.setEnabled(.calendar, enabled: true)
        try await scoped.refresh(source: .calendar, force: true, now: now.addingTimeInterval(4))
        calls = await [localCalendar.count(), localReminders.count(), externalMail.count(), externalPage.count()]
        check(calls == [2, 1, 0, 0], "enabling selected intake can refresh its source without contacting external sources")
        try await scoped.refresh(force: true, now: now.addingTimeInterval(5))
        calls = await [localCalendar.count(), localReminders.count(), externalMail.count(), externalPage.count()]
        check(calls == [3, 2, 1, 1], "explicit all-source refresh retains the original enabled-source behavior")
        try await transportAndSharedFileChecks(root: root)
        print("Connector acceptance: \(passed) passed / \(failed) failed")
        if failed > 0 { exit(1) }
    }

    static func transportAndSharedFileChecks(root: URL) async throws {
        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!)
        request.httpMethod = "GET"
        request.setValue("Bearer fixture", forHTTPHeaderField: "Authorization")
        check(GmailHTTPTransport.permits(request), "Gmail native metadata endpoint permitted")
        for value in ["http://gmail.googleapis.com/gmail/v1/users/me/messages",
                      "https://gmail.googleapis.com.attacker.invalid/gmail/v1/users/me/messages",
                      "https://user@gmail.googleapis.com/gmail/v1/users/me/messages",
                      "https://gmail.googleapis.com:443/gmail/v1/users/me/messages",
                      "https://gmail.googleapis.com/gmail/v1/users/me/messages/one/two",
                      "https://gmail.googleapis.com/gmail/v1/users/me/messages/one%2Ftwo",
                      "https://gmail.googleapis.com/gmail/v1/users/me/messages#fragment",
                      "https://gmail.googleapis.com/gmail/v1/users/me/threads"] {
            var invalid = request
            invalid.url = URL(string: value)!
            check(!GmailHTTPTransport.permits(invalid), "Gmail rejects unauthorized URL \(value)")
        }
        var write = request
        write.httpMethod = "POST"
        check(!GmailHTTPTransport.permits(write), "Gmail transport cannot mutate mail")
        var missingGrant = request
        missingGrant.setValue(nil, forHTTPHeaderField: "Authorization")
        check(!GmailHTTPTransport.permits(missingGrant), "Gmail requires explicit bearer grant")
        var body = request
        body.httpBody = Data("{}".utf8)
        check(!GmailHTTPTransport.permits(body), "Gmail read cannot carry a request body")

        for (list, metadata, label) in [
            (#"{"messages":[{"id":"../profile"}]}"#, "{}", "message path injection"),
            (#"{"messages":[{"id":"mail-1"},{"id":"mail-1"}]}"#, "{}", "duplicate list IDs"),
            (#"{"messages":[{"id":"mail-1"}]}"#, #"{"id":"another-message"}"#, "mismatched result identity"),
            (String(repeating: "x", count: GmailLimits.responseBytes + 1), "{}", "oversized result")
        ] {
            let source = GmailInformationSource(account: TestGmailAccount(), transport: { request in
                let payload = request.url!.path.hasSuffix("/messages") ? list : metadata
                return (Data(payload.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
            do { _ = try await source.fetch(now: now, checkpoint: nil); check(false, "Gmail rejects \(label)") }
            catch { check(true, "Gmail rejects \(label)") }
        }
        let redirected = GmailInformationSource(account: TestGmailAccount(), transport: { _ in
            (Data(#"{"messages":[]}"#.utf8), HTTPURLResponse(url: URL(string: "https://attacker.invalid/")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        do { _ = try await redirected.fetch(now: now, checkpoint: nil); check(false, "redirected Gmail responses never become data") }
        catch { check(true, "redirected Gmail responses never become data") }

        let preview = root.appendingPathComponent("shared.txt")
        let text = "Rehan: Our project review is Friday. Bring your notes."
        try Data(text.utf8).write(to: preview)
        check(try SelectedMessageTextFile.preview(preview) == text, "user-selected UTF-8 text opens without invented data")
        let previewStore = InformationStore(modelContainer: try container())
        let previewEngine = InformationEngine(registry: .init([UserSelectedMessageSource()]), store: previewStore)
        check(try await previewEngine.retrieve(now: now).isEmpty, "opening a text preview does not persist it")
        check(try await previewEngine.importSelectedMessage(SelectedMessageTextFile.preview(preview), now: now) == .imported,
              "explicit shared-file excerpt uses the real privacy and persistence pipeline")
        check(try await previewEngine.retrieve(.init(sources: [.messages]), now: now).first?.title == text,
              "shared-file excerpt can be read by existing context retrieval")
        try text.data(using: .utf16)!.write(to: preview)
        check(try SelectedMessageTextFile.preview(preview) == text, "UTF-16 chat text opens for review")
        for (data, label) in [(Data(), "empty"), (Data([0xff, 0xab, 0xcc]), "invalid encoding"),
                              (Data("private\0binary".utf8), "binary"),
                              (Data(repeating: 65, count: SelectedMessageTextFile.byteLimit + 1), "oversized")] {
            try data.write(to: preview)
            do { _ = try SelectedMessageTextFile.preview(preview); check(false, "shared text rejects \(label) file") }
            catch { check(true, "shared text rejects \(label) file") }
        }
        do { _ = try SelectedMessageTextFile.preview(root); check(false, "shared text cannot recursively read a directory") }
        catch { check(true, "shared text cannot recursively read a directory") }
        do { _ = try SelectedMessageTextFile.preview(URL(string: "https://example.invalid/chat.txt")!); check(false, "shared text never downloads a remote file") }
        catch { check(true, "shared text never downloads a remote file") }
    }
}
