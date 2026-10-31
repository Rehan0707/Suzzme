import Foundation
import Observation

@MainActor @Observable
final class SharedAppContextController {
    private let responder: SharedAppResponder
    private var work: Task<Void, Never>?
    private var owner: UUID?
    private(set) var text = ""
    private(set) var fromScreenshot = false
    private(set) var answer: SharedAppAnswer?
    private(set) var isWorking = false
    private(set) var status: String?
    private(set) var error: String?

    init(pipeline: SuzzmeUnderstandingPipeline) { responder = .init(pipeline: pipeline) }

    func edit(_ text: String) {
        cancel(); self.text = text; answer = nil; error = nil
    }
    func invalidateAnswer() { cancel(); answer = nil; error = nil }

    func readScreenshot(_ url: URL) {
        start(status: "Reading screenshot on this device…") {
            let text = try await SharedAppScreenshot.read(url)
            try Task.checkCancellation()
            self.text = text; self.fromScreenshot = true
            self.status = "Review the recognized text before asking. Screenshot text can contain mistakes."
        }
    }
    func ask(source: SharedAppSource, task: SharedAppTask, question: String) {
        start(status: "Considering your shared excerpt on this device…") {
            let snapshot = try SharedAppSnapshot(source: source, text: self.text, fromScreenshot: self.fromScreenshot)
            let answer = try await self.responder.answer(snapshot, task: task, question: question)
            try Task.checkCancellation()
            self.answer = answer; self.status = nil
        }
    }
    func showImportError() { error = SharedAppError.image.localizedDescription }
    func cancel() {
        owner = nil; work?.cancel(); work = nil; isWorking = false; status = nil
    }
    func clear() { cancel(); text = ""; fromScreenshot = false; answer = nil; error = nil }

    private func start(status: String, operation: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        let id = UUID(); owner = id; isWorking = true; answer = nil; error = nil; self.status = status
        work = Task { [weak self] in
            guard let self else { return }
            do { try await operation() }
            catch is CancellationError { }
            catch {
                guard self.owner == id else { return }
                self.status = nil
                self.error = (error as? SharedAppError)?.localizedDescription
                    ?? (error as? SuzzmeIntelligenceError)?.localizedDescription
                    ?? "On-device analysis couldn’t finish. Try again with a smaller excerpt."
            }
            guard self.owner == id else { return }
            self.owner = nil; self.isWorking = false; self.work = nil
        }
    }
}
