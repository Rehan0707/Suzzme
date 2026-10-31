#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
bundle="$output/PresenceRender.app"
resources="$bundle/Contents/Resources"
assets="$output/PresenceAssets.xcassets"
mkdir -p "$bundle/Contents/MacOS" "$resources" "$assets"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.suzzme.validation.presence-render</string>
<key>CFBundleName</key><string>PresenceRender</string>
<key>CFBundleExecutable</key><string>PresenceRender</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
cp Suzzme/Assets.xcassets/Contents.json "$assets/Contents.json"
for asset in Canvas.colorset Surface.colorset AccentColor.colorset PurpleWash.colorset; do
    cp -R "Suzzme/Assets.xcassets/$asset" "$assets/"
done
for asset in Suzzme/Assets.xcassets/SuzzmeMascot*.imageset; do
    cp -R "$asset" "$assets/"
done
cp Suzzme/Resources/MascotAnimations/*.gif "$resources/"
xcrun actool "$assets" --compile "$resources" --platform macosx \
    --minimum-deployment-target 14.0 --output-partial-info-plist "$output/asset-info.plist"
xcrun swiftc -swift-version 6 -whole-module-optimization -parse-as-library -module-cache-path "$output/cache" -framework AppKit -framework SwiftUI -framework Carbon \
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
 Validation/FinalUIPresenceRender.swift -o "$bundle/Contents/MacOS/PresenceRender"
"$bundle/Contents/MacOS/PresenceRender" "${1:-Validation/Reports/FinalUI/PresencePreviews}" "${2:-blue}"
