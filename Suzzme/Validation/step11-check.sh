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
  Validation/Step11Checks.swift -o "$output/Step11Checks"

set +e
result=$($output/Step11Checks)
test_status=$?
set -e
print -r -- "$result"
[[ "$test_status" == "0" ]]
passed=$(print -r -- "$result" | awk -F': ' '/^Step 11 behavioral checks passed:/ { print $2 }')
failed=$(print -r -- "$result" | awk -F': ' '/^Step 11 behavioral checks failed:/ { print $2 }')
[[ "$passed" == "220" ]]
[[ "$failed" == "0" ]]

# Supplemental architecture/security audit. Runtime behavior above remains the acceptance proof.
[[ $(rg -l '^actor SuzzmeCore' Suzzme | wc -l | tr -d ' ') == 1 ]]
[[ $(rg -l '^final class VoiceSessionController' Suzzme | wc -l | tr -d ' ') == 1 ]]
[[ $(rg -l '^actor InformationEngine' Suzzme | wc -l | tr -d ' ') == 1 ]]
[[ $(rg -l '^actor ProactiveIntelligenceEngine' Suzzme | wc -l | tr -d ' ') == 1 ]]
if rg -n 'WKWebView|SFSafariViewController|import ActivityKit|DynamicIslandExpandedRegion|URL\(string: "file:|URL\(string: "http:' Suzzme/Core/Information/WatchedLinks Suzzme/Core/Invocation; then
  print 'FAIL: forbidden Step 11 implementation surface'
  exit 1
fi
if rg -n 'EKEventStore|memoryStore\.commit|LongTermMemoryStore' Suzzme/Core/Information/WatchedLinks Suzzme/Core/Proactive/ProactiveModels.swift; then
  print 'FAIL: Step 11 observation crossed a mutation boundary'
  exit 1
fi
print 'Step 11 production behavioral checks passed: 220'
print 'Step 11 production behavioral checks failed: 0'
