#!/bin/zsh
set -eu
cd "${0:A:h}/.."
launch_at_login_output=$(mktemp -d)
trap 'rm -rf "$launch_at_login_output"' EXIT

xcrun swiftc -disable-sandbox -swift-version 6 -parse-as-library \
  -module-cache-path "$launch_at_login_output/cache" \
  -framework ServiceManagement \
  Suzzme/Platform/macOS/MacLaunchAtLoginController.swift \
  Validation/LaunchAtLoginChecks.swift \
  -o "$launch_at_login_output/LaunchAtLoginChecks"

"$launch_at_login_output/LaunchAtLoginChecks"
