#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
  Suzzme/Core/Models/SuzzmeAssistantState.swift \
  Suzzme/Core/Voice/VoiceTranscriptFinalizer.swift \
  Validation/Step5Checks.swift -o "$output/Step5Checks"
"$output/Step5Checks"
