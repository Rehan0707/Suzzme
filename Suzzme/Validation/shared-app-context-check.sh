#!/bin/zsh
set -eu
cd "${0:A:h}/.."
local_knowledge_check_output=$(mktemp -d)
local_knowledge_check_cache="${TMPDIR:-/tmp}/suzzme-step17-summary-follow-up-module-cache"
trap 'rm -rf "$local_knowledge_check_output"' EXIT

xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path "$local_knowledge_check_cache" -framework SwiftData -framework SwiftUI -framework EventKit -framework Contacts \
  Suzzme/Core/Models/SuzzmeItem.swift \
  Suzzme/Core/Models/ExtractedSuzzmeItem.swift \
  Suzzme/Core/Models/DailyBriefing.swift \
  Suzzme/Core/Models/SuzzmeAssistantState.swift \
  Suzzme/DesignSystem/Theme/SuzzmeTheme.swift \
  Suzzme/Core/Invocation/SuzzmePresenceTheme.swift \
  Suzzme/Core/Invocation/AssistantPresentation.swift \
  Suzzme/Core/Persistence/StoredSuzzmeItem.swift \
  Suzzme/Core/Persistence/SuzzmeItemStore.swift \
  Suzzme/Core/Persistence/RecoverableJSONFile.swift \
  Suzzme/Core/Context/SuzzmeContextItem.swift \
  Suzzme/Core/Context/SuzzmeContextQuery.swift \
  Suzzme/Core/Context/ScreenContext.swift \
  Suzzme/Core/Context/ScreenContextPolicy.swift \
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
  Validation/Step8StoreDouble.swift \
  Suzzme/Core/Actions/SettingsCapability.swift \
  Suzzme/Core/Intelligence/IntelligenceCapability.swift \
  Suzzme/Core/Intelligence/IntelligenceService.swift \
  Suzzme/Core/Intelligence/BasicIntelligenceService.swift \
  Suzzme/Core/Intelligence/AppleIntelligenceService.swift \
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
  Suzzme/Core/Proactive/ProactiveIntelligenceStore.swift \
  Suzzme/Core/Proactive/ProactiveIntelligenceEngine.swift \
  Suzzme/Core/Intelligence/SuzzmeCore.swift \
  Suzzme/Core/Knowledge/LocalKnowledgeEngine.swift \
  Suzzme/Core/Knowledge/LocalKnowledgeController.swift \
  Suzzme/Core/Integrations/SharedAppContext.swift \
  Suzzme/Core/Integrations/SharedAppScreenshot.swift \
  Suzzme/Core/Integrations/SharedAppContextController.swift \
  Validation/SharedAppContextChecks.swift -o "$local_knowledge_check_output/SharedAppContextChecks"

"$local_knowledge_check_output/SharedAppContextChecks" "$@"
