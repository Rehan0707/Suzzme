# SUZZME — INTEGRATIONS + MCP IMPLEMENTATION REPORT

7 October 2026. **Read-software checkpoint; the full integrations scope is not accepted.**

## Executive Summary

Implemented native GitHub account configuration and an explicit-resource, read-only MCP route under the existing SuzzmeCore. Fixed account selection, cancellation, configuration, result ownership, repository-root arguments, ambiguous URLs, and UI health projection defects. No real GitHub account has been connected or tested. Browser extension source exists, but its signed native host and installation do not. External writes and custom MCP servers remain disabled.

## Existing Architecture Audit

Reused AppEnvironment composition, SuzzmeCore orchestration, ContextEngine, IntelligenceRouter/SuzzmeUnderstandingPipeline, AppleIntelligenceService, PrivacyEngine, SessionMemoryEngine, LongTermMemoryStore, existing action coordinators, VoiceSessionController, ScreenContextPolicy/MacScreenContextSource, and existing assistant/Presence ownership. No duplicate Core, Context, Memory, Action, Privacy, Voice, Screen, or Presence manager was created.

## Verified External Technology

- **MCP specification/version:** current 2026-07-28; the implemented adapter deliberately supports only legacy 2025-11-25. It is not a current-spec general-purpose MCP client.
- **MCP SDK/version:** official Swift SDK 0.12.1, commit `a0ae212ebf6eab5f754c3129608bc5557637e605`; exact Swift Logging 1.6.2. Consumer transitive versions are recorded in VERIFIED_TECHNOLOGY.md and Package.resolved.
- **GitHub MCP server/version/commit:** audited v2.0.0, `cb290407e20d9cc4a7c338179f4a30287f4e5040`. The hosted server deployment cannot be pinned to that public commit.
- **GitHub authentication options verified:** PAT bearer authentication; provider OAuth requires a registered app. This implementation uses a user-entered fine-grained PAT, not invented OAuth registration.
- **GitHub read-only behavior verified:** official source/documents define `X-MCP-Readonly` and explicit tool headers. Native allowlists also reject writes. Actual provider-side behavior remains account acceptance pending.
- **Browser Native Messaging requirements:** MV3 nativeMessaging permission, real allowed extension ID, separate executable host, registered manifest, bounded framed stdin/stdout, legitimate installation and signed app IPC. Source-only extension does not satisfy installation.
- **Apple APIs verified:** Security SecItem/data-protection Keychain, installed Swift 6/SwiftUI/Observation, public native IPC/signing and sandbox constraints. App Group/helper provisioning was not fabricated.
- **LinkedIn capabilities verified:** visible-content assistance is possible through existing authorized screen context. Generic feed/messages/profile access is not implemented or advertised as connected.

Primary references, pinned source APIs and compatibility decisions: [VERIFIED_TECHNOLOGY.md](VERIFIED_TECHNOLOGY.md).

## Architecture

Settings → IntegrationController → actor-isolated IntegrationGateway → verified account + repository scope → fixed-origin GitHub MCP client → ephemeral ContextEngine resource → existing read-only local answer path → current native presentation. Tokens never enter the reasoning layer. Resource text never enters item extraction, action planning, Session Memory facts, durable Memory, Information Store, or Daily Summary persistence.

Native Calendar/Reminder actions containing a GitHub URL continue through the existing confirmation pipeline. The integrations gateway itself has no write method.

## Integration Catalog

| Service | Status | Connector / authentication | Read capabilities actually implemented | Write capabilities | Future only |
| --- | --- | --- | --- | --- | --- |
| GitHub | Available, read only; account acceptance pending | Fixed official remote MCP + PAT/Keychain | Explicit allowed repository directory, issue, PR, commit-file reads | None | Browser-native delivery, approved issue creation, durable external-write receipts |
| LinkedIn | Visible-content help; no account access | Existing authorized Screen Awareness; no integration authentication | Bounded user-requested screen assistance | None | Any official authenticated capability requires separate registration/verification |
| Notion | Not configured | No live connector/authentication | None | None | Authorized pages and actions |
| Linear | Not configured | No live connector/authentication | None | None | Authorized issues and actions |
| Google Docs | Not configured | No live connector/authentication | None | None | Authorized documents and actions |
| Google Calendar | Existing native Calendar route | Existing EventKit authorization in Sources | Existing authorized Calendar context | Existing centrally confirmed EventKit capabilities, not MCP | A separate Google account connector is not implemented |

