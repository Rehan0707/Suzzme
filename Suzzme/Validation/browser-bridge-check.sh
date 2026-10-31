#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path "$output/cache" \
 Suzzme/Core/BrowserBridge/BrowserBridgeEngine.swift Suzzme/Core/BrowserBridge/BrowserBridgeIPC.swift Suzzme/Core/BrowserBridge/NativeMessagingFrame.swift Validation/BrowserBridgeChecks.swift -o "$output/checks"
"$output/checks"
