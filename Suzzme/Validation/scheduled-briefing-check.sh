#!/bin/zsh
set -eu
cd "${0:A:h}/.."
scheduled_briefing_output=$(mktemp -d)
trap 'rm -rf "$scheduled_briefing_output"' EXIT

xcrun swiftc -disable-sandbox -swift-version 6 -parse-as-library \
  -module-cache-path "$scheduled_briefing_output/cache" \
  Suzzme/Core/Persistence/RecoverableJSONFile.swift \
  Suzzme/Core/Background/ScheduledBriefingModels.swift \
  Suzzme/Core/Background/ScheduledBriefingActivity.swift \
  Suzzme/Core/Background/ScheduledBriefingStore.swift \
  Suzzme/Core/Background/ScheduledBriefingEngine.swift \
  Validation/ScheduledBriefingChecks.swift -o "$scheduled_briefing_output/ScheduledBriefingChecks"

"$scheduled_briefing_output/ScheduledBriefingChecks"
