#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -framework SwiftData \
 Suzzme/Core/Models/SuzzmeItem.swift \
 Suzzme/Core/Context/SuzzmeContextItem.swift \
 Suzzme/Core/Context/SuzzmeContextQuery.swift \
 Suzzme/Core/Privacy/PrivacyEngine.swift \
 Suzzme/Core/Information/InformationModels.swift \
 Suzzme/Core/Information/InformationStore.swift \
 Suzzme/Core/Information/InformationEngine.swift \
 Suzzme/Core/Information/UserSelectedMessageSource.swift \
 Suzzme/Core/Information/GmailSelection.swift Suzzme/Core/Information/GmailAccessGrant.swift \
 Suzzme/Core/Information/GmailMessageMetadata.swift \
 Suzzme/Core/Information/GmailInformationSource.swift \
 Validation/ConnectorAcceptanceChecks.swift -o "$output/ConnectorChecks"
"$output/ConnectorChecks"
