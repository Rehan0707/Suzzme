#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_suzzme=$(CDPATH= cd -- "$task_root/.." && pwd)
task_scratch=$(mktemp -d "${TMPDIR:-/tmp}/suzzme-resource-check.XXXXXX")
trap 'rm -rf "$task_scratch"' EXIT HUP INT TERM
xcrun swiftc -swift-version 6 -module-cache-path "$task_scratch/module-cache" \
  "$task_suzzme/Suzzme/Core/Integrations/IntegrationModels.swift" \
  "$task_suzzme/Suzzme/Core/Integrations/ProviderReadRecipe.swift" \
  "$task_suzzme/Suzzme/Core/Integrations/GoogleProviderRecipes.swift" \
  "$task_suzzme/Suzzme/Core/Integrations/IntegrationResource.swift" \
  "$task_root/Tests/IntegrationResourceChecks.swift" \
  -o "$task_scratch/resource-check"
"$task_scratch/resource-check"
