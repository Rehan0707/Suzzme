#!/bin/zsh
set -eu
cd "${0:A:h}/../.."
node --experimental-strip-types Suzzme/Validation/CompanionPushChecks.ts
# Install @electric-sql/pglite into an isolated directory and set
# SUZZME_PGLITE_MODULE to its dist/index.js to run database/RLS checks.
if [[ -n "${SUZZME_PGLITE_MODULE:-}" ]]; then
  node Suzzme/Validation/CompanionDeliveryDatabaseChecks.mjs
fi
