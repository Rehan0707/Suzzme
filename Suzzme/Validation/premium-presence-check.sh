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
 Validation/PremiumPresenceChecks.swift -o "$output/PremiumPresenceChecks"
"$output/PremiumPresenceChecks"
