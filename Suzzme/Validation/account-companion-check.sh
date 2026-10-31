#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -swift-version 6 -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -parse-as-library -module-cache-path "$output/cache" \
  Suzzme/App/AccountWelcomeProgress.swift Suzzme/App/CompanionSummaryTransport.swift \
  Suzzme/App/CompanionDeliveryPolicy.swift \
  Validation/AccountCompanionChecks.swift -o "$output/checks"
"$output/checks"
