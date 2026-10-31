#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -disable-sandbox -swift-version 6 -parse-as-library \
 -enable-upcoming-feature NonisolatedNonsendingByDefault -module-cache-path "$output/cache" \
 -framework AVFoundation -framework Speech -framework NaturalLanguage \
 Suzzme/Core/Models/SuzzmeAssistantState.swift \
 Suzzme/Core/Voice/VoiceTranscriptFinalizer.swift \
 Suzzme/Core/Voice/SuzzmeAssemblyAITranscription.swift \
 Suzzme/Core/Voice/SuzzmePCM16AudioConverter.swift \
 Validation/VoiceTestCloudStub.swift \
 Suzzme/Core/Voice/VoiceSessionController.swift \
 Validation/VoiceLifecycleAcceptanceChecks.swift -o "$output/VoiceChecks"
"$output/VoiceChecks"
