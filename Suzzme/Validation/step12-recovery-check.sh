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
  Suzzme/Core/Models/ExtractedSuzzmeItem.swift \
  Suzzme/Core/Models/DailyBriefing.swift \
  Suzzme/Core/Persistence/StoredSuzzmeItem.swift \
  Suzzme/Core/Memory/SessionMemoryEngine.swift \
  Suzzme/Core/Actions/SuzzmeAction.swift \
  Suzzme/Core/Actions/ActionPlanner.swift \
  Suzzme/Core/Intelligence/IntelligenceCapability.swift \
  Suzzme/Core/Intelligence/IntelligenceService.swift \
  Suzzme/Core/Intelligence/BasicIntelligenceService.swift \
  Suzzme/Core/Intelligence/SuzzmeUnderstandingPipeline.swift \
  Suzzme/Core/Intelligence/IntelligenceRouter.swift \
  Suzzme/Core/LongTermMemory/LongTermMemoryEngine.swift \
  Suzzme/Core/Information/InformationRequest.swift \
  Suzzme/Core/Intelligence/SuzzmeCore.swift \
  Suzzme/Core/Intelligence/AppleIntelligenceService.swift \
  Suzzme/Platform/Shared/ProactiveNotificationDelivery.swift \
  Validation/Step12RecoveryChecks.swift -o "$output/Step12RecoveryChecks"

"$output/Step12RecoveryChecks"
