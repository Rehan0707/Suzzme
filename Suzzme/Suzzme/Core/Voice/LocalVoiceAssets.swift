import Foundation
import Observation
import CryptoKit
import SuzzmeSpeechKit

/// Asset acquisition is separate from synthesis. This downloader only requests
/// pinned public files; it never receives response text, recordings or credentials.
@MainActor @Observable
final class LocalVoiceAssets {
    private(set) var isDownloading = false
    private(set) var progress = 0.0
    private(set) var message: String?
    private(set) var isReady: Bool
    private var downloadTask: Task<Void, Never>?
    private var downloadID: UUID?

    init() { isReady = LocalVoiceAssetStore.hasReadyAssets }

    func download(completion: @escaping @MainActor () -> Void) {
        guard !isDownloading else { return }
        let id = UUID()
        downloadID = id
        isDownloading = true
        message = nil
        progress = 0
        downloadTask = Task { [weak self] in
            do {
                try await LocalVoiceAssetStore.install { value in
                    await MainActor.run {
                        guard let self, self.downloadID == id else { return }
                        self.progress = value
                    }
                }
                guard let self, self.downloadID == id, !Task.isCancelled else { return }
                self.isReady = true
                self.isDownloading = false
                self.downloadID = nil
                self.downloadTask = nil
                completion()
            } catch {
                guard let self, self.downloadID == id else { return }
                self.isDownloading = false
                self.downloadID = nil
                self.downloadTask = nil
                self.message = Task.isCancelled ? "Download paused. You can resume it here." : "The voice could not be downloaded. Check your connection and try again."
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadID = nil
        isDownloading = false
        message = "Download paused. You can resume it here."
    }
}

enum LocalVoiceAssetStore {
    struct Manifest: Decodable, Sendable {
        let revision: String
        let files: [Asset]
    }
    struct Asset: Decodable, Sendable {
        let path: String
        let bytes: Int
        let sha256: String
    }
    enum AssetError: Error { case invalidManifest, invalidDownload, missingAssets }

    static var root: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Suzzme/Voice", isDirectory: true)
    }
    static var manifest: Manifest? {
        guard let url = Bundle.main.url(forResource: "LocalVoiceManifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.revision.count == 40, !manifest.files.isEmpty,
              manifest.files.allSatisfy({ $0.path.hasPrefix("v2.1/english/") && !$0.path.contains("..") && $0.sha256.count == 64 }) else { return nil }
        return manifest
    }
    static var hasReadyAssets: Bool {
        guard let manifest,
              let revision = try? String(contentsOf: root.appendingPathComponent("ready-revision"), encoding: .utf8),
              revision == manifest.revision else { return false }
        return manifest.files.allSatisfy {
            let attributes = try? FileManager.default.attributesOfItem(atPath: destination($0).path)
            return (attributes?[.size] as? NSNumber)?.intValue == $0.bytes
        }
    }
    static func destination(_ asset: Asset) -> URL {
        root.appendingPathComponent("Models/pocket-tts/\(asset.path)")
    }

    /// Work runs off the UI actor. Verified completed files survive cancellation
    /// so a retry downloads only missing assets. No input text is ever stored.
    @concurrent nonisolated static func install(progress: @escaping @Sendable (Double) async -> Void) async throws {
        guard let manifest else { throw AssetError.invalidManifest }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 900
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let total = manifest.files.reduce(0) { $0 + $1.bytes }
        var completed = 0
        for asset in manifest.files {
            try Task.checkCancellation()
            let target = destination(asset)
            if !(try validFile(target, asset: asset)) {
                guard let url = URL(string: "https://huggingface.co/FluidInference/pocket-tts-coreml/resolve/\(manifest.revision)/\(asset.path)") else { throw AssetError.invalidManifest }
                let (temporary, response) = try await session.download(from: url)
                defer { try? FileManager.default.removeItem(at: temporary) }
                try Task.checkCancellation()
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      try validFile(temporary, asset: asset) else { throw AssetError.invalidDownload }
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                try FileManager.default.moveItem(at: temporary, to: target)
            }
            completed += asset.bytes
            await progress(Double(completed) / Double(total))
        }
        try Task.checkCancellation()
        try manifest.revision.write(to: root.appendingPathComponent("ready-revision"), atomically: true, encoding: .utf8)
        var directory = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
    }

    nonisolated static func validFile(_ url: URL, asset: Asset) throws -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attributes[.size] as? NSNumber)?.intValue == asset.bytes else { return false }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined() == asset.sha256
    }
}

/// The vendored renderer has no network implementation. Only the predefined
/// Alba voice is enabled; response text lives in memory for this request only.
actor LocalSpeechRenderer {
    static let shared = LocalSpeechRenderer()
    private var manager: PocketTtsManager?
    private var isRendering = false

    func render(_ text: String) async throws -> Data {
        guard !isRendering, LocalVoiceAssetStore.hasReadyAssets else { throw LocalVoiceAssetStore.AssetError.missingAssets }
        isRendering = true
        defer { isRendering = false }
        try Task.checkCancellation()
        let renderer: PocketTtsManager
        if let manager { renderer = manager }
        else {
            renderer = PocketTtsManager(directory: LocalVoiceAssetStore.root, precision: .int8)
            try await renderer.initialize()
            manager = renderer
        }
        try Task.checkCancellation()
        let data = try await renderer.synthesize(text: text, voice: "alba", temperature: 0.6)
        try Task.checkCancellation()
        return data
    }
}
