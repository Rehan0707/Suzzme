#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT

xcrun swiftc -swift-version 6 -parse-as-library -framework SwiftData -framework SwiftUI -framework EventKit -framework AVFoundation -framework Speech -framework Contacts \
  Suzzme/Core/Models/SuzzmeItem.swift \
  Suzzme/Core/Models/SuzzmeAssistantState.swift \
  Suzzme/Core/Context/SuzzmeContextItem.swift \
  Suzzme/Core/Context/SuzzmeContextQuery.swift \
  Suzzme/Core/Context/ContextEngine.swift \
  Suzzme/Core/Connectors/AppleContextSources.swift \
  Suzzme/Core/Connectors/AppleContextPermissions.swift \
  Suzzme/Core/Privacy/PrivacyEngine.swift \
  Suzzme/Core/Privacy/CrossDevicePolicy.swift \
  Suzzme/Core/LongTermMemory/LongTermMemoryModels.swift \
  Suzzme/Core/LongTermMemory/LongTermMemoryStore.swift \
  Suzzme/Core/Information/InformationModels.swift \
  Suzzme/Core/Information/InformationStore.swift \
  Suzzme/Core/Information/InformationEngine.swift \
  Suzzme/Core/Information/WatchedLinks/WatchedLinkModels.swift \
  Suzzme/Core/Information/WatchedLinks/WebURLPolicy.swift \
  Suzzme/Core/Information/WatchedLinks/WebContentExtractor.swift \
  Suzzme/Core/Information/WatchedLinks/WatchedLinkStore.swift \
  Suzzme/Core/Information/WatchedLinks/WatchedWebSource.swift \
  Suzzme/Core/Proactive/ProactiveModels.swift \
  Suzzme/Core/Persistence/RecoverableJSONFile.swift \
  Suzzme/Core/Proactive/ProactiveIntelligenceStore.swift \
  Suzzme/Core/Proactive/ProactiveIntelligenceEngine.swift \
  Suzzme/Core/Actions/CapabilityActionModels.swift \
  Suzzme/Core/Actions/ActionPolicy.swift \
  Suzzme/Core/Actions/ActionExecutionCoordinator.swift \
  Suzzme/Core/Actions/EventKitCapabilities.swift \
  Suzzme/Core/Actions/ActionMutation.swift \
  Suzzme/Core/Actions/SettingsCapability.swift \
  Suzzme/DesignSystem/Theme/SuzzmeTheme.swift \
  Suzzme/Core/Invocation/SuzzmePresenceTheme.swift \
  Suzzme/Core/Invocation/AssistantPresentation.swift \
  Suzzme/Core/Voice/VoiceTranscriptFinalizer.swift \
  Suzzme/Core/Voice/VoiceSessionController.swift \
  Suzzme/Platform/Shared/ProactiveNotificationDelivery.swift \
  Validation/Step10Checks.swift -o "$output/Step10Checks"

set +e
result=$("$output/Step10Checks")
test_status=$?
set -e
print -r -- "$result"
[[ "$test_status" == "0" ]]
passed=$(print -r -- "$result" | awk -F': ' '/^Step 10 behavioral checks passed:/ { print $2 }')
failed=$(print -r -- "$result" | awk -F': ' '/^Step 10 behavioral checks failed:/ { print $2 }')
[[ "$passed" == "190" ]]
[[ "$failed" == "0" ]]

# Architectural boundaries are checked in addition to executing production behavior.
[[ $(rg -l '^actor SuzzmeCore' Suzzme | wc -l | tr -d ' ') == 1 ]]
[[ $(rg -l '^final class VoiceSessionController' Suzzme | wc -l | tr -d ' ') == 1 ]]
[[ $(rg -l '^actor ContextEngine' Suzzme | wc -l | tr -d ' ') == 1 ]]
[[ $(rg -l '^actor InformationEngine' Suzzme | wc -l | tr -d ' ') == 1 ]]
[[ $(rg -l '^struct LongTermMemoryEngine' Suzzme | wc -l | tr -d ' ') == 1 ]]
[[ $(rg -l '^actor ProactiveIntelligenceEngine' Suzzme | wc -l | tr -d ' ') == 1 ]]
if rg -n 'EKEventStore|SuzzmeActionExecutionCoordinator|EventKit.*Capability|memoryStore\.commit|information.*\.commit' Suzzme/Core/Proactive; then
  print 'FAIL: proactive layer crossed a mutation boundary'
  exit 1
fi
if rg -n 'http://|https://|OpenAI|Anthropic|Gemini|Firebase|Supabase' Suzzme/Core/Proactive Suzzme/Features/Briefing Suzzme/Features/Settings/ProactiveIntelligenceSettingsView.swift; then
  print 'FAIL: external dependency in Step 10'
  exit 1
fi

print "Step 10 production behavioral checks passed: $passed"
print 'Step 10 production behavioral checks failed: 0'
