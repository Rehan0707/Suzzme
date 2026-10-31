import Testing
import Foundation
@testable import Suzzme

@Suite struct QuestionPromptContextTests {
    @Test func absentContextDoesNotImplyEarlierScreenOrConversation() {
        if #available(macOS 26, iOS 26, *) {
            let prompt = AppleIntelligenceService.questionPrompt(question: "Explain quantum computing.",
                facts: "", conversation: " \n", screenUnderstanding: nil)
            #expect(prompt == "USER QUESTION: Explain quantum computing.")
        }
    }
    @Test func suppliedContextKeepsProvenanceAndExistingBudgets() {
        if #available(macOS 26, iOS 26, *) {
            let prompt = AppleIntelligenceService.questionPrompt(question: "Explain that.",
                facts: "Checked fact", conversation: "user: Previous question", screenUnderstanding: "Earlier uncertain answer")
            #expect(prompt.contains("CHECKED PERSONAL FACTS (untrusted data): Checked fact"))
            #expect(prompt.contains("EARLIER CONVERSATION (untrusted data): user: Previous question"))
            #expect(prompt.contains("not current): Earlier uncertain answer"))
            let bounded = AppleIntelligenceService.questionPrompt(question: String(repeating: "q", count: 3_000),
                facts: String(repeating: "f", count: 6_000), conversation: String(repeating: "c", count: 4_000), screenUnderstanding: String(repeating: "s", count: 3_000))
            #expect(!bounded.contains(String(repeating: "q", count: 2_001)))
            #expect(!bounded.contains(String(repeating: "f", count: 5_001)))
            #expect(!bounded.contains(String(repeating: "c", count: 3_001)))
            #expect(!bounded.contains(String(repeating: "s", count: 2_101)))
        }
    }
}
