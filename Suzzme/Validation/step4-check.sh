#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
  Suzzme/Core/Models/SuzzmeItem.swift Suzzme/Core/Models/ExtractedSuzzmeItem.swift Suzzme/Core/Models/DailyBriefing.swift \
  Suzzme/Core/Context/SuzzmeContextQuery.swift Suzzme/Core/Context/SuzzmeContextItem.swift Suzzme/Core/Context/ContextEngine.swift \
  Suzzme/Core/Privacy/PrivacyEngine.swift Suzzme/Core/Intelligence/IntelligenceCapability.swift Suzzme/Core/Intelligence/IntelligenceService.swift \
  Suzzme/Core/Intelligence/BasicIntelligenceService.swift Suzzme/Core/Intelligence/SuzzmeUnderstandingPipeline.swift Suzzme/Core/Intelligence/IntelligenceRouter.swift \
  Suzzme/Core/Intelligence/AppleIntelligenceService.swift Validation/Step4Checks.swift -o "$output/Step4Checks"
"$output/Step4Checks"
