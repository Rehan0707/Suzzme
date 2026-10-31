#!/bin/zsh
set -eu
cd "${0:A:h}/.."
background_tasks_output=$(mktemp -d)
trap 'rm -rf "$background_tasks_output"' EXIT
xcrun swiftc -disable-sandbox -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -module-cache-path "$background_tasks_output/cache" \
  Suzzme/Core/Persistence/RecoverableJSONFile.swift \
  Suzzme/Core/Background/ScheduledBriefingModels.swift \
  Suzzme/Core/Background/ScheduledBriefingActivity.swift \
  Suzzme/Core/Background/ScheduledBriefingStore.swift \
  Suzzme/Core/Background/ScheduledBriefingEngine.swift \
  Suzzme/Features/Background/BackgroundTasksPresentation.swift \
  Validation/BackgroundTasksChecks.swift -o "$background_tasks_output/BackgroundTasksChecks"
"$background_tasks_output/BackgroundTasksChecks"
