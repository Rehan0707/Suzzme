#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT

# Compile the presentation domain with Swift 6. This is intentionally isolated
# from UI rendering and hardware; it verifies the production state mapping,
# preference persistence, and invocation ownership deterministically.
xcrun swiftc -swift-version 6 -parse-as-library -framework SwiftUI \
  Suzzme/DesignSystem/Theme/SuzzmeTheme.swift \
  Suzzme/Core/Models/SuzzmeAssistantState.swift \
  Suzzme/Core/Invocation/SuzzmePresenceTheme.swift \
  Suzzme/Core/Invocation/AssistantPresentation.swift \
  Validation/Step7Checks.swift -o "$output/Step7Checks"
result=$("$output/Step7Checks")
print -r -- "$result"

executed=$(print -r -- "$result" | awk -F': ' '/^Behavioral tests executed:/ { print $2 }')
passed=$(print -r -- "$result" | awk -F': ' '/^Behavioral tests passed:/ { print $2 }')
failed=$(print -r -- "$result" | awk -F': ' '/^Behavioral tests failed:/ { print $2 }')
coverage=$(print -r -- "$result" | awk -F': ' '/^Required coverage status:/ { print $2 }')
[[ "$executed" =~ '^[0-9]+$' && "$executed" -ge 90 ]]
[[ "$passed" == "$executed" ]]
[[ "$failed" == "0" ]]
[[ "$coverage" == "PASS" ]]

# Architectural invariants: one core, one voice session controller, and one
# supported App Intent handoff. The presence layer cannot own intelligence.
[[ $(rg -l '^actor SuzzmeCore|^final class SuzzmeCore' Suzzme | wc -l | tr -d ' ') == 1 ]]
[[ $(rg -l '^final class VoiceSessionController' Suzzme | wc -l | tr -d ' ') == 1 ]]
[[ $(rg -l '^struct StartSuzzmeIntent' Suzzme | wc -l | tr -d ' ') == 1 ]]
[[ $(rg -l 'AVAudioEngine' Suzzme | wc -l | tr -d ' ') == 1 ]]
! rg -n '@unchecked Sendable|ScreenCaptureKit|CGEventTap|AXIsProcessTrusted|ActivityKit' Suzzme >/dev/null
rg -q 'VoiceSessionController' Suzzme/App/AppEnvironment.swift
rg -q 'SuzzmeCore' Suzzme/App/AppEnvironment.swift
rg -q 'SuzzmeAssistantPresentation.make' Suzzme/Platform/macOS/MacAssistantPresence.swift
rg -q 'SuzzmeAssistantPresenceView' Suzzme/Platform/macOS/MacAssistantPresence.swift
rg -q 'RegisterEventHotKey' Suzzme/Platform/macOS/MacAssistantPresence.swift
rg -q 'presenceTheme' Suzzme/DesignSystem/Effects/SuzzmeHalo.swift
rg -q 'presenceAnimation' Suzzme/App/ContentView.swift
