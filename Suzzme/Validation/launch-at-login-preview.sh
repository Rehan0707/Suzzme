#!/bin/zsh
set -eu
cd "${0:A:h}/.."
launch_at_login_output=$(mktemp -d)
trap 'rm -rf "$launch_at_login_output"' EXIT

report=Validation/Reports/LaunchAtLogin-20261023
mkdir -p "$report"
xcrun swiftc -disable-sandbox -swift-version 6 -parse-as-library \
  -module-cache-path "$launch_at_login_output/cache" \
  -framework AppKit -framework ServiceManagement \
  Suzzme/DesignSystem/Theme/SuzzmeTheme.swift \
  Suzzme/Platform/macOS/MacLaunchAtLoginController.swift \
  Suzzme/Features/Settings/MacLaunchAtLoginSettingsSection.swift \
  Validation/LaunchAtLoginPreview.swift \
  -o "$launch_at_login_output/LaunchAtLoginPreview"

"$launch_at_login_output/LaunchAtLoginPreview" "$report"
