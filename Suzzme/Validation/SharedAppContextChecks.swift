import Foundation
import AppKit

private actor SharedModelFixture: SuzzmeIntelligenceService {
    var result: SuzzmeKnowledgeReply? = .init(answer: "The review is in Studio Cedar.", sourceNumbers: [1])
    var prompt = ""
    var evidence = ""
    var calls = 0
    var blocked = false
    var entered = false
    var releaseGate: CheckedContinuation<Void, Never>?
    var entryGate: CheckedContinuation<Void, Never>?
    func capability() async -> IntelligenceCapability { .available }
    func understand(text: String, referenceDate: Date) async throws -> [ExtractedSuzzmeItem] { fatalError("No extraction authority") }
    func summarize(text: String) async throws -> String { fatalError("No briefing intake") }
    func answerKnowledge(question: String, evidence: String) async throws -> SuzzmeKnowledgeReply? {
        calls += 1; prompt = question; self.evidence = evidence
        if blocked {
            entered = true; entryGate?.resume(); entryGate = nil
            await withCheckedContinuation { releaseGate = $0 }
        }
        return result
    }
    func configure(_ result: SuzzmeKnowledgeReply?) { self.result = result }
    func block() { blocked = true; entered = false }
    func waitForEntry() async { if !entered { await withCheckedContinuation { entryGate = $0 } } }
    func release() { blocked = false; releaseGate?.resume(); releaseGate = nil }
}

@main @MainActor struct SharedAppContextChecks {
    static var passed = 0, failed = 0
    static func check(_ condition: Bool, _ label: String) {
        print("\(condition ? "PASS" : "FAIL") \(label)")
        if condition { passed += 1 } else { failed += 1 }
    }
    static func rejects(_ label: String, _ operation: () async throws -> Void) async {
        do { try await operation(); check(false, label) } catch { check(true, label) }
    }
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmeSharedChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = SharedModelFixture()
        let responder = SharedAppResponder(pipeline: SuzzmeUnderstandingPipeline(primary: model))
        let text = "Mina: The review is in Studio Cedar on 22 October. It is not the public launch."
        check(!SharedAppSource.allCases.contains(.whatsapp), "WhatsApp absent from selectable sources")
        await rejects("WhatsApp ingestion excluded before inference") { _ = try SharedAppSnapshot(source: .whatsapp, text: text) }
        let snapshot = try SharedAppSnapshot(source: .linkedin, text: text)
        let answer = try await responder.answer(snapshot, task: .question, question: "Where is the review?")
        check(answer.source.text == text && answer.source.source == .linkedin, "answer retains exact selected source")
        check(answer.text.contains("Studio Cedar"), "read-only answer returns grounded model output")
        check(await model.evidence.contains("not live account data"), "model sees snapshot provenance, not a live account claim")
        check(await model.evidence.contains(text), "model receives full bounded excerpt")
        _ = try await responder.answer(snapshot, task: .reply, question: "Keep it friendly.")
        let draftPrompt = await model.prompt
        check(draftPrompt.contains("for review") && draftPrompt.contains("Do not invent commitments"), "draft is labelled as a proposal with no send authority")
        for phrase in ["I will review the slides.", "I’ll be there.", "We can attend.", "Confirmed. See you there."] {
            await model.configure(.init(answer: phrase, sourceNumbers: [1]))
            await rejects("unconfirmed draft commitment withheld") { _ = try await responder.answer(snapshot, task: .reply, question: "Acknowledge the venue.") }
        }
        await model.configure(.init(answer: "Thanks for sharing the Studio Cedar details.", sourceNumbers: [1]))
        _ = try await responder.answer(snapshot, task: .summary, question: "")
        check(await model.prompt.contains("negation"), "summary preserves negation and uncertainty")
        for value in ["", String(repeating: "a", count: 4_501), "bad\0text", "The password is secret.", "Routine medical information"] {
            await rejects("invalid or private source rejected before inference") { _ = try SharedAppSnapshot(source: .linkedin, text: value) }
        }
        let calls = await model.calls
        await rejects("oversized question rejected") { _ = try await responder.answer(snapshot, task: .question, question: String(repeating: "x", count: 701)) }
        await rejects("empty question rejected") { _ = try await responder.answer(snapshot, task: .question, question: " ") }
        await rejects("sensitive question rejected") { _ = try await responder.answer(snapshot, task: .question, question: "My password is secret") }
        check(await model.calls == calls, "invalid questions never invoke inference")
        for reply in [SuzzmeKnowledgeReply(answer: "Invented", sourceNumbers: []), .init(answer: "Wrong source", sourceNumbers: [2]), .init(answer: "Mixed source", sourceNumbers: [1,2]), .init(answer: " ", sourceNumbers: [1]), .init(answer: String(repeating: "a", count: 2_001), sourceNumbers: [1]), .init(answer: "The password is secret", sourceNumbers: [1])] {
            await model.configure(reply)
            await rejects("uncited, invalid or private output withheld") { _ = try await responder.answer(snapshot, task: .question, question: "Where?") }
        }
        await model.configure(nil)
        await rejects("unavailable model remains unavailable") { _ = try await responder.answer(snapshot, task: .question, question: "Where?") }
        await model.configure(.init(answer: "Studio Cedar", sourceNumbers: [1]))
        await model.block()
        let controller = SharedAppContextController(pipeline: SuzzmeUnderstandingPipeline(primary: model))
        controller.edit(text); controller.ask(source: .linkedin, task: .question, question: "Where?")
        await model.waitForEntry(); controller.cancel(); await model.release()
        for _ in 0..<20 { await Task.yield() }
        check(controller.answer == nil && !controller.isWorking, "Stop discards late inference result")
        controller.clear()
        check(controller.text.isEmpty && controller.answer == nil && controller.error == nil, "clear removes all ephemeral context")
        let invalid = root.appendingPathComponent("fake.png")
        try Data("not an image".utf8).write(to: invalid)
        await rejects("invalid image rejected") { _ = try await SharedAppScreenshot.read(invalid) }
        let large = root.appendingPathComponent("large.png")
        try Data(repeating: 0, count: SharedAppScreenshot.maximumBytes + 1).write(to: large)
        await rejects("oversized image rejected before decoding") { _ = try await SharedAppScreenshot.read(large) }
        let fixture = root.appendingPathComponent("source.png")
        let image = NSImage(size: NSSize(width: 1100, height: 260))
        image.lockFocus(); NSColor.white.setFill(); NSRect(x:0,y:0,width:1100,height:260).fill()
        ("Mina: The review is in Studio Cedar.\nThursday 22 October at 10:00." as NSString).draw(in: NSRect(x:40,y:50,width:1020,height:170), withAttributes: [.font:NSFont.systemFont(ofSize:36), .foregroundColor:NSColor.black])
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using:.png,properties:[:])!.write(to: fixture)
        let recognized = try await SharedAppScreenshot.read(fixture)
        check(recognized.contains("Studio Cedar") && recognized.contains("22 October"), "real Vision OCR reads source screenshot locally")
        let alias = root.appendingPathComponent("alias.png")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture)
        await rejects("screenshot symlink rejected") { _ = try await SharedAppScreenshot.read(alias) }
        let fresh = SharedAppContextController(pipeline: SuzzmeUnderstandingPipeline(primary: model))
        check(fresh.text.isEmpty && fresh.answer == nil, "new workspace has no retained context")
        print("\(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
