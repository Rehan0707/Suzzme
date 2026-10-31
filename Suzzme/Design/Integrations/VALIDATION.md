# Integrations read-boundary validation

These runners use synthetic credentials and in-process fixtures, not a real account. Never paste a GitHub token into a command, chat, report or test file. Real-account acceptance uses Settings → Integrations after choosing a dedicated test repository.

From repository root:

```sh
zsh Suzzme/Validation/integration-safety-check.sh
zsh Suzzme/Validation/integration-core-check.sh
sh Suzzme/BrowserExtension/Tests/resource-check.sh
node Suzzme/BrowserExtension/Tests/protocol-check.mjs
SUZZME_MCP_PRODUCTS=/path/to/pinned-sdk-build-products zsh Suzzme/Validation/integration-mcp-check.sh
python3 Suzzme/Validation/integrations-regressions.py
```

The MCP runner links official Swift SDK 0.12.1 and its actual Logging/EventSource/System products. Build that pinned package with the installed Swift toolchain or use the application’s matching built products. Do not substitute a different SDK silently. Xcode compiler plugins may require normal host compiler permissions.

Evidence for this checkpoint: `Suzzme/Validation/Reports/2026-10-07-integrations/`. Regression logs use a new directory; prior acceptance reports/fixtures are not overwritten. Existing UI/environment assertions run in temporary isolated app copies with the resolved package cache; only the runner's package paths change, not assertions.

Real-account gate: connect through secure UI, verify actual account/scopes/tools/schema, read an explicitly allowed issue, inspect grounding/provenance, disconnect and prove authenticated reads stop. Browser acceptance additionally needs the signed native host and current resource/version delivery. Do not start external writes or claim account acceptance from these fixtures.
