#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -framework SwiftData \
  Suzzme/Core/Models/SuzzmeItem.swift \
  Suzzme/Core/Persistence/StoredSuzzmeItem.swift \
  Suzzme/Core/LongTermMemory/LongTermMemoryModels.swift \
  Suzzme/Core/LongTermMemory/LongTermMemoryStore.swift \
  Suzzme/Core/LongTermMemory/LongTermMemoryEngine.swift \
  Validation/Step6BehavioralChecks.swift -o "$output/Step6Checks"
result=$("$output/Step6Checks")
print -r -- "$result"

executed=$(print -r -- "$result" | awk -F': ' '/^Behavioral tests executed:/ { print $2 }')
passed=$(print -r -- "$result" | awk -F': ' '/^Behavioral tests passed:/ { print $2 }')
failed=$(print -r -- "$result" | awk -F': ' '/^Behavioral tests failed:/ { print $2 }')
coverage=$(print -r -- "$result" | awk -F': ' '/^Required coverage status:/ { print $2 }')

[[ "$executed" =~ '^[0-9]+$' && "$executed" -ge 40 ]]
[[ "$passed" == "$executed" ]]
[[ "$failed" == "0" ]]
[[ "$coverage" == "PASS" ]]
