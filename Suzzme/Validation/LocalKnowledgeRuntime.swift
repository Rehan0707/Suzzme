import Foundation

@main @MainActor struct LocalKnowledgeRuntime {
    static func main() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmeKnowledgeRuntime-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pipeline = SuzzmeUnderstandingPipeline()
        let capability = await pipeline.capability()
        guard capability == .available else {
            try JSONSerialization.data(withJSONObject: ["status":"BLOCKED", "reason":capability.displayDescription], options: [.prettyPrinted, .sortedKeys]).write(to: output)
            return
        }
        let engine = LocalKnowledgeEngine(pipeline: pipeline, fileURL: root.appendingPathComponent("library.json"))
        let started = Date()
        let text = "Project Larch's launch rehearsal is scheduled for 22 October 2026 at 10:00 in Studio Cedar. Mina owns the slide review. The rehearsal is a practice session, not the public launch."
        let input = LocalKnowledgeInput(title: "Larch launch note", text: text)
        var evidence: [String: Any] = ["scope":"Real Foundation Models with final production pipeline and LocalKnowledgeEngine in disposable CLI host; not app UI acceptance", "input":text, "capability":capability.displayDescription, "networkClientAdded":false]
        do {
            let result = try await engine.analyze([input], owner: UUID())
            let notes = try await engine.notes()
            evidence["kept"] = result.kept
            evidence["sourceExcerpts"] = notes.map(\.excerpts)
            let answer = try await engine.answer("Where is the Larch launch rehearsal?", owner: UUID())
            evidence["answer"] = answer.text
            evidence["usedOnDeviceModel"] = answer.usedModel
            evidence["answerSources"] = answer.sources.map(\.title)
            let duplicate = try await engine.analyze([input], owner: UUID())
            evidence["unchangedOnReimport"] = duplicate.unchanged
            let missing = try await engine.answer("What penguin species lives on Europa?", owner: UUID())
            evidence["noMatchingEvidenceUsesModel"] = missing.usedModel
            evidence["noMatchingEvidenceAnswer"] = missing.text
            evidence["markdown"] = LocalKnowledgeEngine.markdown(notes)
            evidence["status"] = result.kept == 1 && answer.usedModel && answer.text.localizedCaseInsensitiveContains("Studio Cedar") && !answer.sources.isEmpty && duplicate.unchanged == 1 && !missing.usedModel ? "PASS" : "FAIL"
        } catch {
            evidence["status"] = "FAIL"
            evidence["error"] = error.localizedDescription
        }
        evidence["elapsedSeconds"] = Date().timeIntervalSince(started)
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        print(String(data: try Data(contentsOf: output), encoding: .utf8) ?? "")
    }
}
