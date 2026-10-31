import Foundation
import CryptoKit

enum LocalKnowledgeLimits {
    static let characters = 6_000
    static let fileBytes = 64_000
    static let batch = 8
    static let notes = 128
    static let checkpoints = 256
    static let folderScanLimit = 500
    static let folderDepth = 2
}

struct LocalKnowledgeInput: Sendable {
    let title: String
    let text: String
}

struct LocalKnowledgeNote: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let title: String
    let excerpts: [String]
    let analyzedAt: Date
    let fingerprint: String

    var text: String { excerpts.joined(separator: "\n\n") }
}

struct LocalKnowledgeImport: Sendable {
    var kept = 0
    var skipped = 0
    var unchanged = 0
}

struct LocalKnowledgeAnswer: Sendable {
    let text: String
    let sources: [LocalKnowledgeNote]
    let usedModel: Bool
}

enum LocalKnowledgeError: LocalizedError {
    case invalidInput, restricted, invalidSelection, storage, busy, full, unsupportedFile, unsupportedFolder
    var errorDescription: String? {
        switch self {
        case .invalidInput: "Use a title of up to 100 characters and text of up to 6,000 characters."
        case .restricted: "This includes sensitive or secret information and wasn’t added."
        case .invalidSelection: "The local model could not select reliable source excerpts. Nothing was added for this item."
        case .storage: "Your local library couldn’t be read or saved. Existing files have been kept."
        case .busy: "A local analysis is still finishing. Try again shortly."
        case .full: "Your library is full. Remove a note before adding another."
        case .unsupportedFile: "Choose up to eight small UTF-8 text or Markdown files, each under 64 KB and 6,000 characters."
        case .unsupportedFolder: "Choose a folder with up to eight small UTF-8 text or Markdown files within two folder levels. Hidden files, packages, and symbolic links are skipped."
        }
    }
}

