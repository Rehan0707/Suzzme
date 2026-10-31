#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
cat Suzzme/Core/Voice/VoiceSessionController.swift Validation/VoiceQualityChecks.swift > "$output/VoiceQuality.swift"
xcrun swiftc -disable-sandbox -swift-version 6 -parse-as-library \
 -enable-upcoming-feature NonisolatedNonsendingByDefault -module-cache-path "$output/cache" \
 -framework AVFoundation -framework Speech -framework NaturalLanguage \
 Suzzme/Core/Models/SuzzmeAssistantState.swift Suzzme/Core/Voice/VoiceTranscriptFinalizer.swift \
 Suzzme/Core/Voice/SuzzmeAssemblyAITranscription.swift Suzzme/Core/Voice/SuzzmePCM16AudioConverter.swift \
 Validation/VoiceTestCloudStub.swift \
 "$output/VoiceQuality.swift" -o "$output/VoiceQuality"
"$output/VoiceQuality"
