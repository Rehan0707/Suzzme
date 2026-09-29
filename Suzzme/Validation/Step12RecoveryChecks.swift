import Foundation
import SwiftData
import Darwin

@main @MainActor
struct Step12RecoveryChecks {
    static var passed = 0
    static var failed = 0
    static func check(_ value: Bool, _ name: String) {
        print("\(value ? "PASS" : "FAIL") \(name)")
        if value { passed += 1 } else { failed += 1 }
    }
    static func rejected(_ body: () async throws -> Void) async -> Bool {
        do { try await body(); return false } catch { return true }
    }
    static func main() async throws {
        let args = CommandLine.arguments
        if args.count > 1 {
            let url = URL(fileURLWithPath: args[2])
            if ["information-", "watched-", "proactive-", "settings-"].contains(where: args[1].hasPrefix) {
                try await interruptedStoreOperation(args[1], url: url, now: Date(timeIntervalSince1970: Double(args[3])!))
                _exit(91)
            }
            if args[1].hasPrefix("sqlite-") {
                let schema = Schema([StoredSuzzmeItem.self, StoredSuzzmeMemory.self, StoredSuzzmeMemoryRelationship.self])
                let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
                let context = ModelContext(container); context.autosaveEnabled = false
                if args[1].contains("delete") {
                    for row in try context.fetch(FetchDescriptor<StoredSuzzmeMemory>()) { context.delete(row) }
                } else {
                    context.insert(StoredSuzzmeMemory(type: .project, name: "Interrupted project", detail: "Durable record", confidence: 1, importance: .normal, provenance: .userExplicit))
                }
                if args[1].hasSuffix("after") { try context.save() }
                _exit(91)
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: args[3]))
            if args[1] == "partial" {
                try data.prefix(data.count / 2).write(to: RecoverableJSONFile.temporaryURL(for: url))
                _exit(91)
            }
            try RecoverableJSONFile.write(data, to: url) { boundary in
                if String(describing: boundary) == args[1] { _exit(91) }
            }
            _exit(0)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmeRecovery-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let seed = root.appendingPathComponent("seed.json")
        _ = try await WatchedLinkStore(fileURL: seed).add(name: "Original", url: "https://example.edu/notices")
        let original = try Data(contentsOf: seed)
        let next = root.appendingPathComponent("next.json")
        _ = try await WatchedLinkStore(fileURL: next).add(name: "Replacement", url: "https://example.edu/news")
        let empty = Data("{\"schemaVersion\":1,\"links\":[]}".utf8)
        let deleted = root.appendingPathComponent("deleted.json"); try empty.write(to: deleted)
        for deleting in [false, true] {
            for phase in ["partial", "temporaryWritten", "recoveryRetired", "primaryReplaced", "recoveryWritten"] {
                let file = root.appendingPathComponent("\(deleting)-\(phase).json")
                try RecoverableJSONFile.write(original, to: file)
                let process = Process(); process.executableURL = URL(fileURLWithPath: args[0])
                process.arguments = [phase, file.path, (deleting ? deleted : next).path]
                try process.run(); process.waitUntilExit()
                let committed = phase == "primaryReplaced" || phase == "recoveryWritten"
                let records = try await WatchedLinkStore(fileURL: file).records()
                let expected = committed ? (deleting ? [] : ["Replacement"]) : ["Original"]
                check(process.terminationStatus == 91 && records.map(\.name) == expected, "process death \(phase), delete=\(deleting), trustworthy commit only")
                let second = try await WatchedLinkStore(fileURL: file).records()
                check(second.map(\.id) == records.map(\.id), "second reopen stable \(phase), delete=\(deleting)")
                if deleting && committed {
                    try Data("broken".utf8).write(to: file)
                    let restored = try await WatchedLinkStore(fileURL: file).records()
                    check(restored.isEmpty, "recovery cannot resurrect committed deletion \(phase)")
                }
            }
        }
        let corruptions: [(String, Data)] = [
            ("zero", Data()), ("truncated", original.prefix(original.count / 2)),
            ("malformed-version", Data("{\"schemaVersion\":\"bad\",\"links\":[]}".utf8)),
            ("invalid-json", Data("{bad}".utf8))
        ]
        for (label, bad) in corruptions {
            let file = root.appendingPathComponent("corrupt-\(label).json")
            try RecoverableJSONFile.write(original, to: file); try bad.write(to: file)
            check(try await WatchedLinkStore(fileURL: file).records().map(\.name) == ["Original"], "\(label) primary uses validated recovery")
            try bad.write(to: file); try bad.write(to: RecoverableJSONFile.recoveryURL(for: file))
            check(await rejected { _ = try await WatchedLinkStore(fileURL: file).records() }, "both \(label) fail safely")
        }
        let future = root.appendingPathComponent("future.json")
        try RecoverableJSONFile.write(original, to: future)
        let futureData = Data("{\"schemaVersion\":999,\"links\":[]}".utf8); try futureData.write(to: future)
        check(await rejected { _ = try await WatchedLinkStore(fileURL: future).records() }, "future primary never silently downgraded to recovery")
        check(try Data(contentsOf: future) == futureData, "unsupported future preserved intact")
        let valid = root.appendingPathComponent("valid.json")
        try RecoverableJSONFile.write(original, to: valid)
        try Data("broken".utf8).write(to: RecoverableJSONFile.recoveryURL(for: valid))
        check(try await WatchedLinkStore(fileURL: valid).records().count == 1, "valid primary wins over corrupt recovery")
        let missing = root.appendingPathComponent("missing.json")
        try original.write(to: RecoverableJSONFile.recoveryURL(for: missing))
        check(try await WatchedLinkStore(fileURL: missing).records().count == 1, "missing primary repaired from valid recovery")
        var object = try JSONSerialization.jsonObject(with: original) as! [String: Any]
        let links = object["links"] as! [[String: Any]]; object["links"] = links + links
        let duplicate = root.appendingPathComponent("duplicate.json")
        try JSONSerialization.data(withJSONObject: object).write(to: duplicate)
        check(await rejected { _ = try await WatchedLinkStore(fileURL: duplicate).records() }, "duplicate identifiers fail closed without valid recovery")
        for phase in ["temporaryWritten", "primaryReplaced"] {
            let file = root.appendingPathComponent("cancel-\(phase).json")
            try RecoverableJSONFile.write(original, to: file)
            let result = await Task { () -> Bool in
                do {
                    try RecoverableJSONFile.write(empty, to: file) { boundary in
                        if String(describing: boundary) == phase { withUnsafeCurrentTask { $0?.cancel() } }
                    }
                    return false
                } catch is CancellationError { return true } catch { return false }
            }.value
            let records = try await WatchedLinkStore(fileURL: file).records()
            check(result && records.count == (phase == "primaryReplaced" ? 0 : 1), "cancellation \(phase) reports no phantom success and reopens actual commit")
        }
        let proactive = root.appendingPathComponent("proactive.json")
        var preferences = ProactivePreferences(); preferences.dailyBriefingEnabled = false
        try await ProactiveIntelligenceStore(fileURL: proactive).updatePreferences(preferences)
        try Data().write(to: proactive)
        check(try await ProactiveIntelligenceStore(fileURL: proactive).preferences().dailyBriefingEnabled == false, "proactive preferences recover through full store validation")
        try await resetCommitFailures(root)
        try await recoveryPrivacy(root)
        try await sourceReset(root)
        try await sqliteRestarts(root)
        try await interruptedStoreRestarts(root)
        try await repeatedIntake(root)
        try await repeatedUse(root)
        print("Remediation recovery checks passed: \(passed)")
        print("Remediation recovery checks failed: \(failed)")
        if failed > 0 { exit(1) }
    }
    /// The helper process exits without Swift defers, actor teardown or a normal application exit.
    /// Public store methods define the commit boundaries; private implementation details are not overridden.
    static func runKilledChild(_ phase: String, file: URL, now: Date) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [phase, file.path, String(now.timeIntervalSince1970)]
        try process.run(); process.waitUntilExit()
        return process.terminationStatus == 91
    }
    struct CycleRecord: Codable {
        let id: UUID
        let source: InformationSourceID
        let checkpoint: Date?
        init(_ value: InformationCycle) { id = value.id; source = value.source; checkpoint = value.checkpoint }
        var cycle: InformationCycle { .init(id: id, source: source, checkpoint: checkpoint) }
    }
    static func informationContainer(_ url: URL) throws -> ModelContainer {
        let schema = Schema([StoredInformationEvent.self, StoredInformationSource.self])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
    }
    static func informationBatch(_ title: String, now: Date) -> InformationBatch {
        .init(observations: [.init(externalID: "restart-fixture", title: title, modifiedAt: now, effectiveAt: now.addingTimeInterval(3600))], complete: true, window: .init(start: now, duration: 86400))
    }
    static func webResponse(_ url: URL, title: String) -> WatchedLinkFetchResponse {
        .init(finalURL: url, statusCode: 200, mimeType: "text/html", data: Data("<html><head><title>\(title)</title></head><body><p>\(title) project timetable is published for review.</p></body></html>".utf8), etag: title, lastModified: nil)
    }
    static func commitPage(_ store: WatchedLinkStore, refresh: WatchedLinkRefresh, title: String, now: Date) async throws {
        let response = webResponse(refresh.record.canonicalURL, title: title)
        let extraction = try WebContentExtractor.extract(data: response.data, mimeType: response.mimeType, now: now)
        _ = try await store.commit(refresh.record.id, generation: refresh.generation, response: response, extraction: extraction, now: now)
    }
    static func interruptedStoreOperation(_ phase: String, url: URL, now: Date) async throws {
        let tokenURL = url.appendingPathExtension("owner.json")
        if phase.hasPrefix("information-") {
            let store = InformationStore(modelContainer: try informationContainer(url))
            let cycle = try await store.begin(.calendar, now: now)
            try JSONEncoder().encode(CycleRecord(cycle)).write(to: tokenURL)
            if phase.hasSuffix("after") { try await store.commit(informationBatch("Replacement meeting", now: now), cycle: cycle, now: now) }
            if phase.hasSuffix("delete") { try await store.removeAllObjects(source: .calendar) }
            if phase.hasSuffix("disable") { try await store.setEnabled(.calendar, enabled: false) }
            if phase.hasSuffix("failure") { try await store.fail(cycle, state: .error) }
        } else if phase.hasPrefix("watched-") {
            let store = WatchedLinkStore(fileURL: url)
            let record = try await store.records(now: now)[0]
            let refresh = try await store.begin(record.id, now: now, force: true)!
            try JSONEncoder().encode(refresh.generation).write(to: tokenURL)
            if phase.hasSuffix("after") { try await commitPage(store, refresh: refresh, title: "Replacement", now: now) }
            if phase.hasSuffix("delete") { try await store.remove(record.id) }
            if phase.hasSuffix("disable") { try await store.setEnabled(record.id, enabled: false) }
            if phase.hasSuffix("failure") { try await store.fail(record.id, generation: refresh.generation, error: .timeout, now: now) }
        } else if phase.hasPrefix("proactive-") {
            let store = ProactiveIntelligenceStore(fileURL: url)
            let (generation, _) = try await store.beginGeneration()
            try JSONEncoder().encode(generation).write(to: tokenURL)
            if phase.hasSuffix("after") {
                let snapshot = try JSONDecoder().decode(ProactiveSnapshot.self, from: Data(contentsOf: url.appendingPathExtension("candidate.json")))
                try await store.commit(snapshot, generation: generation, now: now)
            }
            if phase.hasSuffix("delete") { try await store.clearProactiveContent() }
        } else if phase.hasPrefix("settings-") {
            let engine = ProactiveIntelligenceEngine(store: ProactiveIntelligenceStore(fileURL: url))
            let coordinator = SuzzmeSettingsCapabilityCoordinator(proactive: engine)
            let requestID = UUID()
            let plan = try SuzzmeSettingsPlanner().plan(for: "Turn off daily summary", requestID: requestID, now: now)!
            try JSONEncoder().encode(plan).write(to: tokenURL)
            await coordinator.begin(requestID: requestID)
            if phase.hasSuffix("after") { _ = try await coordinator.execute(plan, requestID: requestID, now: now) }
        }
    }
    static func preparedSnapshot(_ file: URL, title: String, now: Date) async throws -> ProactiveSnapshot {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let candidate = ProactiveCandidate(id: "restart-meeting", kind: .schedule, title: title, summary: title, source: "calendar", sourceReference: "restart-meeting", effectiveAt: now.addingTimeInterval(3600), effectiveUntil: now.addingTimeInterval(7200), freshness: .current, sourceHealthy: true)
        return try await ProactiveIntelligenceEngine(store: ProactiveIntelligenceStore(fileURL: file)).prepare(input: .init(candidates: [candidate], generatedAt: now), now: now, calendar: calendar)
    }
    static func interruptedStoreRestarts(_ root: URL) async throws {
        let now = Date.now
        let earlier = now.addingTimeInterval(-60)
        for phase in ["before", "after", "delete", "disable", "failure"] {
            let file = root.appendingPathComponent("information-interrupted-\(phase).store")
            let container = try informationContainer(file)
            let store = InformationStore(modelContainer: container)
            try await store.setEnabled(.calendar, enabled: true)
            let seed = try await store.begin(.calendar, now: earlier)
            try await store.commit(informationBatch("Original meeting", now: earlier), cycle: seed, now: earlier)
            check(try runKilledChild("information-\(phase)", file: file, now: now), "Information \(phase) uses real abrupt process exit")
            let dead = try JSONDecoder().decode(CycleRecord.self, from: Data(contentsOf: file.appendingPathExtension("owner.json")))
            for reopening in 1...2 {
                let reopenedContainer = try informationContainer(file)
                let reopened = InformationStore(modelContainer: reopenedContainer)
                let rows = try ModelContext(reopenedContainer).fetch(FetchDescriptor<StoredInformationEvent>()).filter { !$0.isSuperseded }
                let expected = phase == "delete" ? [] : [phase == "after" ? "Replacement meeting" : "Original meeting"]
                let health = try await reopened.health(now: now).first { $0.source == .calendar }
                let visible = try await reopened.retrieve(now: now)
                let expectedHealth: InformationHealthState = switch phase { case "after": .healthy; case "disable": .disabled; case "failure": .error; default: .stale }
                check(rows.map(\.title) == expected && health?.state == expectedHealth, "Information \(phase) reopen \(reopening) preserves committed rows and truthful source health")
                check(visible.map(\.title) == (phase == "after" ? expected : []), "Information \(phase) reopen \(reopening) never exposes incomplete refresh as current")
                check(await rejected { try await reopened.commit(informationBatch("Stale callback", now: now), cycle: dead.cycle, now: now) }, "Information \(phase) reopen \(reopening) rejects dead-process ownership")
            }
        }
        for phase in ["before", "after", "delete", "disable", "failure"] {
            let file = root.appendingPathComponent("watched-interrupted-\(phase).json")
            let store = WatchedLinkStore(fileURL: file)
            let original = try await store.add(name: "University page", url: "https://example.edu/notice")
            let seed = try await store.begin(original.id, now: earlier, force: true)!
            try await commitPage(store, refresh: seed, title: "Original", now: earlier)
            check(try runKilledChild("watched-\(phase)", file: file, now: now), "Watched \(phase) uses real abrupt process exit")
            let dead = try JSONDecoder().decode(UUID.self, from: Data(contentsOf: file.appendingPathExtension("owner.json")))
            for reopening in 1...2 {
                let reopened = WatchedLinkStore(fileURL: file)
                let rows = try await reopened.records(now: now)
                let expectedState: WatchedLinkState = switch phase { case "after": .changed; case "disable": .disabled; case "failure": .offline; default: .stale }
                check(phase == "delete" ? rows.isEmpty : rows.count == 1 && rows[0].state == expectedState && rows[0].pageTitle == (phase == "after" ? "Replacement" : "Original"), "Watched \(phase) reopen \(reopening) preserves committed content and exits refreshing state")
                check(await rejected { _ = try await reopened.commit(original.id, generation: dead, response: webResponse(original.canonicalURL, title: "Stale"), extraction: nil, now: now) }, "Watched \(phase) reopen \(reopening) rejects dead-process callbacks")
                if phase == "failure" { check(rows[0].consecutiveFailures == 1 && rows[0].nextEligibleRefresh! > now && rows[0].lastSuccess == earlier, "Watched failed refresh reopen \(reopening) preserves backoff and last verified success") }
            }
        }
        let next = try await preparedSnapshot(root.appendingPathComponent("next-snapshot.json"), title: "Replacement meeting", now: now)
        check(next.briefing?.items.count == 1 && next.dailyContext?.entries.count == 1, "Restart fixture produced by real relevance and Daily Context engine")
        for phase in ["before", "after", "delete"] {
            let file = root.appendingPathComponent("proactive-interrupted-\(phase).json")
            let original = try await preparedSnapshot(file, title: "Original meeting", now: earlier)
            try JSONEncoder().encode(next).write(to: file.appendingPathExtension("candidate.json"))
            check(try runKilledChild("proactive-\(phase)", file: file, now: now), "Summary/Today \(phase) uses real abrupt process exit")
            let dead = try JSONDecoder().decode(UUID.self, from: Data(contentsOf: file.appendingPathExtension("owner.json")))
            for reopening in 1...2 {
                let reopened = ProactiveIntelligenceStore(fileURL: file)
                let state = try await reopened.current(now: now)
                let expected = phase == "delete" ? [] : [phase == "after" ? "Replacement meeting" : "Original meeting"]
                check((state.briefing?.items.map(\.summary) ?? []) == expected && (state.dailyContext?.entries.map(\.title) ?? []) == expected, "Summary/Today \(phase) reopen \(reopening) has one consistent committed snapshot")
                check(state.briefing?.id == (phase == "delete" ? nil : phase == "after" ? next.briefing?.id : original.briefing?.id), "Summary/Today \(phase) reopen \(reopening) preserves summary identity")
                check(await rejected { try await reopened.commit(next, generation: dead, now: now) }, "Summary/Today \(phase) reopen \(reopening) rejects dead-process generation")
            }
        }
        for phase in ["before", "after"] {
            let file = root.appendingPathComponent("settings-interrupted-\(phase).json")
            try await ProactiveIntelligenceStore(fileURL: file).updatePreferences(.init())
            check(try runKilledChild("settings-\(phase)", file: file, now: now), "Settings \(phase) uses real abrupt process exit through capability coordinator")
            let plan = try JSONDecoder().decode(SuzzmeSettingsPlan.self, from: Data(contentsOf: file.appendingPathExtension("owner.json")))
            for reopening in 1...2 {
                let store = ProactiveIntelligenceStore(fileURL: file)
                check(try await store.preferences().dailyBriefingEnabled == (phase == "before"), "Settings \(phase) reopen \(reopening) retains only committed change")
                let coordinator = SuzzmeSettingsCapabilityCoordinator(proactive: ProactiveIntelligenceEngine(store: store))
                check(await rejected { _ = try await coordinator.execute(plan, requestID: plan.requestID, now: now) }, "Settings \(phase) reopen \(reopening) cannot replay dead request without active owner")
            }
        }
    }
    static func repeatedIntake(_ root: URL) async throws {
        let now = Date.now
        let watched = WatchedLinkStore(fileURL: root.appendingPathComponent("repeated-watched.json"))
        let link = try await watched.add(name: "University notices", url: "https://example.edu/notice")
        let infoURL = root.appendingPathComponent("repeated-information.store")
        let container = try informationContainer(infoURL)
        let info = InformationStore(modelContainer: container)
        try await info.setEnabled(.calendar, enabled: true)
        var bounded = true
        var samples = [residentBytes()]
        for index in 0..<100 {
            let date = now.addingTimeInterval(Double(index))
            let cancelled = try await watched.begin(link.id, now: date, force: true)!
            try await watched.cancel(link.id, generation: cancelled.generation)
            let active = try await watched.begin(link.id, now: date, force: true)!
            try await commitPage(watched, refresh: active, title: "Revision \(index)", now: date)
            let staleRejected = await rejected { _ = try await watched.commit(link.id, generation: cancelled.generation, response: webResponse(link.canonicalURL, title: "Cancelled"), extraction: nil, now: date) }
            let stale = try await info.begin(.calendar, now: date)
            let cycle = try await info.begin(.calendar, now: date)
            let staleInfoRejected = await rejected { try await info.commit(informationBatch("Cancelled meeting", now: date), cycle: stale, now: date) }
            try await info.commit(informationBatch("Meeting revision \(index)", now: date), cycle: cycle, now: date)
            let records = try await watched.records(now: date)
            let visible = try await info.retrieve(now: date)
            bounded = bounded && staleRejected && staleInfoRejected && records.count == 1 && records[0].changes.count <= WatchedLinkLimits.sections && visible.count == 1
            if index % 20 == 19 { samples.append(residentBytes()) }
        }
        check(bounded, "100 Watched refresh/cancel and Information supersession cycles preserve bounded ownership")
        let reopenedContainer = try informationContainer(infoURL)
        let rows = try ModelContext(reopenedContainer).fetch(FetchDescriptor<StoredInformationEvent>())
        check(rows.count <= InformationLimits.versions && rows.filter { !$0.isSuperseded }.count == 1, "100 Information updates retain only bounded versions across restart")
        let reopenedWatched = try await WatchedLinkStore(fileURL: root.appendingPathComponent("repeated-watched.json")).records(now: now.addingTimeInterval(100))
        check(reopenedWatched.count == 1 && reopenedWatched[0].pageTitle == "Revision 99", "100 Watched refreshes retain latest verified page across restart")
        print("MEASUREMENT Watched/Information 100-cycle RSS bytes: \(samples)")
    }
    static func sqliteRestarts(_ root: URL) async throws {
        let schema = Schema([StoredSuzzmeItem.self, StoredSuzzmeMemory.self, StoredSuzzmeMemoryRelationship.self])
        func run(_ phase: String, _ url: URL) throws {
            let process = Process(); process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); process.arguments = [phase, url.path]
            try process.run(); process.waitUntilExit()
            check(process.terminationStatus == 91, "real process terminated at \(phase)")
        }
        for boundary in ["before", "after"] {
            let url = root.appendingPathComponent("sqlite-\(boundary).store")
            try run("sqlite-insert-\(boundary)", url)
            for reopen in 1...2 {
                let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
                let records = try await LongTermMemoryStore(modelContainer: container).allMemories()
                check(records.count == (boundary == "after" ? 1 : 0), "SQLite insert \(boundary) reopen \(reopen) sees only committed records")
            }
            if boundary == "before" { try run("sqlite-insert-after", url) }
            try run("sqlite-delete-\(boundary)", url)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let records = try await LongTermMemoryStore(modelContainer: container).allMemories()
            check(records.count == (boundary == "after" ? 0 : 1), "SQLite deletion \(boundary) preserves transaction boundary")
        }
    }
    static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info(); var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return status == KERN_SUCCESS ? info.resident_size : 0
    }
    static func repeatedUse(_ root: URL) async throws {
        let url = root.appendingPathComponent("stress.json")
        let engine = ProactiveIntelligenceEngine(store: ProactiveIntelligenceStore(fileURL: url))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.startOfDay(for: Date())
        var samples: [UInt64] = [residentBytes()]
        var bounded = true
        for index in 0..<100 {
            let date = now.addingTimeInterval(Double(index) * 60)
            let candidate = ProactiveCandidate(id: "class", kind: .schedule, title: "Project review", summary: "Updated meeting", source: "calendar", sourceReference: "class", effectiveAt: date.addingTimeInterval(3600), effectiveUntil: date.addingTimeInterval(7200), freshness: .current, sourceHealthy: true)
            let result = try await engine.prepare(input: .init(candidates: [candidate], generatedAt: date), now: date, calendar: calendar)
            bounded = bounded && (result.dailyContext?.entries.count ?? 999) <= 24 && (result.briefing?.items.count ?? 999) <= 8
            await engine.cancel()
            var preferences = try await engine.preferences(); preferences.briefingMinute = index % 60
            try await engine.updatePreferences(preferences)
            if index % 20 == 19 { samples.append(residentBytes()) }
        }
        check(bounded, "100 real summary/Today preparations and cancellations remain bounded")
        let disk = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        check((disk["briefings"] as? [Any])?.count == 3, "100 generations persist only three summaries")
        let reopened = ProactiveIntelligenceStore(fileURL: url)
        check(try await reopened.preferences().briefingMinute == 39, "repeated settings updates survive restart")
        let tomorrow = try await reopened.current(now: now.addingTimeInterval(86400))
        check(tomorrow.dailyContext?.entries.isEmpty ?? true, "restart on next day expires old Today context")
        print("MEASUREMENT summary/context/settings 100-cycle RSS bytes: \(samples)")
    }
    static func resetCommitFailures(_ root: URL) async throws {
        let watchedURL = root.appendingPathComponent("reset-fault-watched.json")
        _ = try await WatchedLinkStore(fileURL: watchedURL).add(name: "Original", url: "https://example.edu/original")
        let watched = WatchedLinkStore(fileURL: watchedURL, write: { data, url in
            let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let resetting = (object["links"] as? [Any])?.isEmpty == true
            try RecoverableJSONFile.write(data, to: url) { boundary in
                if resetting && boundary == .primaryReplaced { throw CocoaError(.fileWriteUnknown) }
            }
        })
        _ = try await watched.records()
        check(await rejected { try await watched.reset() }, "watched reset surfaces post-commit mirror failure")
        // Reading an empty store also attempts normalization persistence; the
        // injected disk remains failed. It must not expose the old cached link.
        check(await rejected { _ = try await watched.records() }, "same watched actor cannot serve pre-reset cache after commit failure")
        let reopened = WatchedLinkStore(fileURL: watchedURL)
        check(try await reopened.records().isEmpty, "watched reset really committed despite caller failure")
        _ = try await reopened.add(name: "New", url: "https://example.edu/new")
        check(try await reopened.records().map(\.name) == ["New"], "next watched mutation cannot resurrect erased link")
        let proactiveURL = root.appendingPathComponent("reset-fault-proactive.json")
        var preferences = ProactivePreferences(); preferences.dailyBriefingEnabled = false
        try await ProactiveIntelligenceStore(fileURL: proactiveURL).updatePreferences(preferences)
        let proactive = ProactiveIntelligenceStore(fileURL: proactiveURL, write: { data, url in
            try RecoverableJSONFile.write(data, to: url) { boundary in
                if boundary == .primaryReplaced { throw CocoaError(.fileWriteUnknown) }
            }
        })
        check(try await proactive.preferences().dailyBriefingEnabled == false, "faulted proactive actor first caches old preference")
        check(await rejected { try await proactive.reset() }, "proactive reset surfaces post-commit mirror failure")
        check(try await proactive.preferences().dailyBriefingEnabled, "same proactive actor reopens actual reset state after failure")
    }
    static func recoveryPrivacy(_ root: URL) async throws {
        let seed = root.appendingPathComponent("privacy-seed.json")
        let snapshot = try await preparedSnapshot(seed, title: "Project meeting", now: Date())
        check(snapshot.briefing?.items.count == 1 && snapshot.dailyContext?.entries.count == 1, "privacy fixture has real structured summary and Today entries")
        let data = try Data(contentsOf: seed)
        let original = String(decoding: data, as: UTF8.self)
        // Normal wording with restricted metadata must fail regardless of the
        // lexical classifier. Both primary and mirror use the same validator.
        let restricted = original.replacingOccurrences(of: "\"sensitivity\":\"public\"", with: "\"sensitivity\":\"restricted\"")
            .replacingOccurrences(of: "\"sensitivity\":\"personal\"", with: "\"sensitivity\":\"restricted\"")
        check(restricted != original, "privacy fixture changed sensitivity metadata")
        for recovery in [false, true] {
            let url = root.appendingPathComponent("privacy-\(recovery).json")
            try Data(restricted.utf8).write(to: recovery ? RecoverableJSONFile.recoveryURL(for: url) : url)
            check(await rejected { _ = try await ProactiveIntelligenceStore(fileURL: url).current(now: Date()) }, "restricted metadata rejected from \(recovery ? "recovery" : "primary")")
        }
    }
    static func sourceReset(_ root: URL) async throws {
        let schema = Schema([StoredInformationEvent.self, StoredInformationSource.self])
        let url = root.appendingPathComponent("information.store")
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let store = InformationStore(modelContainer: container)
        let now = Date.now
        for source in [InformationSourceID.watchedWeb, .calendar] {
            try await store.setEnabled(source, enabled: true)
            let cycle = try await store.begin(source, now: now)
            try await store.commit(.init(observations: [.init(externalID: "fixture", title: "Project meeting", modifiedAt: now)], complete: true, window: .init(start: now, duration: 3600)), cycle: cycle, now: now)
        }
        let staleCycle = try await store.begin(.watchedWeb, now: now)
        try await store.removeAllObjects(source: .watchedWeb)
        check(await rejected { try await store.commit(.init(observations: [], complete: true, window: .init(start: now, duration: 3600)), cycle: staleCycle, now: now) }, "source reset invalidates pending intake ownership")
        let reopened = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let rows = try ModelContext(reopened).fetch(FetchDescriptor<StoredInformationEvent>())
        check(rows.count == 1 && rows.first?.source == "calendar", "watched reset persists source-scoped deletion and preserves Calendar")
        let sources = try ModelContext(reopened).fetch(FetchDescriptor<StoredInformationSource>())
        let watched = sources.first { $0.id == "watchedWeb" }
        check(watched?.checkpoint == nil && watched?.lastSuccess == nil && watched?.health == "stale", "source reset cannot retain false healthy checkpoint")
    }
}
