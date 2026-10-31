#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
sources=( \
 Suzzme/Core/Models/SuzzmeItem.swift Suzzme/Core/Models/ExtractedSuzzmeItem.swift \
 Suzzme/Core/Models/DailyBriefing.swift Suzzme/Core/Models/SuzzmeAssistantState.swift \
 Suzzme/Core/Persistence/StoredSuzzmeItem.swift \
 Suzzme/Core/Context/SuzzmeContextItem.swift Suzzme/Core/Context/SuzzmeContextQuery.swift Suzzme/Core/Context/ContextEngine.swift \
 Suzzme/Core/Privacy/PrivacyEngine.swift Suzzme/Core/Memory/SessionMemoryEngine.swift \
 Suzzme/Core/Actions/SuzzmeAction.swift Suzzme/Core/Actions/CapabilityActionModels.swift Suzzme/Core/Actions/ActionPlanner.swift \
 Suzzme/Core/Actions/ActionPolicy.swift Suzzme/Core/Actions/ActionMutation.swift \
 Suzzme/Core/Connectors/AppleContextSources.swift Suzzme/Core/Connectors/AppleContextPermissions.swift \
 Suzzme/Core/Actions/EventKitCapabilities.swift Suzzme/Core/Actions/ActionExecutionCoordinator.swift Suzzme/Core/Actions/SettingsCapability.swift \
 Suzzme/DesignSystem/Theme/SuzzmeTheme.swift Suzzme/Core/Invocation/SuzzmePresenceTheme.swift Suzzme/Core/Invocation/AssistantPresentation.swift \
 Suzzme/Core/Intelligence/IntelligenceCapability.swift Suzzme/Core/Context/ScreenContext.swift Suzzme/Core/Context/ScreenContextPolicy.swift \
 Suzzme/Core/Intelligence/IntelligenceService.swift Suzzme/Core/Intelligence/BasicIntelligenceService.swift \
 Suzzme/Core/Intelligence/SuzzmeUnderstandingPipeline.swift Suzzme/Core/Intelligence/IntelligenceRouter.swift \
 Suzzme/Core/LongTermMemory/LongTermMemoryModels.swift Suzzme/Core/LongTermMemory/LongTermMemoryStore.swift Suzzme/Core/LongTermMemory/LongTermMemoryEngine.swift \
 Suzzme/Core/Information/InformationModels.swift Suzzme/Core/Information/InformationStore.swift Suzzme/Core/Information/InformationEngine.swift Suzzme/Core/Information/InformationRequest.swift \
 Suzzme/Core/Proactive/ProactiveModels.swift Suzzme/Core/Persistence/RecoverableJSONFile.swift \
 Suzzme/Core/Proactive/ProactiveIntelligenceStore.swift Suzzme/Core/Proactive/ProactiveIntelligenceEngine.swift \
 Suzzme/Core/Intelligence/SuzzmeCore.swift Suzzme/Core/Intelligence/AppleIntelligenceService.swift \
 Suzzme/Core/Integrations/IntegrationModels.swift Suzzme/Core/Integrations/CustomMCPModels.swift Suzzme/Core/Integrations/ProviderReadRecipe.swift Suzzme/Core/Integrations/GoogleProviderRecipes.swift Suzzme/Core/Integrations/IntegrationResource.swift \
 Suzzme/Core/Integrations/IntegrationStore.swift Suzzme/Core/Integrations/IntegrationCredentials.swift \
 Suzzme/Core/Integrations/IntegrationGateway.swift Suzzme/Core/Integrations/NotionIntegrationClient.swift \
 Suzzme/Core/Integrations/GoogleProviderScopeStore.swift Suzzme/Core/Integrations/ProviderReadClient.swift \
 Suzzme/Core/Integrations/IntegrationTransportSecurity.swift Suzzme/Core/Integrations/LinearIntegrationClient.swift \
 Suzzme/Core/Integrations/IntegrationInformationSource.swift \
 Validation/Step8StoreDouble.swift Validation/NotionCoreChecks.swift )
# Compile an exact temporary snapshot so simultaneous app builds or unrelated
# editor saves cannot alter compiler inputs halfway through this acceptance run.
for source in "${sources[@]}"; do
    mkdir -p "$output/source/${source:h}"
    cp "$source" "$output/source/$source"
done
cd "$output/source"
xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path "$output/module-cache" -framework SwiftData -framework SwiftUI \
 "${sources[@]}" -o "$output/checks"
"$output/checks"
