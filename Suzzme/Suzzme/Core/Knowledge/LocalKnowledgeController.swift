import Foundation
import Observation

@MainActor @Observable
final class LocalKnowledgeController {
    private let engine: LocalKnowledgeEngine
    private var task: Task<Void, Never>?
    private var owner: UUID?
    private(set) var notes: [LocalKnowledgeNote] = []
    private(set) var isLoaded = false
    private(set) var isWorking = false
    private(set) var status: String?
    private(set) var error: String?
    private(set) var answer: LocalKnowledgeAnswer?

    init(engine: LocalKnowledgeEngine) { self.engine = engine }

    func load() async {
        do { notes = try await engine.notes(); isLoaded = true }
        catch { self.error = LocalKnowledgeError.storage.localizedDescription }
    }

    func add(_ inputs: [LocalKnowledgeInput]) {
        start { [engine] id in
            let result = try await engine.analyze(inputs, owner: id) { [weak self] index, total in
                await MainActor.run {
                    guard self?.owner == id else { return }
                    self?.status = "Analyzing document \(index + 1) of \(total) on this device…"
                }
            }
            guard self.owner == id else { return }
            self.status = "\(result.kept) added · \(result.unchanged) unchanged · \(result.skipped) not kept."
        }
    }

    func importFiles(_ urls: [URL]) {
        start { [engine] id in
            let inputs = try await Self.readFiles(urls)
            try Task.checkCancellation()
            guard self.owner == id else { return }
            let result = try await engine.analyze(inputs, owner: id) { [weak self] index, total in
                await MainActor.run {
                    guard self?.owner == id else { return }
                    self?.status = "Analyzing document \(index + 1) of \(total) on this device…"
                }
            }
            guard self.owner == id else { return }
            self.status = "\(result.kept) added · \(result.unchanged) unchanged · \(result.skipped) not kept."
        }
    }

    func importFolder(_ url: URL) {
        start { [engine] id in
            self.status = "Checking the selected folder…"
            let inputs = try await Self.readFolder(url)
            try Task.checkCancellation()
            guard self.owner == id else { return }
            let result = try await engine.analyze(inputs, owner: id) { [weak self] index, total in
                await MainActor.run {
                    guard self?.owner == id else { return }
                    self?.status = "Analyzing document \(index + 1) of \(total) on this device…"
                }
            }
            guard self.owner == id else { return }
            self.status = "\(result.kept) added · \(result.unchanged) unchanged · \(result.skipped) not kept."
        }
    }

    func ask(_ question: String) {
        start { [engine] id in
            self.status = "Finding an answer in your saved excerpts…"
            let answer = try await engine.answer(question, owner: id)
            guard self.owner == id else { return }
            self.answer = answer
            self.status = nil
        }
    }

    func cancel() {
        guard let owner else { return }
        self.owner = nil
        task?.cancel(); task = nil
        isWorking = false
        status = "Stopped. Any completed notes have been kept."
        Task { await engine.cancel(owner: owner); await load() }
    }

    func remove(_ note: LocalKnowledgeNote) async {
        cancel()
        answer = nil
        do { try await engine.remove(id: note.id); await load(); status = "Note removed from this library." }
        catch { self.error = LocalKnowledgeError.storage.localizedDescription }
    }

    func dismissError() { error = nil }

    private func start(_ operation: @escaping @MainActor (UUID) async throws -> Void) {
        guard !isWorking else { return }
        let id = UUID()
        owner = id; isWorking = true; error = nil; answer = nil
        status = "Preparing on this device…"
        task = Task { [weak self] in
            guard let self else { return }
            do { try await operation(id) }
            catch is CancellationError { }
            catch {
                guard self.owner == id else { return }
                if let error = error as? LocalKnowledgeError { self.error = error.localizedDescription }
                else if let error = error as? SuzzmeIntelligenceError { self.error = error.localizedDescription }
                else { self.error = "On-device analysis couldn’t finish. Completed notes are kept; retry skips unchanged documents." }
                self.status = nil
            }
            guard self.owner == id else { return }
            self.owner = nil; self.isWorking = false; self.task = nil
            await self.load()
        }
    }

    /// A folder picker grants access only to the selected root. This is a one-time,
    /// bounded import; it never stores a folder bookmark or watches future changes.
    @concurrent nonisolated static func readFolder(_ folder: URL) async throws -> [LocalKnowledgeInput] {
        guard folder.isFileURL else { throw LocalKnowledgeError.unsupportedFolder }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let candidates = try folderCandidates(folder)
        return try await readFiles(candidates)
    }

    private nonisolated static func folderCandidates(_ folder: URL) throws -> [URL] {
        guard folder.isFileURL else { throw LocalKnowledgeError.unsupportedFolder }
        let rootValues = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw LocalKnowledgeError.unsupportedFolder
        }
        var traversalFailed = false
        guard let enumerator = FileManager.default.enumerator(at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in traversalFailed = true; return false }) else {
            throw LocalKnowledgeError.unsupportedFolder
        }
        let rootDepth = folder.standardizedFileURL.pathComponents.count
        var scanned = 0
        var candidates: [URL] = []
        for case let url as URL in enumerator {
            scanned += 1
            guard scanned <= LocalKnowledgeLimits.folderScanLimit else { throw LocalKnowledgeError.unsupportedFolder }
            let depth = url.standardizedFileURL.pathComponents.count - rootDepth
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values.isDirectory == true {
                if depth >= LocalKnowledgeLimits.folderDepth + 1 { enumerator.skipDescendants() }
                continue
            }
            guard depth <= LocalKnowledgeLimits.folderDepth + 1,
                  ["txt", "md", "markdown"].contains(url.pathExtension.lowercased()) else { continue }
            candidates.append(url)
            guard candidates.count <= LocalKnowledgeLimits.batch else { throw LocalKnowledgeError.unsupportedFolder }
        }
        guard !traversalFailed, !candidates.isEmpty else { throw LocalKnowledgeError.unsupportedFolder }
        return candidates
    }

    /// The document picker grants temporary access only to these exact files.
    @concurrent nonisolated static func readFiles(_ urls: [URL]) async throws -> [LocalKnowledgeInput] {
        guard !urls.isEmpty, urls.count <= LocalKnowledgeLimits.batch else { throw LocalKnowledgeError.unsupportedFile }
        return try urls.map { url in
            try Task.checkCancellation()
            guard url.isFileURL, ["txt", "md", "markdown"].contains(url.pathExtension.lowercased()) else { throw LocalKnowledgeError.unsupportedFile }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let bytes = values.fileSize, bytes <= LocalKnowledgeLimits.fileBytes else { throw LocalKnowledgeError.unsupportedFile }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let data = try file.read(upToCount: LocalKnowledgeLimits.fileBytes + 1) ?? Data()
            guard data.count <= LocalKnowledgeLimits.fileBytes, let text = String(data: data, encoding: .utf8),
                  !text.contains("\0"), text.count <= LocalKnowledgeLimits.characters else { throw LocalKnowledgeError.unsupportedFile }
            return .init(title: url.deletingPathExtension().lastPathComponent, text: text)
        }
    }
}