## Integrations UI

Observed on the running Mac app: Settings → Integrations, honest six-service catalog, GitHub detail, secure PAT field, explicit repository entry, disabled empty-form connection button, and Cancel returning with no account. A typed GitHub URL without an account returned “Connect and verify a GitHub account in Settings → Integrations first.” No authenticated retrieval was claimed. Native accessibility inspection and rendered screenshots were used during the session. These observations do not establish real-account access, VoiceOver acceptance, or physical Presence acceptance.

## Browser Extension

- **Permissions:** activeTab, scripting, nativeMessaging, storage; no host permission, history or cookie access; incognito disabled.
- **Pairing:** versioned challenge/proof/HMAC protocol source; no fake successful native pairing.
- **URL/title/selection:** explicit active-tab delivery, bounded fields, sensitive URL components removed, editable/password inputs excluded.
- **Native Messaging:** extension-side protocol exists; native host/registration/signing are not implemented.
- **Privacy:** no background all-tab capture or durable page-body storage. Native end-to-end enforcement awaits the host.

## Resource Recognition

- **Explicit:** strict parsed HTTPS GitHub resources; exact owner/repository, issue/PR number, and explicit commit-file references. Ambiguous branch/path boundaries are not guessed.
- **Browser:** freshness/version/conflict contract and extension source tested; no production browser intake until native host exists.
- **Screen:** existing explicit Screen Awareness remains separate; a screenshot does not authenticate a service.
- **Conflict handling:** multiple explicit URLs, lookalikes, encoded separators, traversal and contradictory resource candidates fail closed; no fallback from an invalid explicit target.
- **Stale handling:** request invocation owner, account generation, context ID, 30-second freshness, and pre/post-read validation. Default selection, configuration, cancellation and disconnect retire old reads.

## MCP

- **Transport:** ephemeral URLSession, fixed GitHub origin, no redirects/cookies/cache or automatic retries; bounded JSON/SSE.
- **Initialize:** actual pinned SDK legacy handshake, exact returned-version/tools-capability check.
- **tools/list/pagination:** maximum three pages, cycle/duplicate detection. Before/after discovery plus one read allow at most seven connector operations. Handshake and notification traffic are separate protocol frames.
- **Schema validation:** bounded supported schema vocabulary, required fields, native argument validation and schema digests; unsupported schema semantics fail closed.
- **Allowlist:** get_me, issue_read, pull_request_read, get_file_contents; native method/argument restrictions independent of annotations.
- **tools/call:** exactly one reviewed read per resource task; text-only bounded result, tool-error/secret rejection.
- **Tool changes:** notification invalidation and post-read rediscovery reject changed schemas; advertised notification monitoring must work.
- **Reconnect:** fresh session/discovery for each read; saved metadata alone is not Ready after restart.
- **Shutdown:** 30-second deadline; cancellation disconnects SDK/transport and retires current authority. No process helper exists.

## GitHub

- **Authentication/account:** REST `/user` binds verified durable account ID before MCP discovery and Keychain save. API version 2026-03-10. Multiple accounts require an explicit ready default; stale defaults never silently select another account.
- **Repository allowlist:** exact normalized owner/name matches, checked natively before dispatch; provider permissions remain decisive.
- **Discovered actual tool names:** none from a real account. SDK fixture discoveries are synthetic.
- **Reviewed read tools:** the four names above, verified against pinned official source. Repository root uses omitted optional path.
- **Read-only enforcement:** fixed headers, discovered-name/schema review, allowed native read methods, no external-write API exposed to Core/model/UI.

## GitHub Runtime Read

