#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path "$output/module-cache" \
 Suzzme/Core/Integrations/IntegrationModels.swift Suzzme/Core/Integrations/IntegrationResource.swift \
 Suzzme/Core/Integrations/ProviderReadRecipe.swift Suzzme/Core/Integrations/GoogleProviderRecipes.swift \
 Suzzme/Core/Integrations/ProviderReadClient.swift Validation/ProviderReadChecks.swift -o "$output/checks"
"$output/checks"
