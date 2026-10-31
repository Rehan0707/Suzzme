#!/bin/zsh
set -eu
cd "${0:A:h}/.."
# Build the exact official SDK first; no network or account is used by the checks.
sdk_products=${SUZZME_MCP_PRODUCTS:?Set SUZZME_MCP_PRODUCTS to the pinned SDK build products directory}
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path "$output/module-cache" -I "$sdk_products" \
 "$sdk_products/MCP.o" "$sdk_products/Logging.o" "$sdk_products/EventSource.o" "$sdk_products/SystemPackage.o" "$sdk_products/CSystem.o" \
 Suzzme/Core/Integrations/GitHubMCPClient.swift Suzzme/Core/Integrations/IntegrationHTTPTransport.swift Suzzme/Core/Integrations/IntegrationTransportSecurity.swift \
 Validation/IntegrationMCPChecks.swift -o "$output/checks"
"$output/checks"
