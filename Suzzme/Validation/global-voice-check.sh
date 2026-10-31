#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
# Same-file test extensions can inspect private callback ownership without
# adding testing entry points to the controller that ships in the app.
cat Suzzme/Core/Voice/VoiceSessionController.swift Validation/GlobalVoiceChecks.swift > "$output/VoiceControllerChecks.swift"
cat > "$output/CloudVoiceStubs.swift" <<'EOF'
import Foundation
import AVFoundation
enum SuzzmeCloudVoiceError: Error { case unavailable, invalidResponse }
enum SuzzmeCloudVoice {
    static let isConfigured = false
    static func speech(_ text: String) async throws -> Data { throw SuzzmeCloudVoiceError.unavailable }
}
protocol SuzzmeStreamingTranscriptionSession: AnyObject {
    func appendAudioBuffer(_ audioBuffer: AVAudioPCMBuffer)
    func requestFinalTranscript()
    func cancel()
}
@MainActor struct AssemblyAIStreamingTranscriptionProvider {
    func startStreamingSession(keyterms: [String], onTranscriptUpdate: @escaping (String) -> Void, onFinalTranscriptReady: @escaping (String) -> Void, onError: @escaping (Error) -> Void) async throws -> any SuzzmeStreamingTranscriptionSession { throw SuzzmeCloudVoiceError.unavailable }
}
EOF
xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path "$output/ModuleCache" \
 -framework AVFoundation -framework Speech \
 Suzzme/Core/Models/SuzzmeAssistantState.swift \
 Suzzme/Core/Voice/VoiceTranscriptFinalizer.swift \
 "$output/CloudVoiceStubs.swift" \
 "$output/VoiceControllerChecks.swift" -o "$output/GlobalVoiceChecks"
"$output/GlobalVoiceChecks"
