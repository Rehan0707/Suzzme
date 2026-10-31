import Foundation
import Testing
import SuzzmeSpeechKit
@testable import Suzzme

@Suite struct LocalVoiceAssetTests {
    @Test func alteredModelFileIsRejected() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("asset")
        let asset = LocalVoiceAssetStore.Asset(path: "v2.1/english/test", bytes: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try Data("abc".utf8).write(to: url)
        #expect(try LocalVoiceAssetStore.validFile(url, asset: asset))
        try Data("abd".utf8).write(to: url)
        #expect(try !LocalVoiceAssetStore.validFile(url, asset: asset))
        try Data("ab".utf8).write(to: url)
        #expect(try !LocalVoiceAssetStore.validFile(url, asset: asset))
    }

    @Test func missingAssetsFailLocallyWithoutCreatingCacheOrDownloading() async {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        await #expect(throws: (any Error).self) {
            _ = try await PocketTtsResourceDownloader.ensureModels(language: .english, directory: folder, precision: .int8)
        }
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
}
