#!/bin/zsh
set -eu
cd "${0:A:h}/.."
watched_policy_output=$(mktemp -d)
trap 'rm -rf "$watched_policy_output"' EXIT

# Compile the production policy, privacy classifier and legacy store. No network
# client, app startup, provider account or system resolver invocation is run.
xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path "$watched_policy_output/cache" \
  Suzzme/Core/Models/SuzzmeItem.swift \
  Suzzme/Core/Context/SuzzmeContextItem.swift \
  Suzzme/Core/Context/SuzzmeContextQuery.swift \
  Suzzme/Core/Privacy/PrivacyEngine.swift \
  Suzzme/Core/Persistence/RecoverableJSONFile.swift \
  Suzzme/Core/Information/WatchedLinks/WatchedLinkModels.swift \
  Suzzme/Core/Information/WatchedLinks/WebURLPolicy.swift \
  Suzzme/Core/Information/WatchedLinks/WebContentExtractor.swift \
  Suzzme/Core/Information/WatchedLinks/WatchedLinkStore.swift \
  Validation/WatchedURLPolicyChecks.swift -o "$watched_policy_output/checks"
"$watched_policy_output/checks"
