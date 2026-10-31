#!/bin/zsh
set -eu
cd "${0:A:h}/.."
sdk_products=${SUZZME_MCP_PRODUCTS:?Set installed SDK products directory}
appauth_source=${SUZZME_APPAUTH_SOURCE:?Set installed AppAuthCore source directory}
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun clang -fobjc-arc -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
 -I "$appauth_source" -framework Foundation -framework Security \
 Validation/Step15OAuthChecks.m "$sdk_products/AppAuthCore.o" -o "$output/checks"
"$output/checks"
