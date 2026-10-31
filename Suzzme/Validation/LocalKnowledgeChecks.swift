import Foundation

private actor KnowledgeModelFixture: SuzzmeIntelligenceService {
    var selection = SuzzmeKnowledgeSelection(keep: true, sensitive: false, excerpts: ["Launch rehearsal is in Studio Cedar on 22 October."])
    var reply: SuzzmeKnowledgeReply? = .init(answer: "The note places launch rehearsal in Studio Cedar.", sourceNumbers: [1])
    var calls = 0
    var answerCalls = 0
    private var blocked = false
    private var entered = false
    private var waiting: CheckedContinuation<Void, Never>?
    private var released: CheckedContinuation<Void, Never>?
    func capability() async -> IntelligenceCapability { .available }
    func understand(text: String, referenceDate: Date) async throws -> [ExtractedSuzzmeItem] { fatalError("Knowledge must not invoke extraction") }
    func summarize(text: String) async throws -> String { fatalError("Knowledge must not invoke briefing") }
    func selectKnowledge(from text: String) async throws -> SuzzmeKnowledgeSelection { calls += 1; await gate(); return selection }
    func answerKnowledge(question: String, evidence: String) async throws -> SuzzmeKnowledgeReply? { answerCalls += 1; await gate(); return reply }
    func configure(_ value: SuzzmeKnowledgeSelection) { selection = value }
    func configureReply(_ value: SuzzmeKnowledgeReply?) { reply = value }
    func block() { blocked = true; entered = false }
    func waitForCall() async { if !entered { await withCheckedContinuation { waiting = $0 } } }
    func release() { blocked = false; released?.resume(); released = nil }
    private func gate() async {
        if blocked {
            entered = true; waiting?.resume(); waiting = nil
            await withCheckedContinuation { released = $0 }
        }
    }
}