**Exact test:** typed `Summarize https://github.com/fixture-owner/fixture-repo/issues/1` without a connected account. **Actual resource/account:** none; this is a synthetic target, not a provider fixture. **Result:** truthful connection-required recovery. **PASS/FAIL:** unauthorized-read prevention PASS; real authorized GitHub read NOT RUN / acceptance pending.

## Write Safety

**Implemented capability:** no GitHub write. **Approval/digest/expiry:** existing native Step 8 unchanged; external approval not implemented. **Ledger/unknown state/reconciliation:** external durable execution extension remains unimplemented. **Duplicate prevention:** external writes cannot dispatch; actual remote duplicate/restart reconciliation is untested. These absences block full-scope acceptance. M6 is gated on accepted real M5 reads; no fake write receipts or save-without-verification success were added.

## Write Runtime Test

**Cancel / approve / timeout / duplicate count:** NOT RUN. No external issue was created, changed, or deleted. Zero writes performed is not evidence that a working external-write system is accepted.

## Prompt Injection

**Tests:** hostile issue text through actual Core; no extracted items/action/native mutation/Memory/Session facts; write tool/method rejected before connection; changed/unsupported discovery and secret-bearing responses rejected. **Results:** code boundaries pass. Real hosted malicious-content acceptance remains pending. Model outputs have no connector, account or approval authority.

## Custom Connectors

**Implemented:** disabled. **Trust UX:** catalog explains unavailable capabilities; no fake connection. **Remote protections:** fixed official origin only; arbitrary server DNS/SSRF/OAuth policy is not implemented. **Local stdio:** no arbitrary command execution or automatic MCP installation. Modern general-purpose compatibility needs a separate verified decision.

## Storage

**SQLite/SwiftData responsibilities:** existing product stores preserved. IntegrationStore is a separate bounded versioned non-secret account metadata file using existing recoverable-file utilities. **Keychain:** tokens only, device-local, non-synchronizing data-protection items. Real signed-account save/load acceptance remains pending. **Retention:** tool/page bodies have request lifetime; local disconnect disables authority before credential removal, and failed removal leaves Disabled across restart. PAT provider revocation is explicitly separate. **Private Mode:** no new global Private Mode toggle; integration content is ephemeral on every read. No claim of an unimplemented mode.

## IPC

**Transport/authentication/versioning/frame limits:** browser protocol source tests enforce bounded versioned challenge/context contracts; no native host/XPC end-to-end implementation. **Approval authority:** native only; browser cannot approve writes. **Crash recovery:** source contract invalidates leases; installed helper crash/restart acceptance not performed.

## Privacy

**Screenshots:** existing explicitly authorized capture unchanged. **Browser:** opt-in source only, not installed. **Cloud processing:** no external AI API; authenticated GitHub connectivity is opt-in network access. **Tool results:** bounded transient untrusted data, processed through existing local intelligence. **Credentials:** Keychain/client boundary only. **Logs:** fixed native recovery messages, no raw upstream response/credential diagnostics. Test fixtures contain synthetic strings only.

## Performance

**Hardware:** observed identifier Mac14,2; 8 GiB RAM. **Idle CPU / active CPU / app memory / helper memory:** not measured; no helper exists. **Capture behavior:** no new polling screen capture. **Methodology:** regression harness timing is recorded separately and does not count as distributed-app profiling. No performance numbers or physical acceptance inferred from fixtures.

## Packaging

**Helper/runtime:** no installed native browser helper or Node runtime. **Dependencies:** exact official native MCP and Logging products; consumer lockfile retained; existing Google authentication packages preserved. **Signing:** Mac Debug ad-hoc build; iOS Simulator unsigned build. **Notarization:** not performed. **Native Messaging:** production registration/App Group/signed IPC pending. **Clean machine:** not tested; release signing and third-party notices remain release gates.

## Tests

Integration assertions: account/storage/race/UI projection 132; pinned MCP SDK behavior 28; actual Core isolation 18; resource recognition 60; browser protocol 58. All completed without real account/network acceptance. They establish exact scope, deterministic account choice, cancellation/replacement, disabled failed-deletion recovery, bounded discovery, safe protocol failure, transient reasoning, and separation of external data from native actions/Memory.

