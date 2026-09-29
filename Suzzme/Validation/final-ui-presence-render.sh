#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -framework AppKit -framework SwiftUI -framework Carbon \
 Suzzme/Core/Models/SuzzmeAssistantState.swift \
 Suzzme/Core/Invocation/AssistantPresentation.swift \
 Suzzme/Core/Invocation/SuzzmePresenceTheme.swift \
 Suzzme/DesignSystem/Theme/SuzzmeTheme.swift \
 Suzzme/DesignSystem/Components/SuzzmeFace.swift \
 Suzzme/DesignSystem/Components/SuzzmeAssistantPresenceView.swift \
 Suzzme/Platform/macOS/MacAssistantPresence.swift \
 Validation/FinalUIPresenceRender.swift -o "$output/PresenceChecks"
"$output/PresenceChecks" "Validation/Reports/FinalUI/PresencePreviews"
