#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -framework SwiftData -framework SwiftUI \
    Suzzme/Core/Models/SuzzmeItem.swift \
    Suzzme/Core/Models/ExtractedSuzzmeItem.swift \
    Suzzme/Core/Models/DailyBriefing.swift \
    Suzzme/Core/Models/SuzzmeAssistantState.swift \
    Suzzme/Core/Persistence/StoredSuzzmeItem.swift \
    Suzzme/Core/Context/SuzzmeContextItem.swift \
    Suzzme/Core/Context/SuzzmeContextQuery.swift \
    Suzzme/Core/Context/ContextEngine.swift \
    Suzzme/Core/Privacy/PrivacyEngine.swift \
    Suzzme/Core/Memory/SessionMemoryEngine.swift \
    Suzzme/Core/Actions/SuzzmeAction.swift \
    Suzzme/Core/Actions/CapabilityActionModels.swift \
    Suzzme/Core/Actions/ActionPlanner.swift \
    Suzzme/Core/Actions/ActionPolicy.swift \
  Suzzme/Core/Actions/ActionMutation.swift \
    Suzzme/Core/Connectors/AppleContextSources.swift \
    Suzzme/Core/Connectors/AppleContextPermissions.swift \
  Suzzme/Core/Actions/EventKitCapabilities.swift \
    Suzzme/Core/Actions/ActionExecutionCoordinator.swift \
    Suzzme/Core/Actions/SettingsCapability.swift \
    Suzzme/DesignSystem/Theme/SuzzmeTheme.swift \
    Suzzme/Core/Invocation/SuzzmePresenceTheme.swift \
    Suzzme/Core/Invocation/AssistantPresentation.swift \
    Suzzme/Core/Intelligence/IntelligenceCapability.swift \
    Suzzme/Core/Intelligence/IntelligenceService.swift \
    Suzzme/Core/Intelligence/BasicIntelligenceService.swift \
    Suzzme/Core/Intelligence/SuzzmeUnderstandingPipeline.swift \
    Suzzme/Core/Intelligence/IntelligenceRouter.swift \
    Suzzme/Core/LongTermMemory/LongTermMemoryModels.swift \
    Suzzme/Core/LongTermMemory/LongTermMemoryStore.swift \
    Suzzme/Core/LongTermMemory/LongTermMemoryEngine.swift \
    Suzzme/Core/Information/InformationModels.swift \
    Suzzme/Core/Information/InformationStore.swift \
    Suzzme/Core/Information/InformationEngine.swift \
    Suzzme/Core/Information/InformationRequest.swift \
    Suzzme/Core/Proactive/ProactiveModels.swift \
    Suzzme/Core/Persistence/RecoverableJSONFile.swift \
  Suzzme/Core/Proactive/ProactiveIntelligenceStore.swift \
    Suzzme/Core/Proactive/ProactiveIntelligenceEngine.swift \
    Suzzme/Core/Intelligence/SuzzmeCore.swift \
    Suzzme/Core/Intelligence/AppleIntelligenceService.swift \
    Validation/Step8StoreDouble.swift Validation/Step9Checks.swift -o "$output/Step9Checks"
"$output/Step9Checks"

for phase in legacy seed reopen expire cleared; do
    "$output/Step9Checks" "$phase" "$output"
done
