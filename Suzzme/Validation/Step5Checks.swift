import Foundation

@main
struct Step5Checks {
    @MainActor static func main() async throws {
        var finalizer = VoiceTranscriptFinalizer()
        precondition(finalizer.acceptFinal("What is my next meeting?") == "What is my next meeting?")
        precondition(finalizer.acceptFinal("duplicate callback") == nil)
        finalizer.reset()
        precondition(finalizer.acceptFinal("   ") == nil)
        let assistant = AssistantStateController()
        assistant.transition(to: .listening)
        precondition(assistant.state == .listening)
        assistant.transition(to: .transcribing)
        assistant.transition(to: .understanding)
        assistant.transition(to: .reasoning)
        assistant.transition(to: .speaking)
        precondition(assistant.state == .speaking)
        assistant.reset()
        precondition(assistant.state == .idle)
        print("PASS: voice final transcript gating and unified voice state lifecycle")
    }
}
