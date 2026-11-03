#!/bin/zsh
set -eu
cd "${0:A:h}/.."
render_root="${1:-/tmp/SuzzmeCompanionNativeReview}"
bundle="$render_root/CompanionNativeReview.app"
mkdir -p "$bundle"
cat > "$bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.suzzme.CompanionNativeReview</string>
<key>CFBundleName</key><string>Companion Review</string>
<key>CFBundleExecutable</key><string>CompanionNativeReview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
</dict></plist>
PLIST
xcrun actool SuzzmePresenceWidget/Assets.xcassets --compile "$bundle" --platform iphonesimulator \
 --minimum-deployment-target 17.0 --target-device iphone --output-partial-info-plist "$render_root/assets.plist"
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
render_flags=()
if [[ "${2:-}" == cli ]]; then render_flags=(-D SUZZME_PRESENCE_RENDER_CLI); fi
xcrun --sdk iphonesimulator swiftc -swift-version 6 -parse-as-library -D SUZZME_PRESENCE_RENDER \
 "${render_flags[@]}" \
 -sdk "$sdk" -target arm64-apple-ios17.0-simulator -module-cache-path "$render_root/cache" \
 PresenceShared/SuzzmeLiveActivityPhase.swift PresenceShared/SuzzmeLiveActivityAttributes.swift \
 PresenceShared/SuzzmeCompanionSnapshot.swift PresenceShared/SuzzmeCharacterArtwork.swift \
 PresenceShared/SuzzmeCompanionStyle.swift PresenceShared/SuzzmeCompanionSurfaces.swift \
 SuzzmePresenceWidget/SuzzmePresenceWidget.swift SuzzmePresenceWidget/SuzzmeCompanionWidget.swift \
 Validation/CompanionNativeRender.swift -o "$bundle/CompanionNativeReview"
codesign --force --sign - "$bundle"
print "$bundle"
