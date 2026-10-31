import Foundation

/// Suzzme modification: this resolver only reads local assets. It contains no
/// networking code, token lookup, automatic downloads, or cache deletion.
public enum PocketTtsResourceDownloader {
    public static func ensureModels(language: PocketTtsLanguage, directory: URL?,
        precision: PocketTtsPrecision) async throws -> URL {
        guard let directory else { throw PocketTTSError.modelNotFound("An explicit local model directory is required") }
        let root = directory.appendingPathComponent("Models/pocket-tts/\(language.repoSubdirectory)")
        for name in ModelNames.PocketTTS.requiredModels(precision: precision) {
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) else {
                throw PocketTTSError.modelNotFound("Local voice assets are incomplete")
            }
        }
        return root
    }
    public static func ensureVoice(_ voice: String, language: PocketTtsLanguage,
        languageRoot: URL) async throws -> PocketTtsVoiceData {
        guard voice == "alba" else { throw PocketTTSError.processingFailed("Unsupported local voice") }
        return try PocketTtsConstantsLoader.loadVoice(voice, from: languageRoot)
    }
    public static func ensureMimiEncoder(directory: URL?) async throws -> URL {
        throw PocketTTSError.processingFailed("Voice cloning is not enabled in Suzzme")
    }
}
