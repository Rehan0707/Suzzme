#!/bin/zsh
set -eu
cd "${0:A:h}/.."
sdk_products=${SUZZME_MCP_PRODUCTS:?Set SDK products directory}
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -I "$sdk_products" "$sdk_products/MCP.o" "$sdk_products/Logging.o" "$sdk_products/EventSource.o" "$sdk_products/SystemPackage.o" "$sdk_products/CSystem.o" -swift-version 6 -parse-as-library -module-cache-path "$output/module-cache" \
 Suzzme/Core/Integrations/IntegrationModels.swift Suzzme/Core/Integrations/CustomMCPModels.swift Suzzme/Core/Integrations/ProviderReadRecipe.swift Suzzme/Core/Integrations/GoogleProviderRecipes.swift Suzzme/Core/Integrations/GoogleProviderScopeStore.swift Suzzme/Core/Integrations/ProviderReadClient.swift Suzzme/Core/Integrations/IntegrationTransportSecurity.swift Suzzme/Core/Integrations/LinearIntegrationClient.swift Suzzme/Core/Integrations/IntegrationResource.swift \
 Suzzme/Core/Integrations/IntegrationStore.swift Suzzme/Core/Integrations/IntegrationCredentials.swift \
 Suzzme/Core/Integrations/IntegrationGateway.swift Suzzme/Core/Persistence/RecoverableJSONFile.swift \
 Suzzme/Core/Integrations/NotionIntegrationClient.swift \
 Suzzme/Core/Integrations/IntegrationController.swift Suzzme/Core/Integrations/IntegrationConnectionSuggestion.swift \
 Suzzme/Core/Context/SuzzmeContextItem.swift Suzzme/Core/Context/SuzzmeContextQuery.swift \
 Suzzme/Core/Privacy/PrivacyEngine.swift Suzzme/Core/Models/SuzzmeItem.swift \
 Suzzme/Core/Integrations/CustomMCPClient.swift Suzzme/Core/Integrations/PinnedMCPHTTPClient.swift Validation/Step15MCPChecks.swift -o "$output/checks"
"$output/checks"
