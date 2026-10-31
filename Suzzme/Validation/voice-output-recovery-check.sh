#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT

cat Suzzme/Core/Voice/VoiceSessionController.swift Validation/VoiceOutputRecoveryChecks.swift > "$output/VoiceRecovery.swift"
xcrun swiftc -disable-sandbox -swift-version 6 \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -parse-as-library -module-cache-path "$output/cache" \
  -framework AVFoundation -framework Speech -framework NaturalLanguage \
  Suzzme/Core/Models/SuzzmeAssistantState.swift \
  Suzzme/Core/Voice/VoiceTranscriptFinalizer.swift \
  Suzzme/Core/Voice/SuzzmeAssemblyAITranscription.swift \
  Suzzme/Core/Voice/SuzzmePCM16AudioConverter.swift \
  "$output/VoiceRecovery.swift" -o "$output/checks"
"$output/checks"
