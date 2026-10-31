#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
  PresenceShared/SuzzmeLiveActivityPhase.swift \
  Suzzme/Core/Models/SuzzmeAssistantState.swift \
  Validation/LiveActivityChecks.swift -o "$output/LiveActivityChecks"
"$output/LiveActivityChecks"
! rg -n 'URLSession|EventKit|SuzzmeCore|AVAudioEngine' PresenceShared SuzzmePresenceWidget
rg -q 'let liveActivity = SuzzmeLiveActivityController\(\)' Suzzme/App/SuzzmeAppStartup.swift
rg -q 'await liveActivity.update\(.idle\)' Suzzme/App/SuzzmeAppStartup.swift
rg -q 'foreground: self.applicationPhase != .background' Suzzme/App/SuzzmeAppStartup.swift
rg -Fq 'applicationRuntime?.updateLiveActivity' Suzzme/App/ContentView.swift
! rg -q '@State private var liveActivity' Suzzme/App/ContentView.swift
rg -q 'staleDate:' Suzzme/Platform/iOS/SuzzmeLiveActivityController.swift
