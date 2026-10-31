#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -disable-sandbox -module-cache-path "$output/cache" -swift-version 6 -parse-as-library -framework SwiftUI \
 Suzzme/Core/Models/SuzzmeAssistantState.swift \
 Suzzme/Core/Invocation/AssistantPresentation.swift \
 Suzzme/Core/Invocation/SuzzmePresenceTheme.swift \
 Validation/GlobalShortcutChecks.swift -o "$output/GlobalShortcutChecks"
"$output/GlobalShortcutChecks" | tee "$output/results.log"
rg -q '^Global shortcut reducer checks passed: 29$' "$output/results.log"
