#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -framework EventKit -framework SwiftUI \
  Suzzme/Core/Models/SuzzmeItem.swift \
  Suzzme/Core/Models/SuzzmeAssistantState.swift \
  Suzzme/Core/Context/SuzzmeContextQuery.swift \
  Suzzme/Core/Actions/SuzzmeAction.swift \
  Suzzme/Core/Actions/CapabilityActionModels.swift \
  Suzzme/Core/Actions/ActionPolicy.swift \
  Suzzme/Core/Actions/ActionMutation.swift \
  Suzzme/Core/Actions/ActionPlanner.swift \
  Suzzme/Core/Connectors/AppleContextSources.swift \
  Suzzme/Core/Connectors/AppleContextPermissions.swift \
  Suzzme/Core/Actions/EventKitCapabilities.swift \
  Suzzme/Core/Actions/ActionExecutionCoordinator.swift \
  Suzzme/Core/Context/SuzzmeContextItem.swift \
  Suzzme/Core/Privacy/PrivacyEngine.swift \
  Suzzme/DesignSystem/Theme/SuzzmeTheme.swift \
  Suzzme/Core/Invocation/SuzzmePresenceTheme.swift \
  Suzzme/Core/Invocation/AssistantPresentation.swift \
  Validation/Step8StoreDouble.swift \
  Validation/Step8Checks.swift -o "$output/Step8Checks"
result=$("$output/Step8Checks")
print -r -- "$result"
executed=$(print -r -- "$result" | awk -F': ' '/^Behavioral tests executed:/ { print $2 }')
passed=$(print -r -- "$result" | awk -F': ' '/^Behavioral tests passed:/ { print $2 }')
failed=$(print -r -- "$result" | awk -F': ' '/^Behavioral tests failed:/ { print $2 }')
[[ "$executed" =~ '^[0-9]+$' && "$executed" -ge 60 ]]
[[ "$passed" == "$executed" && "$failed" == "0" ]]
if rg -n 'import EventKit|EKEventStore' Suzzme/Core/Intelligence Suzzme/App Suzzme/Features Suzzme/Intents Suzzme/Platform; then
  print 'FAIL: EventKit access above capability boundary'
  exit 1
fi
[[ $(rg -l '^actor SuzzmeCore' Suzzme | wc -l | tr -d ' ') == 1 ]]
[[ $(rg -l '^final class VoiceSessionController' Suzzme | wc -l | tr -d ' ') == 1 ]]

core_result=$(zsh Validation/step8-core-check.sh)
print -r -- "$core_result"
core_passed=$(print -r -- "$core_result" | awk -F': ' '/^Core integration checks passed:/ { print $2 }')
core_failed=$(print -r -- "$core_result" | awk -F': ' '/^Core integration checks failed:/ { print $2 }')
[[ "$core_passed" =~ '^[0-9]+$' && "$core_passed" -ge 22 && "$core_failed" == "0" ]]
print "Step 8 total checks passed: $((passed + core_passed))"
print 'Step 8 total checks failed: 0'
