#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -swift-version 6 -D SHARE_HANDOFF_CHECKS -parse-as-library -module-cache-path "$output/cache" \
 ShareShared/SharedWebInbox.swift Validation/SharedWebHandoffChecks.swift -o "$output/checks"
"$output/checks"
