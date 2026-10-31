import Testing
import Foundation
@testable import Suzzme

@Suite @MainActor struct AssistantPresentationOwnershipTests {
    @Test func brainLabCompletionReturnsItsOwnPresentationToIdle() async throws {
        let model = HeldPresentationExtraction()
        let environment = makeEnvironment(model: model)
        let extraction = Task { try await environment.understand(text: "Disposable extraction fixture") }
        try await waitForExtraction(model)
        #expect(environment.assistant.state == .understanding)
        await model.release()
        _ = try await extraction.value
        #expect(environment.assistant.state == .idle)
        #expect(environment.lastUnderstandingResult != nil)
    }

    @Test func brainLabCompletionCannotResetNewerPresentationOnSameRequestAndSession() async throws {
        let model = HeldPresentationExtraction()
        let environment = makeEnvironment(model: model)
        let extraction = Task { try await environment.understand(text: "Disposable extraction fixture") }
        try await waitForExtraction(model)
        // A confirmation reply or other activity may retain request/session
        // identity while acquiring a newer presentation revision.
        environment.assistant.transition(to: .listening)
        await model.release()
        do {
            _ = try await extraction.value
            Issue.record("Superseded extraction must not publish its result")
        } catch is CancellationError { }
        #expect(environment.assistant.state == .listening)
        #expect(environment.lastUnderstandingResult == nil)
        await environment.cancelVoiceSession()
    }

    @Test func brainLabCompletionCannotResetReplacementVoiceSession() async throws {
        let model = HeldPresentationExtraction()
        let environment = makeEnvironment(model: model)
        let extraction = Task { try await environment.understand(text: "Disposable extraction fixture") }
        try await waitForExtraction(model)
        _ = environment.voice.beginSession()
        environment.assistant.transition(to: .understanding)
        await model.release()
        do {
            _ = try await extraction.value
            Issue.record("A replaced voice session must retire the old extraction presentation")
        } catch is CancellationError { }
        #expect(environment.assistant.state == .understanding)
        #expect(environment.lastUnderstandingResult == nil)
        await environment.cancelVoiceSession()
    }

    @Test func brainLabCannotClaimAnExistingListeningPresentation() async throws {
        let model = HeldPresentationExtraction()
        let environment = makeEnvironment(model: model)
        environment.assistant.transition(to: .listening)
        let revision = environment.assistant.revision
        let extraction = Task { try await environment.understand(text: "Disposable extraction fixture") }
        try await waitForExtraction(model)
        #expect(environment.assistant.state == .listening)
        await model.release()
        _ = try await extraction.value
        #expect(environment.assistant.state == .listening)
        #expect(environment.assistant.revision == revision)
        await environment.cancelVoiceSession()
    }

    private func makeEnvironment(model: HeldPresentationExtraction) -> AppEnvironment {
        AppEnvironment(understandingPipeline: .init(primary: model),
            watchedLinkURL: FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmePresentation-\(UUID()).json"))
    }

    private func waitForExtraction(_ model: HeldPresentationExtraction) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await model.started), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        let started = await model.started
        try #require(started)
    }
}

private actor HeldPresentationExtraction: SuzzmeIntelligenceService {
    private var continuation: CheckedContinuation<[ExtractedSuzzmeItem], Never>?
    private(set) var started = false
    func capability() async -> IntelligenceCapability { .available }
    func summarize(text: String) async throws -> String { text }
    func understand(text: String, referenceDate: Date) async throws -> [ExtractedSuzzmeItem] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started = true
        }
    }
    func release() {
        continuation?.resume(returning: [])
        continuation = nil
    }
}