/// User-selected documents only. No network, source enumeration, tools or action capabilities.
/// Each item commits its retained excerpts and digest together. Raw imports stay in memory.
actor LocalKnowledgeEngine {
    private struct State: Codable {
        var schemaVersion = 1
        var notes: [LocalKnowledgeNote] = []
        var processed: [String] = []
    }
    private let pipeline: SuzzmeUnderstandingPipeline
    private let fileURL: URL
    private var state: State?
    private var activeOwner: UUID?
    private var revision: UInt64 = 0

    init(pipeline: SuzzmeUnderstandingPipeline = .init(), fileURL: URL = LocalKnowledgeEngine.defaultURL) {
        self.pipeline = pipeline
        self.fileURL = fileURL
    }

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Suzzme/Knowledge/library-v1.json")
    }

    func notes() throws -> [LocalKnowledgeNote] {
        try load()
        return (state?.notes ?? []).sorted { $0.analyzedAt > $1.analyzedAt }
    }

    func cancel(owner: UUID) {
        if activeOwner == owner { activeOwner = nil; revision &+= 1 }
    }

    func analyze(_ inputs: [LocalKnowledgeInput], owner: UUID,
                 progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> LocalKnowledgeImport {
        try load()
        guard activeOwner == nil else { throw LocalKnowledgeError.busy }
        guard !inputs.isEmpty, inputs.count <= LocalKnowledgeLimits.batch else { throw LocalKnowledgeError.invalidInput }
        // Validate the whole batch before invoking a model or changing storage.
        for input in inputs { try Self.validate(input) }
        activeOwner = owner
        let epoch = revision
        defer { if activeOwner == owner { activeOwner = nil } }
        var result = LocalKnowledgeImport()
        for (index, input) in inputs.enumerated() {
            try ensure(owner, epoch)
            await progress(index, inputs.count)
            try ensure(owner, epoch)
            let fingerprint = Self.digest(input.text)
            if state?.processed.contains(fingerprint) == true || state?.notes.contains(where: { $0.fingerprint == fingerprint }) == true {
                result.unchanged += 1
                continue
            }
            // Skip private inputs before inference; never persist their text or digest.
            if Self.isPrivate(input.title + "\n" + input.text) { result.skipped += 1; continue }
            let selection = try await pipeline.selectKnowledge(from: input.text)
            try ensure(owner, epoch)
            if selection.sensitive { result.skipped += 1; continue }
            var next = state ?? State()
            if selection.keep {
                let excerpts = try Self.grounded(selection.excerpts, in: input.text)
                guard next.notes.count < LocalKnowledgeLimits.notes else { throw LocalKnowledgeError.full }
                next.notes.append(.init(id: UUID(), title: input.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    excerpts: excerpts, analyzedAt: .now, fingerprint: fingerprint))
            } else if !selection.excerpts.isEmpty {
                // Inconsistent model flags are not a completed checkpoint.
                throw LocalKnowledgeError.invalidSelection
            }
            next.processed.append(fingerprint)
            next.processed = Array(next.processed.suffix(LocalKnowledgeLimits.checkpoints))
            try persist(next)
            if selection.keep { result.kept += 1 } else { result.skipped += 1 }
        }
        return result
    }

    func remove(id: UUID) throws {
        try load()
        activeOwner = nil; revision &+= 1
        var next = state ?? State()
        let fingerprints = Set(next.notes.filter { $0.id == id }.map(\.fingerprint))
        next.notes.removeAll { $0.id == id }
        next.processed.removeAll { fingerprints.contains($0) }
        try persist(next)
    }

    func answer(_ question: String, owner: UUID) async throws -> LocalKnowledgeAnswer {
        try load()
        guard activeOwner == nil else { throw LocalKnowledgeError.busy }
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, question.count <= 1_000 else { throw LocalKnowledgeError.invalidInput }
        guard !Self.isPrivate(question) else { throw LocalKnowledgeError.restricted }
        let matches = Self.retrieve(question, from: state?.notes ?? [])
        guard !matches.isEmpty else {
            return .init(text: "I couldn’t find matching source excerpts in your library. Try a name or phrase from the note.", sources: [], usedModel: false)
        }
        activeOwner = owner
        let epoch = revision
        defer { if activeOwner == owner { activeOwner = nil } }
        // Complete source blocks only; no chopped citation or hidden truncation.
        let evidence = matches.enumerated().map {
            "[\($0.offset + 1)] Saved source: \($0.element.title)\nAnalyzed: \($0.element.analyzedAt.ISO8601Format())\n\($0.element.text)"
        }.joined(separator: "\n\n")
        guard let reply = try await pipeline.answerKnowledge(question: question, evidence: evidence) else {
            try ensure(owner, epoch)
            return .init(text: "On-device answers are unavailable. You can still read the matching source excerpts below.", sources: matches, usedModel: false)
        }
        try ensure(owner, epoch)
        let numbers = Set(reply.sourceNumbers)
        guard !numbers.isEmpty else {
            return .init(text: "I couldn’t verify that answer from the matching excerpts. You can review them below.", sources: matches, usedModel: false)
        }
        guard numbers.count <= matches.count, numbers.allSatisfy({ (1...matches.count).contains($0) }),
              !reply.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              reply.answer.count <= 2_000, !Self.isPrivate(reply.answer) else { throw LocalKnowledgeError.invalidSelection }
        return .init(text: reply.answer, sources: numbers.sorted().map { matches[$0 - 1] }, usedModel: true)
    }

    static func retrieve(_ question: String, from notes: [LocalKnowledgeNote]) -> [LocalKnowledgeNote] {
        let query = terms(question)
        guard !query.isEmpty else { return [] }
        var ranked: [(note: LocalKnowledgeNote, score: Int)] = []
        for note in notes {
            let score = query.intersection(terms(note.title + " " + note.text)).count
            if score > 0 { ranked.append((note, score)) }
        }
        ranked.sort { left, right in
            if left.score != right.score { return left.score > right.score }
            return left.note.id.uuidString < right.note.id.uuidString
        }
        // Three sources × 1,500 excerpt characters + metadata fits the model budget.
        return ranked.prefix(3).map(\.note)
    }

    static func markdown(_ notes: [LocalKnowledgeNote]) -> String {
        var lines = ["# Suzzme Local Knowledge", "", "Saved source excerpts selected on this device. Notes may be outdated; they do not authorize actions.", ""]
        for note in notes {
            lines += ["## " + note.title.replacingOccurrences(of: "\n", with: " "), "", "Analyzed: " + note.analyzedAt.ISO8601Format(), ""]
            for excerpt in note.excerpts {
                lines.append(excerpt.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n"))
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func grounded(_ excerpts: [String], in text: String) throws -> [String] {
        guard !excerpts.isEmpty, excerpts.count <= 5 else { throw LocalKnowledgeError.invalidSelection }
        var seen = Set<String>()
        for excerpt in excerpts {
            guard !excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, excerpt.count <= 300,
                  text.contains(excerpt), !isPrivate(excerpt), seen.insert(excerpt).inserted else { throw LocalKnowledgeError.invalidSelection }
        }
        return excerpts
    }

    private static func validate(_ input: LocalKnowledgeInput) throws {
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 100, !title.contains(where: \.isNewline),
              !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              input.text.count <= LocalKnowledgeLimits.characters else { throw LocalKnowledgeError.invalidInput }
    }

    private static func isPrivate(_ text: String) -> Bool { PrivacyEngine().classify(text).sensitivity >= .sensitive }
    private static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    private static func terms(_ text: String) -> Set<String> {
        let stop = Set(["the", "and", "for", "from", "this", "that", "what", "where", "when", "which", "who", "how", "does", "can", "you", "about", "with", "have", "was", "are", "please", "my", "our", "note", "notes", "library", "is", "it", "to", "of", "on", "in", "at", "an", "as", "by", "be", "do", "me", "or", "we", "us", "am", "been", "has", "had", "your", "would", "could", "should"])
        return Set(text.lowercased().components(separatedBy: .alphanumerics.inverted).filter { $0.count > 1 && !stop.contains($0) })
    }
    private func ensure(_ owner: UUID, _ epoch: UInt64) throws {
        try Task.checkCancellation()
        guard activeOwner == owner, revision == epoch else { throw CancellationError() }
    }

    private func load() throws {
        guard state == nil else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { state = State(); return }
        do {
            guard (try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_000_000 else { throw LocalKnowledgeError.storage }
            let next = try JSONDecoder().decode(State.self, from: Data(contentsOf: fileURL))
            try Self.validateState(next)
            state = next
        } catch { throw LocalKnowledgeError.storage }
    }
    private static func validateState(_ next: State) throws {
        guard next.schemaVersion == 1, next.notes.count <= LocalKnowledgeLimits.notes,
              Set(next.notes.map(\.id)).count == next.notes.count,
              Set(next.notes.map(\.fingerprint)).count == next.notes.count,
              next.processed.count <= LocalKnowledgeLimits.checkpoints,
              next.processed.allSatisfy({ $0.count == 64 && $0.allSatisfy(\.isHexDigit) }) else { throw LocalKnowledgeError.storage }
        for note in next.notes {
            try validate(.init(title: note.title, text: note.text))
            guard note.fingerprint.count == 64, note.fingerprint.allSatisfy(\.isHexDigit),
                  !isPrivate(note.title + " " + note.text), note.analyzedAt.timeIntervalSince1970.isFinite else { throw LocalKnowledgeError.storage }
            _ = try grounded(note.excerpts, in: note.text)
        }
    }
    private func persist(_ next: State) throws {
        do {
            try Self.validateState(next)
            let data = try JSONEncoder().encode(next)
            guard data.count <= 1_000_000 else { throw LocalKnowledgeError.storage }
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // One atomic file is the commit: no older recovery copy can resurrect a removed note.
            try data.write(to: fileURL, options: .atomic)
            state = next
        } catch is CancellationError { throw CancellationError() }
        catch { throw LocalKnowledgeError.storage }
    }
}
