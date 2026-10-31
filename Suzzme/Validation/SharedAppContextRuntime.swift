import Foundation

@main @MainActor struct SharedAppContextRuntime {
    static func main() async throws {
        let pipeline = SuzzmeUnderstandingPipeline()
        let responder = SharedAppResponder(pipeline: pipeline)
        let capability = await pipeline.capability()
        var evidence: [String: Any] = ["capability": capability.displayDescription, "scope": "Real production responder and Apple Foundation Models; fictional source, not a connected WhatsApp account"]
        let source = try SharedAppSnapshot(source: .whatsapp, text: "Mina: Project Larch's rehearsal is in Studio Cedar on 22 October 2026 at 10:00. It is a practice session, not the public launch. Can you review the slides beforehand?")
        evidence["source"] = source.text
        do {
            let answer = try await responder.answer(source, task: .question, question: "Where is the Larch rehearsal?")
            evidence["answer"] = answer.text
            let draft = try await responder.answer(source, task: .reply, question: "Acknowledge the venue without promising availability.")
            evidence["draft"] = draft.text
            let summary = try await responder.answer(source, task: .summary, question: "")
            evidence["summary"] = summary.text
            evidence["status"] = answer.text.contains("Studio Cedar") ? "PASS" : "FAIL"
        } catch {
            evidence["status"] = capability == .available ? "FAIL" : "BLOCKED"
            evidence["error"] = error.localizedDescription
        }
        let data = try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1])); print(String(decoding: data, as: UTF8.self))
    }
}