@main @MainActor struct LocalKnowledgeChecks {
    static var passed = 0
    static var failed = 0
    static func expect(_ condition: Bool, _ label: String) {
        print("\(condition ? "PASS" : "FAIL") \(label)")
        if condition { passed += 1 } else { failed += 1 }
    }
    static func main() async throws {
        print("DETERMINISTIC LOCAL KNOWLEDGE FIXTURES — NOT REAL MODEL ACCEPTANCE")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmeKnowledgeChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = KnowledgeModelFixture()
        let pipeline = SuzzmeUnderstandingPipeline(primary: model)
        let url = root.appendingPathComponent("library.json")
        let engine = LocalKnowledgeEngine(pipeline: pipeline, fileURL: url)
        let text = "Launch rehearsal is in Studio Cedar on 22 October. Bring the revised slides."
        let input = LocalKnowledgeInput(title: "Launch Plan", text: text)
        expect(try await engine.notes().isEmpty, "new library is genuinely empty")
        let result = try await engine.analyze([input], owner: UUID())
        expect(result.kept == 1 && result.skipped == 0, "keeps a grounded useful selection")
        let notes = try await engine.notes()
        expect(notes.count == 1 && notes[0].excerpts == ["Launch rehearsal is in Studio Cedar on 22 October."], "stores exact excerpts, not the entire document")
        let localSource = LocalKnowledgeInformationSource(engine: engine)
        let sameDay = try await localSource.fetch(now: notes[0].analyzedAt.addingTimeInterval(5), checkpoint: nil)
        expect(sameDay.observations.count == 1 && sameDay.observations[0].title.contains(notes[0].excerpts[0]), "only an exact user-approved excerpt is eligible for today's Daily Summary")
        let nextDay = Calendar.current.startOfDay(for: notes[0].analyzedAt).addingTimeInterval(86_400 + 5)
        expect(try await localSource.fetch(now: nextDay, checkpoint: nil).observations.isEmpty, "older library entries do not replay into a later Daily Summary")
        let raw = try String(contentsOf: url, encoding: .utf8)
        expect(!raw.contains("Bring the revised slides"), "unselected raw text is not persisted")
        let reopened = LocalKnowledgeEngine(pipeline: pipeline, fileURL: url)
        expect(try await reopened.notes() == notes, "notes survive reopening")
        let duplicate = try await engine.analyze([.init(title: "Renamed file", text: text)], owner: UUID())
        expect(duplicate.unchanged == 1 && duplicate.kept == 0, "content digest skips renamed identical documents")
        expect(await model.calls == 1, "unchanged documents do not invoke inference again")
        let beforePrivacy = await model.calls
        let privateResult = try await engine.analyze([.init(title: "Private", text: "The password is secret."), .init(title: "Medical record", text: "Routine medical information")], owner: UUID())
        let afterPrivacy = await model.calls
        expect(privateResult.skipped == 2 && afterPrivacy == beforePrivacy, "private inputs skipped before model invocation")
        expect(try String(contentsOf: url, encoding: .utf8) == raw, "private inputs leave no new text or checkpoints")
        let answer = try await engine.answer("Where is launch rehearsal?", owner: UUID())
        expect(answer.usedModel && answer.sources == notes && answer.text.contains("Studio Cedar"), "bounded read-only answer cites a retrieved note")
        let beforeNoHit = await model.answerCalls
        let noHit = try await engine.answer("Tell me about penguins", owner: UUID())
        expect(!noHit.usedModel && noHit.sources.isEmpty, "no-match answer is honest local state")
        expect(await model.answerCalls == beforeNoHit, "no matching evidence means no inference")
        await model.configureReply(.init(answer: "Uncited invention", sourceNumbers: []))
        let uncited = try await engine.answer("launch", owner: UUID())
        expect(!uncited.usedModel && !uncited.text.contains("invention"), "uncited model answer is discarded")
        await model.configureReply(.init(answer: "Bad citation", sourceNumbers: [99]))
        do { _ = try await engine.answer("launch", owner: UUID()); expect(false, "invalid citation rejected") }
        catch { expect(true, "invalid citation rejected") }
        await model.configureReply(.init(answer: "The note places rehearsal in Studio Cedar.", sourceNumbers: [1]))
        await model.configure(.init(keep: true, sensitive: false, excerpts: ["Launch rehearsal is in Paris."]))
        do { _ = try await engine.analyze([.init(title: "Other", text: "A revised launch rehearsal is in Studio Cedar.")], owner: UUID()); expect(false, "hallucinated source excerpt rejected") }
        catch { expect(true, "hallucinated source excerpt rejected") }
        expect(try await engine.notes().count == 1, "bad selection cannot mutate notes")
        await model.configure(.init(keep: false, sensitive: false, excerpts: ["inconsistent"]))
        do { _ = try await engine.analyze([.init(title: "Flags", text: "inconsistent")], owner: UUID()); expect(false, "inconsistent flags rejected") }
        catch { expect(true, "inconsistent flags rejected") }
        await model.configure(.init(keep: false, sensitive: false, excerpts: []))
        let junk = try await engine.analyze([.init(title: "Noise", text: "Generic advertising noise.")], owner: UUID())
        expect(junk.skipped == 1, "valid low-value verdict is not saved as knowledge")
        let beforeJunkRetry = await model.calls
        _ = try await engine.analyze([.init(title: "Noise", text: "Generic advertising noise.")], owner: UUID())
        expect(await model.calls == beforeJunkRetry, "completed junk verdict has a change checkpoint")
        await model.configure(.init(keep: true, sensitive: true, excerpts: ["never save this"]))
        let sensitive = try await engine.analyze([.init(title: "Filtered", text: "A private contextual fact.")], owner: UUID())
        let afterSensitive = try String(contentsOf: url, encoding: .utf8)
        expect(sensitive.skipped == 1 && !afterSensitive.contains("never save this"), "sensitive model verdict cannot retain output")
        do { _ = try await engine.analyze([.init(title: "Too long", text: String(repeating: "a", count: 6_001))], owner: UUID()); expect(false, "oversized input refused, not truncated") }
        catch { expect(true, "oversized input refused, not truncated") }
        do { _ = try await engine.analyze(Array(repeating: input, count: 9), owner: UUID()); expect(false, "batch bounded") }
        catch { expect(true, "batch bounded") }
        do { _ = try LocalKnowledgeEngine.grounded(["Launch", "Launch"], in: text); expect(false, "duplicate output excerpts rejected") }
        catch { expect(true, "duplicate output excerpts rejected") }
        let exported = LocalKnowledgeEngine.markdown(notes)
        expect(exported.contains("> Launch rehearsal") && exported.contains("Launch Plan") && !exported.contains("fingerprint"), "readable Markdown export with source title and date")
        expect(LocalKnowledgeEngine.retrieve("unrelated penguins", from: notes).isEmpty, "retrieval never pads irrelevant results")
        expect(LocalKnowledgeEngine.retrieve("What is a penguin?", from: notes).isEmpty, "common question words alone do not retrieve unrelated notes")
        expect(LocalKnowledgeEngine.retrieve("where is rehearsal", from: notes).count == 1, "bounded lexical retrieval finds evidence")
        let waitingEngine = LocalKnowledgeEngine(pipeline: pipeline, fileURL: root.appendingPathComponent("cancel.json"))
        await model.configure(.init(keep: true, sensitive: false, excerpts: ["Launch rehearsal is in Studio Cedar on 22 October."]))
        await model.block()
        let owner = UUID()
        let lateImport = Task { try await waitingEngine.analyze([input], owner: owner) }
        await model.waitForCall()
        await waitingEngine.cancel(owner: UUID())
        do { _ = try await waitingEngine.analyze([input], owner: UUID()); expect(false, "wrong-owner cancel cannot release an active operation") }
        catch { expect(true, "wrong-owner cancel cannot release an active operation") }
        await waitingEngine.cancel(owner: owner)
        await model.release()
        do { _ = try await lateImport.value; expect(false, "late analysis cannot commit after cancellation") }
        catch is CancellationError { expect(true, "late analysis cannot commit after cancellation") }
        expect(try await waitingEngine.notes().isEmpty && !FileManager.default.fileExists(atPath: root.appendingPathComponent("cancel.json").path), "cancelled import creates no stored note")
        await model.block()
        let answerTask = Task { try await engine.answer("launch rehearsal", owner: UUID()) }
        await model.waitForCall()
        try await engine.remove(id: notes[0].id)
        await model.release()
        do { _ = try await answerTask.value; expect(false, "deletion invalidates an in-flight answer") }
        catch is CancellationError { expect(true, "deletion invalidates an in-flight answer") }
        expect(try await LocalKnowledgeEngine(pipeline: pipeline, fileURL: url).notes().isEmpty, "deleted notes stay deleted after restart")
        let readded = try await engine.analyze([input], owner: UUID())
        expect(readded.kept == 1, "removal retires the note checkpoint so explicit reimport works")
        let partial = LocalKnowledgeEngine(pipeline: pipeline, fileURL: root.appendingPathComponent("partial.json"))
        do {
            _ = try await partial.analyze([input, .init(title: "Unmatched", text: "Different document without the fixture excerpt.")], owner: UUID())
            expect(false, "partially invalid batch reports failure")
        } catch { expect(true, "partially invalid batch reports failure") }
        expect(try await partial.notes().count == 1, "completed first item remains committed when a later item fails")
        let partialRetry = try await partial.analyze([input], owner: UUID())
        expect(partialRetry.unchanged == 1, "batch retry resumes without reprocessing a completed item")
        let parentFile = root.appendingPathComponent("not-a-directory")
        try Data("original".utf8).write(to: parentFile)
        let unwritable = LocalKnowledgeEngine(pipeline: pipeline, fileURL: parentFile.appendingPathComponent("library.json"))
        do { _ = try await unwritable.analyze([input], owner: UUID()); expect(false, "storage failure is reported") }
        catch { expect(true, "storage failure is reported") }
        expect(try await unwritable.notes().isEmpty, "failed atomic write cannot publish an in-memory note")
        let corrupt = root.appendingPathComponent("corrupt.json")
        try Data("{bad json".utf8).write(to: corrupt)
        do { _ = try await LocalKnowledgeEngine(pipeline: pipeline, fileURL: corrupt).notes(); expect(false, "corrupt store fails closed") }
        catch { expect(true, "corrupt store fails closed") }
        expect(try String(contentsOf: corrupt, encoding: .utf8) == "{bad json", "corrupt owner file is preserved")
        let future = root.appendingPathComponent("future.json")
        try Data("{\"schemaVersion\":2,\"notes\":[],\"processed\":[]}".utf8).write(to: future)
        do { _ = try await LocalKnowledgeEngine(pipeline: pipeline, fileURL: future).notes(); expect(false, "future schema refused") }
        catch { expect(true, "future schema refused") }
        let file = root.appendingPathComponent("Chosen.md")
        try text.write(to: file, atomically: true, encoding: .utf8)
        let imported = try await LocalKnowledgeController.readFiles([file])
        expect(imported.count == 1 && imported[0].title == "Chosen" && imported[0].text == text, "selected UTF-8 Markdown read with provenance")
        let folder = root.appendingPathComponent("ChosenFolder", isDirectory: true)
        let nested = folder.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try text.write(to: folder.appendingPathComponent("Top.txt"), atomically: true, encoding: .utf8)
        try "Nested source".write(to: nested.appendingPathComponent("Nested.md"), atomically: true, encoding: .utf8)
        try Data([0xff, 0xfe]).write(to: folder.appendingPathComponent("ignored.bin"))
        let folderLink = folder.appendingPathComponent("Alias.md")
        try FileManager.default.createSymbolicLink(at: folderLink, withDestinationURL: file)
        let folderInputs = try await LocalKnowledgeController.readFolder(folder)
        expect(Set(folderInputs.map(\.title)) == ["Top", "Nested"] && folderInputs.count == 2, "one-time folder import includes only bounded text/Markdown regular files: \(folderInputs.map(\.title))")
        let tooMany = root.appendingPathComponent("TooMany", isDirectory: true)
        try FileManager.default.createDirectory(at: tooMany, withIntermediateDirectories: true)
        for index in 0...LocalKnowledgeLimits.batch {
            try "small note \(index)".write(to: tooMany.appendingPathComponent("\(index).txt"), atomically: true, encoding: .utf8)
        }
        do { _ = try await LocalKnowledgeController.readFolder(tooMany); expect(false, "folder imports refuse more than the explicit batch bound") }
        catch LocalKnowledgeError.unsupportedFolder { expect(true, "folder imports refuse more than the explicit batch bound") }
        catch { expect(false, "folder import reports its safe limit") }
        let symlink = root.appendingPathComponent("Alias.md")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: file)
        do { _ = try await LocalKnowledgeController.readFiles([symlink]); expect(false, "symlink source rejected") }
        catch { expect(true, "symlink source rejected") }
        let binary = root.appendingPathComponent("Binary.txt")
        try Data([0xff, 0xfe]).write(to: binary)
        do { _ = try await LocalKnowledgeController.readFiles([binary]); expect(false, "non-UTF8 rejected") }
        catch { expect(true, "non-UTF8 rejected") }
        let unavailable = LocalKnowledgeEngine(pipeline: .init(primary: BasicIntelligenceService()), fileURL: root.appendingPathComponent("unavailable.json"))
        do { _ = try await unavailable.analyze([input], owner: UUID()); expect(false, "unavailable model never fabricates knowledge") }
        catch { expect(true, "unavailable model never fabricates knowledge") }
        print("Local Knowledge: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
