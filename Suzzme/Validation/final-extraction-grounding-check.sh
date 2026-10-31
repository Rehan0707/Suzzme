#!/bin/zsh
set -eu
cd "${0:A:h}/.."
final_extraction_output=$(mktemp -d)
final_extraction_cache="${TMPDIR:-/tmp}/suzzme-final-extraction-module-cache"
trap 'rm -rf "$final_extraction_output"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path "$final_extraction_cache" \
    Suzzme/Core/Models/*.swift \
    Suzzme/Core/Intelligence/IntelligenceCapability.swift \
    Suzzme/Core/Context/SuzzmeContextItem.swift \
    Suzzme/Core/Context/SuzzmeContextQuery.swift \
    Suzzme/Core/Privacy/PrivacyEngine.swift \
    Suzzme/Core/Context/ScreenContext.swift \
    Suzzme/Core/Context/ScreenContextPolicy.swift \
    Suzzme/Core/Intelligence/IntelligenceService.swift \
    Suzzme/Core/Intelligence/MockIntelligenceService.swift \
    Suzzme/Core/Intelligence/BasicIntelligenceService.swift \
    Suzzme/Core/Intelligence/DailyBriefingBuilder.swift \
    Suzzme/Core/Intelligence/SuzzmeUnderstandingPipeline.swift \
    Suzzme/Core/Intelligence/AppleIntelligenceService.swift \
    Suzzme/Core/Actions/CapabilityActionModels.swift \
    Suzzme/Core/Actions/ActionPlanner.swift \
    Validation/FinalExtractionGroundingChecks.swift \
    -o "$final_extraction_output/FinalExtractionGroundingChecks"
"$final_extraction_output/FinalExtractionGroundingChecks"
