#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
app="$output/MascotPreview.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MascotPreview</string>
<key>CFBundleIdentifier</key><string>dev.suzzme.mascot-preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
xcrun actool Suzzme/Assets.xcassets --compile "$app/Contents/Resources" \
 --platform macosx --minimum-deployment-target 14.0 --target-device mac \
 --output-partial-info-plist "$output/assets.plist" > "$output/actool.log"
cp Suzzme/Resources/MascotAnimations/*.gif "$app/Contents/Resources/"
xcrun swiftc -disable-sandbox -whole-module-optimization -swift-version 6 -parse-as-library -module-cache-path "$output/cache" \
 -framework AppKit -framework SwiftUI \
 Suzzme/Core/Models/SuzzmeAssistantState.swift \
 Suzzme/Core/Invocation/AssistantPresentation.swift \
 Suzzme/Core/Invocation/SuzzmePresenceTheme.swift \
 Suzzme/DesignSystem/Theme/SuzzmeTheme.swift \
 Suzzme/DesignSystem/Components/SuzzmeGlassSurface.swift \
 PresenceShared/SuzzmeCharacterArtwork.swift \
 Suzzme/DesignSystem/Components/SuzzmeFace.swift \
 Suzzme/DesignSystem/Components/SuzzmeMascotArtwork.swift \
 Suzzme/DesignSystem/Components/SuzzmeMascot.swift \
 Suzzme/DesignSystem/Components/SuzzmeAssistantPresenceView.swift \
 Validation/MascotRender.swift -o "$app/Contents/MacOS/MascotPreview"
"$app/Contents/MacOS/MascotPreview" "${1:-Validation/Reports/Mascot}"
