import Foundation

enum SuzzmeCloudVoiceError: LocalizedError {
    case unavailable, invalidResponse
    var errorDescription: String? { "Cloud voice unavailable in this local check." }
}

@MainActor enum SuzzmeCloudVoice {
    static let isConfigured = false
    static func temporaryTranscriptionToken() async throws -> String { throw SuzzmeCloudVoiceError.unavailable }
    static func speech(_ text: String) async throws -> Data { throw SuzzmeCloudVoiceError.unavailable }
}
