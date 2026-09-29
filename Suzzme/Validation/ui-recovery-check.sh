#!/bin/zsh
set -eu
cd "${0:A:h}/.."

passed=0
failed=0

check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    print "PASS: $name"
    passed=$((passed + 1))
  else
    print "FAIL: $name"
    failed=$((failed + 1))
  fi
}

contains() { rg -q -- "$2" "$1" }
absent() { ! rg -q -- "$2" "$1"; }
count_is() { [[ $(rg -o -- "$2" "$1" | wc -l | tr -d ' ') == "$3" ]]; }

check "semantic background token" contains Suzzme/DesignSystem/Theme/SuzzmeTheme.swift 'backgroundPrimary'
check "semantic intelligence token" contains Suzzme/DesignSystem/Theme/SuzzmeTheme.swift 'intelligencePrimary'
check "spacing scale" contains Suzzme/DesignSystem/Theme/SuzzmeTheme.swift 'enum Spacing'
check "radius scale" contains Suzzme/DesignSystem/Theme/SuzzmeTheme.swift 'enum Radius'
check "motion scale" contains Suzzme/DesignSystem/Theme/SuzzmeTheme.swift 'enum Motion'
check "single reusable Face type" count_is Suzzme/DesignSystem/Components/SuzzmeFace.swift '^struct SuzzmeFace:' 1
check "Home uses Face-led presence" contains Suzzme/Features/Home/HomeView.swift 'SuzzmeHalo'
check "Home voice primary action" contains Suzzme/Features/Home/HomeView.swift 'Talk to Suzzme'
check "Home typed secondary action" contains Suzzme/Features/Home/HomeView.swift 'Type to Suzzme'
check "production Settings reachable" contains Suzzme/Features/Home/HomeView.swift 'SettingsView'
check "compact navigation avoids all destinations" absent Suzzme/Platform/iOS/MobileRootView.swift 'ForEach\(AppDestination\.allCases\)'
check "compact navigation has three destinations" contains Suzzme/Platform/iOS/MobileRootView.swift '\[\.home, \.briefing, \.memory\]'
check "Ask uses central environment" contains Suzzme/Features/Home/AskSuzzmeView.swift 'environment.askSuzzme'
check "Ask shows exact action title" contains Suzzme/Features/Home/AskSuzzmeView.swift 'title: action.title'
check "Ask has semantic confirmation summary" contains Suzzme/Features/Home/AskSuzzmeView.swift 'SuzzmeConfirmationSummary'
check "Ask hides confidence metadata" absent Suzzme/Features/Home/AskSuzzmeView.swift 'Confidence'
check "Ask hides raw framework errors" absent Suzzme/Features/Home/AskSuzzmeView.swift 'localizedDescription'
check "Ask provides keyboard dismissal" contains Suzzme/Features/Home/AskSuzzmeView.swift 'placement: \.keyboard'
check "Memory delete requires confirmation" contains Suzzme/Features/Memory/MemoryView.swift 'confirmationDialog'
check "Memory explains deletion boundary" contains Suzzme/Features/Memory/MemoryView.swift 'recent source information are not affected'
check "Sources has permission recovery" contains Suzzme/Features/Sources/SourcesView.swift 'Open Settings'
check "Sources exposes real health" contains Suzzme/Features/Sources/InformationInspectionView.swift 'informationHealth'
check "Information distinguishes nothing new" contains Suzzme/Features/Sources/InformationInspectionView.swift 'Nothing new'
check "Information distinguishes unavailable" contains Suzzme/Features/Sources/InformationInspectionView.swift 'information is unavailable'
check "Information UI hides external IDs" absent Suzzme/Features/Sources/InformationInspectionView.swift 'externalID'
check "Information UI hides fingerprints" absent Suzzme/Features/Sources/InformationInspectionView.swift 'fingerprint'
check "Information UI hides normalization internals" absent Suzzme/Features/Sources/InformationInspectionView.swift 'normalizationVersion'
check "Settings has native groups" contains Suzzme/Features/Settings/SettingsView.swift 'Section\("Intelligence"\)'
check "Privacy controls are reachable" contains Suzzme/Features/Settings/SettingsDetailViews.swift 'struct PrivacyView'
check "Voice selection is visible" contains Suzzme/Features/Settings/VoiceSettingsView.swift 'checkmark'
check "onboarding has real permission requests" contains Suzzme/App/LaunchExperience.swift 'requestSourcePermission'
check "onboarding has no credential fields" absent Suzzme/App/LaunchExperience.swift 'SecureField|emailAddress|password'
check "Sign in with Apple is truthfully unavailable" contains Suzzme/App/LaunchExperience.swift 'Account sync is not available'
check "Presence respects Reduce Motion" contains Suzzme/DesignSystem/Components/SuzzmeAssistantPresenceView.swift 'accessibilityReduceMotion'
check "Presence respects Reduce Transparency" contains Suzzme/DesignSystem/Components/SuzzmeAssistantPresenceView.swift 'accessibilityReduceTransparency'
check "Presence respects Increased Contrast" contains Suzzme/DesignSystem/Components/SuzzmeAssistantPresenceView.swift 'colorSchemeContrast'
check "Home has small-width preview" contains Suzzme/Features/Home/HomeView.swift 'frame\(width: 320, height: 568\)'
check "Home has large-width preview" contains Suzzme/Features/Home/HomeView.swift 'frame\(width: 440, height: 956\)'
check "Home has accessibility type preview" contains Suzzme/Features/Home/HomeView.swift 'dynamicTypeSize, \.accessibility3'
check "Mac uses split navigation" contains Suzzme/Platform/macOS/MacRootView.swift 'NavigationSplitView'
check "Mac preserves non-notch policy" contains Suzzme/Core/Invocation/AssistantPresentation.swift 'topCenter'
check "no fake Dynamic Island implementation" absent Suzzme 'DynamicIsland|dynamicIsland|fake island'
check "UI Foundation skill exists" test -f ../.agents/skills/suzzme-ui-foundation/SKILL.md
check "Screen Patterns skill exists" test -f ../.agents/skills/suzzme-screen-patterns/SKILL.md
check "Presence skill exists" test -f ../.agents/skills/suzzme-presence/SKILL.md
check "UI Validation skill exists" test -f ../.agents/skills/suzzme-ui-validation/SKILL.md

print "UI recovery checks passed: $passed"
print "UI recovery checks failed: $failed"
[[ $failed == 0 ]]
