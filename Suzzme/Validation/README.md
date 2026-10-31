# Validation guide

Run commands from `Suzzme/`, the directory containing `Suzzme.xcodeproj`. Shell checks use `zsh`; Python tools use Python 3; browser and connector checks use Node 24. Swift checks use the selected Xcode toolchain.

## Quick checks

```sh
zsh Validation/check.sh
zsh Validation/persistence-check.sh
zsh Validation/ui-recovery-check.sh
node BrowserExtension/Tests/protocol-check.mjs
node BrowserExtension/Tests/github-connection-check.mjs
sh BrowserExtension/Tests/resource-check.sh
(cd ConnectorServer && npm test)
```

`check.sh` covers local extraction and assistant state. `persistence-check.sh` covers the saved-item store. `ui-recovery-check.sh` checks source-level UI contracts; it does not launch the app or establish visual or accessibility acceptance.

## Choose checks by area

| Area | Entry points |
| --- | --- |
| Context, privacy, memory and actions | `step3-check.sh` through `step9-check.sh`, `product-flow-check.sh`, `p0-blocker-check.sh` |
| Information and proactive intelligence | `step10-check.sh`, `step11-check.sh`, `step17-summary-follow-up-check.sh`, `step21-intelligence-check.sh` |
| Recovery and release hardening | `step12-check.sh`, `step12-recovery-check.sh`, `backend-reliability-check.py`, `background-cleanup-check.py` |
| Mac scheduled preparation | `scheduled-briefing-check.sh`, `scheduled-briefing-environment-check.py`, `scheduled-briefing-lifecycle-check.sh` |
| Mac Launch at Login | `launch-at-login-check.sh`, `launch-at-login-preview.sh` (fake Service Management state and inactive native Settings renders); `launch-at-login-device-check.py` (read-only installed-app, process and receipt probe after real sign-in) |
| Mac Background Tasks screen | `background-tasks-check.sh`, `background-tasks-preview.py` (production view and scheduler with isolated synthetic data; no live sources or permissions) |
| Mac background activity in Presence/menu | `background-presence-check.sh`, `background-presence-preview.py` (real scheduler/panel checks and exact component renders; synthetic data and isolated fixtures) |
| Watched links | `watched-url-policy-check.sh`, `watched-extraction-check.sh`, `watched-transport-check.sh`, `watched-dns-resolver-check.sh`, `watched-pinned-connection-check.sh` |
| Integrations and selected resources | `integration-core-check.sh`, `integration-mcp-check.sh`, `integration-safety-check.sh`, `provider-read-check.sh`, `notion-client-check.sh`, `notion-core-check.sh`, `notion-gateway-check.sh`, `step15-google-check.sh`, `composio-client-check.sh` |
| Browser bridge | `browser-bridge-check.sh`, `browser-github-handoff-check.sh`, `browser-github-controller-check.sh`, plus `BrowserExtension/Tests/` |
| Voice and global invocation | `voice-quality-check.sh`, `voice-lifecycle-acceptance-check.sh`, `global-voice-check.sh`, `global-shortcut-check.sh`, `global-shortcut-monitor-check.py`, `screen-privacy-check.py` |
| Mac screen-label guidance | `clicky-screen-guidance-check.sh`, `global-screen-check.sh`, `clicky-ocr-fixture-check.py` (real local Vision on synthetic images; no screen capture or TCC prompts) |
| Presence and Live Activities | `companion-presence-check.sh`, `premium-presence-check.sh`, `step12-presence-check.sh`, `live-activity-check.sh` |
| Mac point-and-return companion | `point-return-check.py`, `clicky-companion-check.py`, `companion-space-check.py`, `point-return-preview.py` (synthetic content; no live capture or permission prompts) |
| Local knowledge and shared context | `local-knowledge-check.sh`, `shared-app-context-check.sh`, `shared-web-handoff-check.sh` |
| Native app behavior | `final-ui-check.py`, `final-ui-ios-runtime.py`, `final-ui-mac-runtime.py`, `native-platform-runtime.py`, `NativePlatformUnitTests/`, `NativePlatformUITests/` |

The numbered scripts retain their original names because later checks reuse their dependency lists. Their companion `*Checks.swift` files are executable validation harnesses, not unused app sources. Native runtime tools may launch the app, use a simulator or require platform permissions; read the relevant tool before running it.

## Full regression runners

```sh
python3 Validation/run-remediation-regressions.py
python3 Validation/run-final-ui-regressions.py
```

These run the established baseline suites and write logs plus `regressions.json` beneath `Reports/Step12Remediation/` or `Reports/FinalUI/`. They are separate from the four Debug/Release iOS/macOS builds documented in the [app README](../README.md).

`historical-store-check.py` and `final-ui-historical-check.py` regenerate historical fixtures and evidence. Run them only when intentionally updating migration fixtures. `step12-web-probe.sh` is an optional network probe. Watched transport checks may resolve packages and start local TLS fixtures; they are not part of the quick checks above.

## Source, fixtures and generated output

- Keep `Fixtures/`, test sources, package lockfiles and third-party license/provenance files. Historical `.store` files are migration inputs.
- Keep the readable reports, logs and visual evidence referenced by release and design documents. Old results describe their recorded source revision; they do not prove current acceptance.
- Compiler caches, indexes, build intermediates, Python bytecode, abandoned `.preparing-*.app` bundles and connector deployment exports are generated output. They can be recreated and do not belong in version control.
- Some focused integration checks accept `SUZZME_MCP_PRODUCTS` pointing to compiled SDK products. Preserve any product directory in active use, or rebuild it before running those checks. Package checkouts can also be needed for offline validation.
- Use `/tmp/SuzzmeDerivedData` or Xcode's default DerivedData location for new builds, outside source and evidence folders. `Reports/` is ignored by Git; do not use it as a home for production source or secrets.

Physical-device, accessibility, provider authorization and distribution acceptance remain separate gates in [LAUNCH_READINESS.md](../LAUNCH_READINESS.md).
