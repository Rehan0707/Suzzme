#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
sdk=$(xcrun --sdk macosx --show-sdk-path)
xcrun swiftc -swift-version 6 -parse-as-library -sdk "$sdk" -target arm64-apple-macos14.0 \
    Suzzme/Core/Models/*.swift \
    Suzzme/Core/Intelligence/IntelligenceCapability.swift \
    Suzzme/Core/Intelligence/IntelligenceService.swift \
    Suzzme/Core/Intelligence/MockIntelligenceService.swift \
    Suzzme/Core/Intelligence/BasicIntelligenceService.swift \
    Suzzme/Core/Intelligence/DailyBriefingBuilder.swift \
    Suzzme/Core/Intelligence/SuzzmeUnderstandingPipeline.swift \
    Suzzme/Core/Intelligence/AppleIntelligenceService.swift \
    Suzzme/Core/Persistence/*.swift \
    Validation/PersistenceChecks.swift \
    -framework SwiftData -o "$output/PersistenceChecks"
"$output/PersistenceChecks"
