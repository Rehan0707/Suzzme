#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
    Suzzme/Core/Models/*.swift \
    Suzzme/Core/Intelligence/IntelligenceCapability.swift \
    Suzzme/Core/Intelligence/IntelligenceService.swift \
    Suzzme/Core/Intelligence/MockIntelligenceService.swift \
    Suzzme/Core/Intelligence/BasicIntelligenceService.swift \
    Suzzme/Core/Intelligence/DailyBriefingBuilder.swift \
    Suzzme/Core/Intelligence/SuzzmeUnderstandingPipeline.swift \
    Suzzme/Core/Intelligence/AppleIntelligenceService.swift \
    Validation/FoundationChecks.swift \
    -o "$output/FoundationChecks"
"$output/FoundationChecks"