Existing regression suites: main 28, shortcut/Space 2, UI behavior and AppEnvironment 2. Locked floors preserved: Step 6 53/53, Step 7 90/90, Step 8 198/198, Step 9 156/156, Step 10 190/190, UI Recovery 46/46. Step 11 223/223, Step 12 410/410, recovery 164/164; all suite details/logs remain in `Validation/Reports/2026-10-07-integrations`. UI behavior 53/53 and AppEnvironment 35/35 passed again after the final projection wiring. New integration checks total 296 passed / 0 failed.

**iOS build:** PASS (Simulator). **macOS build:** PASS (Debug ad-hoc). Final incremental builds introduce no warnings; exact commands/logs are retained in the validation evidence. Swift 6 actor checks enabled; no unchecked Sendable or warning-suppression change added to production code.

## Runtime Acceptance

**GitHub read/disconnect:** real account pending; no-account denial observed. **Write confirmation/unknown write:** unimplemented and untested. **Injection/account ambiguity/stale context:** synthetic software checks pass; real account/browser acceptance pending. **Mac UI:** catalog, secure form/cancel and unauthorized question recovery observed. **iPhone:** shared code builds; no physical integration acceptance claimed.

## Files Added

- `Suzzme/Core/Integrations/`: IntegrationModels, IntegrationStore, IntegrationCredentials, IntegrationResource, IntegrationHTTPTransport, GitHubMCPClient, GitHubIntegrationClient, IntegrationGateway, IntegrationController.
- `Suzzme/Features/Settings/IntegrationsView.swift`.
- `BrowserExtension/`: MV3 manifest, popup, service worker, protocol/schema, README and two validation programs.
- `Design/Integrations/`: architecture, primary technology verification and this report.
- `Validation/`: IntegrationSafetyChecks, IntegrationMCPChecks, IntegrationCoreChecks, their three runners, and integrations-regressions.py.

## Files Modified

Narrow integration extensions in AppEnvironment, SettingsView, SuzzmeContextItem, ContextEngine, IntelligenceRouter, SuzzmeCore, Xcode project and consumer Package.resolved. Other pre-existing dirty files were preserved; they are not attributed to this pass. No original regression assertions weakened or deleted.

## Existing Systems Preserved

Native action confirmation/execution/verification, EventKit authority, source health, proactive orchestration, durable personal Memory, VoiceSessionController, screen permissions/capture, assistant state, Mac Presence and iPhone system-presence boundaries. Hardware acceptance statuses remain pending wherever previously pending.

## Remaining Issues

**P0:** full external-write execution safety is not implemented or accepted; it remains disabled. Real M5 read acceptance is required before M6 can start.

**P1:** signed browser-native host, authenticated installed IPC, extension ID/registration, real account identity/permissions/discovery/read/disconnect/injection tests, Keychain signing acceptance, custom-connector trust/current-protocol compatibility and service-specific implementations remain pending. A browser page does not yet supply production connector context. There is no new global Private Mode toggle.

**P2:** release notices/signing/notarization/clean-machine validation, measured idle/active performance, physical iPhone accessibility/presentation and physical Mac Presence/voice acceptance are pending.

## PHYSICAL / ACCOUNT ACCEPTANCE

**SOFTWARE VERIFIED:** native read boundary, synthetic SDK/Core/account/browser contracts, existing regressions and platform builds per validation manifest.

**REAL ACCOUNT VERIFIED:** none. No existing browser/CLI credentials reused; no real external mutations performed.

**PHYSICAL MAC VERIFIED:** only the listed native UI reachability and no-account recovery observations. No claim of notch/voice/install/release acceptance.

**PENDING:** dedicated GitHub test account/repository connection via Suzzme’s secure UI; live capabilities/read/disconnect and injection acceptance; signed browser host; gated external-write implementation and runtime acceptance; distributed and physical testing.

SUZZME INTEGRATIONS NOT ACCEPTED —
SECURITY OR EXECUTION BLOCKERS REMAIN
