#!/bin/zsh
set -eu
cd "${0:A:h}/.."
render_root=$(mktemp -d)
trap 'rm -rf "$render_root"' EXIT
bundle="$render_root/CompanionHostReview.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.suzzme.CompanionHostReview</string>
<key>CFBundleExecutable</key><string>CompanionHostReview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
xcrun actool SuzzmePresenceWidget/Assets.xcassets --compile "$bundle/Contents/Resources" \
 --platform macosx --minimum-deployment-target 14.0 --output-partial-info-plist "$render_root/assets.plist"
xcrun swiftc -swift-version 6 -whole-module-optimization -parse-as-library -module-cache-path /tmp/SuzzmeCompanionHostModuleCache \
 -framework AppKit -framework SwiftUI -framework WidgetKit \
 PresenceShared/SuzzmeLiveActivityPhase.swift PresenceShared/SuzzmeCompanionSnapshot.swift \
 PresenceShared/SuzzmeCharacterArtwork.swift PresenceShared/SuzzmeCompanionStyle.swift PresenceShared/SuzzmeCompanionSurfaces.swift \
 Validation/CompanionNativeHostRender.swift -o "$bundle/Contents/MacOS/CompanionHostReview"
"$bundle/Contents/MacOS/CompanionHostReview" "${1:-Validation/Reports/CompanionNative/Images}"
