import AVFoundation
import FirebaseAuth
import FirebaseCore
import Foundation
import os

enum SuzzmeCloudVoiceError: LocalizedError {
    case unavailable, noAccount, rejected, invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable: "Cloud voice is not configured yet. You can type to Suzzme."
        case .noAccount: "Sign in to use cloud voice."
        case .rejected: "Cloud voice could not connect. Please try again."
        case .invalidResponse: "Cloud voice returned an invalid response."
        }
    }
}

@MainActor
enum SuzzmeCloudVoice {
    private static let logger = Logger(subsystem: "rehan.Suzzme", category: "CloudVoice")
    static var isConfigured: Bool {
        guard let url = endpoint else { return false }
        return url.scheme == "https" && !url.absoluteString.contains("$(")
    }

    private static var endpoint: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SuzzmeVoiceGatewayURL") as? String else { return nil }
        return URL(string: value)
    }

    private static func authorizedRequest(path: String) async throws -> URLRequest {
        guard let base = endpoint, isConfigured else { throw SuzzmeCloudVoiceError.unavailable }
        guard FirebaseApp.app() != nil, let user = Auth.auth().currentUser else { throw SuzzmeCloudVoiceError.noAccount }
        let token = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            user.getIDToken { token, error in
                if let error { continuation.resume(throwing: error) }
                else if let token { continuation.resume(returning: token) }
                else { continuation.resume(throwing: SuzzmeCloudVoiceError.noAccount) }
            }
        }
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func temporaryTranscriptionToken() async throws -> String {
        let request = try await authorizedRequest(path: "transcribe-token")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            logger.error("Transcription gateway rejected request with HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw SuzzmeCloudVoiceError.rejected
        }
        struct Token: Decodable { let token: String }
        guard let token = try? JSONDecoder().decode(Token.self, from: data), !token.token.isEmpty else { throw SuzzmeCloudVoiceError.invalidResponse }
        return token.token
    }

    static func speech(_ text: String) async throws -> Data {
        var request = try await authorizedRequest(path: "tts")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["text": text])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            logger.error("Speech gateway rejected request with HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw SuzzmeCloudVoiceError.rejected
        }
        guard !data.isEmpty, data.count <= 12_000_000 else { throw SuzzmeCloudVoiceError.invalidResponse }
        return data
    }
}
