#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -framework SwiftData \
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
    Suzzme/Core/Intelligence/IntelligenceCapability.swift \
    Suzzme/Core/Intelligence/IntelligenceService.swift \
    Suzzme/Core/Intelligence/BasicIntelligenceService.swift \
    Suzzme/Core/Intelligence/SuzzmeUnderstandingPipeline.swift \
    Suzzme/Core/Intelligence/IntelligenceRouter.swift \
    Suzzme/Core/LongTermMemory/LongTermMemoryModels.swift \
    Suzzme/Core/LongTermMemory/LongTermMemoryStore.swift \
    Suzzme/Core/LongTermMemory/LongTermMemoryEngine.swift \
    Suzzme/Core/Intelligence/SuzzmeCore.swift \
    Suzzme/Core/Intelligence/AppleIntelligenceService.swift \
    Validation/Step3Checks.swift -o "$output/Step3Checks"
"$output/Step3Checks"
