#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -disable-sandbox -swift-version 6 -whole-module-optimization -parse-as-library -module-cache-path "$output/cache" -framework AppKit -framework SwiftUI -framework Carbon \
 Suzzme/Core/Models/SuzzmeAssistantState.swift \
 Suzzme/Core/Invocation/AssistantPresentation.swift \
 Suzzme/Core/Invocation/SuzzmePresenceTheme.swift \
 Suzzme/Core/Integrations/IntegrationModels.swift \
 Suzzme/Core/Integrations/IntegrationResource.swift \
 Suzzme/Core/Integrations/ProviderReadRecipe.swift \
 Suzzme/Core/Integrations/GoogleProviderRecipes.swift \
 Suzzme/DesignSystem/Theme/SuzzmeTheme.swift \
 Suzzme/DesignSystem/Components/SuzzmeGlassSurface.swift \
 PresenceShared/SuzzmeCharacterArtwork.swift \
 Suzzme/DesignSystem/Components/SuzzmeMascotArtwork.swift \
 Suzzme/DesignSystem/Components/SuzzmeMascot.swift \
 Suzzme/DesignSystem/Components/SuzzmeFace.swift \
 Suzzme/DesignSystem/Components/SuzzmeAssistantPresenceView.swift \
 Suzzme/Core/Background/ScheduledBriefingModels.swift \
 Suzzme/Core/Background/ScheduledBriefingActivity.swift \
 Suzzme/Platform/macOS/MacBackgroundPreparationView.swift \
 Suzzme/Platform/macOS/MacAssistantPresence.swift \
 Validation/Step12PresenceChecks.swift -o "$output/PresenceChecks"
"$output/PresenceChecks" "$@" | tee "$output/results.log"
if [[ "${1:-}" == "--placement-only" ]]; then
    grep -q '^Presence placement checks passed: 9$' "$output/results.log"
else
    grep -q '^Presence runtime checks failed: 0$' "$output/results.log"
fi
