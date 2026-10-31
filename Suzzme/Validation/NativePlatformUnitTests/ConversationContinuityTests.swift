import XCTest
import Foundation
@testable import Suzzme

/// Controlled model boundary tests; these are not real-model runtime evidence.
final class ConversationContinuityTests: XCTestCase {
    func testExplanationRetainsOnlyBoundedCurrentSafeConversation() async throws {
        let now = Date.now
        let model = RecordingQuestionService()
        let router = IntelligenceRouter(pipeline: .init(primary: model))
        var turns = (0..<8).map { index in
            SuzzmeSessionTurn(id: UUID(), role: index.isMultiple(of: 2) ? .user : .assistant,
                text: "Earlier explanation \(index) " + String(repeating: "x", count: 800),
                timestamp: now, expiresAt: now.addingTimeInterval(60))
        }
        turns.append(.init(id: UUID(), role: .user, text: "Expired subject", timestamp: now,
                           expiresAt: now.addingTimeInterval(-1)))
        let restricted = "My password is SECRETTESTVALUE"
        XCTAssertEqual(PrivacyEngine().classify(restricted).policy, .neverProcess)
        turns.append(.init(id: UUID(), role: .user, text: restricted, timestamp: now,
                           expiresAt: now.addingTimeInterval(60)))
        let response = try await router.route(text: "Explain photosynthesis", context: [], conversation: turns,
                                              existingFingerprints: [], referenceDate: now)
        let sent = await model.conversation
        XCTAssertEqual(response.route, .onDeviceIntelligence)
        XCTAssertTrue(sent.contains("Earlier explanation 4"))
        XCTAssertTrue(sent.contains("Earlier explanation 7"))
        XCTAssertFalse(sent.contains("Earlier explanation 3"))
        XCTAssertFalse(sent.contains("Expired subject"))
        XCTAssertFalse(sent.contains("SECRETTESTVALUE"))
        XCTAssertLessThanOrEqual(sent.count, 3_000)
    }

    @MainActor func testEnvironmentUsesItsExistingProviderForCapabilityAndAnswers() async throws {
        let model = RecordingQuestionService()
        let environment = AppEnvironment(understandingPipeline: .init(primary: model))
        let capability = await environment.intelligenceCapability()
        XCTAssertEqual(capability, .available)
        let owner = UUID()
        let response = try await environment.askSuzzme("Explain photosynthesis", requestID: owner)
        XCTAssertEqual(response.route, .onDeviceIntelligence)
        let requests = await model.requestCount
        XCTAssertEqual(requests, 1)
        await environment.dismissInteraction(owner)
    }

    func testAnUnwindingGenerationKeepsItsDistinctRetryError() async throws {
        let pipeline = SuzzmeUnderstandingPipeline(primary: RecordingQuestionService(isBusy: true))
        do {
            _ = try await pipeline.answerQuestion(question: "Explain photosynthesis", facts: "", conversation: "")
            XCTFail("A busy model must not become a fabricated answer")
        } catch let error as SuzzmeIntelligenceError {
            XCTAssertEqual(error, .generationInProgress)
        }
    }
}

private actor RecordingQuestionService: SuzzmeIntelligenceService {
    private(set) var conversation = ""
    private(set) var requestCount = 0
    let isBusy: Bool
    init(isBusy: Bool = false) { self.isBusy = isBusy }
    func capability() async -> IntelligenceCapability { .available }
    func understand(text: String, referenceDate: Date) async throws -> [ExtractedSuzzmeItem] { [] }
    func summarize(text: String) async throws -> String { text }
    func answerQuestion(question: String, facts: String, conversation: String, screenUnderstanding: String?) async throws -> String? {
        if isBusy { throw SuzzmeIntelligenceError.generationInProgress }
        self.conversation = conversation
        requestCount += 1
        return "Isolated boundary-test response."
    }
}
