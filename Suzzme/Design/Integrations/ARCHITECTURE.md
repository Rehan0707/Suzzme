# Suzzme integrations: architecture freeze

Date: 7 October 2026. Scope: macOS first, existing Suzzme application.

This document records the M0 ownership audit, the implementation boundary for the first authorized GitHub reads, and the gates on subsequent milestones. It is a design record, not evidence of account or physical Mac acceptance. Repository validation, real account validation, and distributed-app validation must be reported separately.

## Frozen product boundaries

Recognition, authentication, and execution are separate facts:

1. A parsed GitHub URL or screen inference identifies a possible resource. It grants no account access.
2. An explicitly connected account grants only its verified scopes and reviewed capabilities. The presence of a credential does not prove a working connection.
3. A permitted read requires the chosen account, repository policy, reviewed capability, current resource binding, and active request.
4. A proposed write requires deterministic Action Policy, the native confirmation path, an immutable approval, dispatch, and verification. A model proposal never grants approval.

SuzzmeCore remains the orchestrator. Foundation Models remains the primary existing on-device reasoning path. MCP supplies connectivity and reviewed tool transport. MCP servers, browser pages, issue bodies, tool descriptions, results, and errors are untrusted data.

The initial implementation adds no second Core, Context Engine, Memory, Action Engine, Privacy Engine, voice engine, screen capture manager, assistant state owner, or Presence owner.

## Existing ownership map

Paths below are relative to `Suzzme/Suzzme` from the repository root. Locations describe the audited pre-integration implementation; subsequent changes may move line numbers.

| Responsibility | Existing owner | Integration extension |
| --- | --- | --- |
| Composition and presentation ownership | `App/AppEnvironment.swift`; Core construction in its initializer | Compose the native account/gateway dependencies once. Keep request IDs, active UI ownership, native consent, and confirmation forwarding here. |
| Orchestration | `Core/Intelligence/SuzzmeCore.swift` | Add a narrow ephemeral resource read route and cancellation forwarding. Keep planning, source selection, memory permission, progress, and final response under this Core. |
| Authorized context | `Core/Context/ContextEngine.swift`, `ContextSource` in `SuzzmeContextItem.swift` | Reuse collection, privacy normalization, and source-health principles. Browser/tool results need explicit ephemeral handling. |
| Screen context | `Core/Context/ScreenContext.swift`, `ScreenContextPolicy.swift`, `Platform/macOS/MacScreenContextSource.swift` | Keep on-demand capture, local privacy preflight, single capture ownership, and geometry validation. Add exclusions in the existing capture filter if required. |
| Reasoning | `Core/Intelligence/IntelligenceRouter.swift`, `SuzzmeUnderstandingPipeline.swift`, `AppleIntelligenceService.swift` | Feed bounded resource facts to the existing read-only question path, labelled as untrusted. Never expose credentials or raw transport authority to the model. |
| Session memory | `Core/Memory/SessionMemoryEngine.swift` | Preserve current session ownership. Initial raw browser/tool data is task-scoped and does not enter actionable session facts. |
| Durable personal memory | `Core/LongTermMemory/LongTermMemoryStore.swift` | Keep explicit memory commands and request capability ownership. Connecting/disconnecting an integration does not authorize memory mutation. |
| Daily Context and relevance | `Core/Proactive/ProactiveIntelligenceEngine.swift`, `ProactiveIntelligenceStore.swift` | Preserve the existing source-health and relevance pipeline. Do not insert raw MCP results into Daily Context. |
| Persistent information intake | `Core/Information/InformationEngine.swift`, `InformationStore.swift` | Reuse only for separately authorized retained information, not ordinary task-scoped connector responses. |
| Native Calendar/Reminders/Contacts | `Core/Connectors/AppleContextSources.swift`, `AppleContextPermissions.swift` | Preserve EventKit and native permission ownership. Google Calendar catalog presence does not replace native Calendar access. |
| Gmail authorization | `Core/Information/GmailAccountController.swift`, `GmailAccessGrant.swift`, `GmailInformationSource.swift` | Preserve GoogleSignIn ownership and generation validation. Future Google capabilities must extend that owner rather than start another Google OAuth stack. |
| Watched Links | `Core/Information/WatchedLinks/WatchedLinkStore.swift`, existing URL/fetch policies | Preserve explicit watched-link scope and persistent-source semantics. Browsing context is a different ephemeral domain. |
| Structured write plan | `Core/Actions/CapabilityActionModels.swift` | Future GitHub issue creation extends the typed capability/payload/plan, including explicit account, destination, arguments, and context binding. |
| Deterministic write policy | `Core/Actions/ActionPolicy.swift` | Extend per-capability rules for the one reviewed future write. Do not replace policy with MCP annotations or model risk estimates. |
| Capability dispatch | `SuzzmeCapability` and `SuzzmeCapabilityRegistry` in `Core/Actions/EventKitCapabilities.swift` | Register a deliberate integration capability; retain the registry boundary. Do not create a model-addressable arbitrary tool executor. |
| Confirmation and final dispatch authority | `Core/Actions/ActionExecutionCoordinator.swift` | Extend this coordinator with proposal digest and a durable non-secret external execution ledger. Keep native confirmation and single-use authorization here. |
| Existing action verification | `Core/Actions/ActionMutation.swift` and capability evidence | Preserve verified EventKit behavior. Remote capabilities need truthful verification/unknown outcome handling under the same coordinator. |
| Action review presentation | `AppEnvironment.respondToPresentedAction`, `Features/Home/AskSuzzmeView.swift`, `SuzzmePresenceReview` | Display the complete resolved proposal through the existing confirmation projection and forwarding path. UI state is not an approval token. |
| Voice and assistant state | `VoiceSessionController`, `AssistantStateController`, `InvocationCoordinator` | Connector tasks publish existing concise progress states. They do not own voice, transcripts, or another assistant lifecycle. |
| Mac invocation/Presence/guidance | `MacGlobalInvocationController`, `MacAssistantPresence`, `MacGuidanceOverlay` | Preserve current owners, display geometry, and interaction identity. Integrations do not redesign these surfaces. |

### Audit implications

The existing normal context path remembers gathered items in SessionMemory. Context items without an expiration can survive until explicit clearing; the session's turn lifetime does not itself expire every context item. Registering a browser page or tool response as an ordinary source would change retention and action-reference semantics. The first GitHub route therefore keeps raw results in the current request and returns only bounded read-only answers and safe provenance.

The existing screen branch returns before action planning, durable memory authorization, ordinary context retention, and information/Daily Context intake. `MacScreenContextSource.fetchContext` returns no ordinary context items. Preserve this isolation. A screen-derived GitHub hint is uncertain recognition, not authorization or a confirmed target.

The existing question model session has no tools and labels context/conversation/screen understanding as untrusted. Keep that read-only session for initial GitHub summaries. Connector content cannot be passed to the action planner as if it were a user utterance.

## Native connectivity decision

Use the maintained native Swift MCP client for the fixed reviewed GitHub remote endpoint `https://api.githubcopilot.com/mcp`, with an explicitly pinned dependency and negotiated protocol version. A TypeScript helper is not required for this first bounded native read path. The distributed app must not require Homebrew, user-installed Node, `npm`, `npx`, shell startup files, or the user's PATH.

The chosen native SDK's legacy protocol baseline is `2025-11-25`. The current modern specification reference is `2026-07-28`. These are different protocol generations: negotiating the supported legacy version is not a claim of modern-spec support. Unsupported or incompatible negotiations fail closed.

| Reviewed dependency | Frozen release/revision | Evidence boundary |
| --- | --- | --- |
| MCP Swift SDK | `0.12.1`, `a0ae212ebf6eab5f754c3129608bc5557637e605` | Native supported legacy client; negotiated version must still be checked at runtime. |
| Official GitHub MCP server | `v2.0.0`, `cb290407e20d9cc4a7c338179f4a30287f4e5040` | Reviewed source reference; the hosted endpoint's actual discovered server/tool schemas must still be checked at runtime. |

Initial source-reviewed read names are `get_me`, `issue_read` with `get`/`get_comments`, `pull_request_read` with `get`/`get_files`, and `get_file_contents`. This is a reviewed list, not a claim of successful runtime discovery. Allow only the capabilities actually implemented, requested, and present with matching reviewed schemas; disable any other method or tool.

Primary verification references:

- [MCP specification](https://modelcontextprotocol.io/specification/2026-07-28)
- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
- [Official GitHub MCP server](https://github.com/github/github-mcp-server)
- [Chrome Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)
- [Chrome activeTab](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab)
- [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
- [Apple Keychain Services](https://developer.apple.com/documentation/security/keychain-services)

Release-specific pins and observed behavior belong in the implementation verification report; these links alone are not runtime evidence.

## Initial integration domain and catalog

Integration identity and an Information Source are related but have different semantics. A connector may support an ephemeral read or future mutation without being a retained information feed.

Use typed descriptors, effects, capabilities, connector identity/transport, connection states, connected accounts, reviewed tools, resolved resources, errors, and receipts. Secrets stay outside Codable domain snapshots, SwiftData, UserDefaults, conversation, Memory, and logs.

| Catalog entry | Initial truthful capability |
| --- | --- |
| GitHub | First implemented account-scoped, repository-allowlisted, reviewed read path. Write production gate closed. |
| LinkedIn | Visible-content assistance/drafting only. No authenticated account action without separately verified supported API access. |
| Notion | Catalog-ready; connector not configured until API/connector verification and implementation. |
| Linear | Catalog-ready; connector not configured until API/connector verification and implementation. |
| Google Docs | Catalog-ready; future implementation must reuse the existing Google authorization owner where applicable. |
| Google Calendar | Explain existing native Calendar context. Do not imply that a remote Google account is connected. |

Connection transitions are explicit: unconfigured → authorizing → connecting → ready, with authExpired, unavailable, and disabled exceptional states. Account identity and granted capability must be checked before ready. A Keychain item alone cannot produce ready.

Multiple accounts are represented from the start. Repository policy belongs to a selected account. An organization appearing in a URL cannot silently select an executing account. A read response identifies which authorized account supplied the result. Consequential account ambiguity requires explicit selection.

## Authorized read lifecycle

1. The user supplies an explicit resource target or consents to task-scoped browser context. Recognition parses the exact HTTPS origin and GitHub resource shape.
2. SuzzmeCore resolves target conflicts, selected account, current context binding, repository allowlist, and reviewed read capability.
3. The native gateway validates account generation and request ownership before acquiring the ephemeral credential and before each connector dispatch.
4. The MCP client initializes the fixed endpoint with read-only mode and individually selected tools, checks the negotiated protocol, discovers bounded/paginated tools, validates reviewed schemas, and allows only known read capabilities. Rediscover and compare schema digests for each read. If tool-change support is advertised, a bounded notification monitor is required; absence or failure must disable the read rather than leave stale tool authority active.
5. Request budgets limit calls, pagination, duration, and output size. Tool descriptions/annotations cannot expand the native allowlist.
6. The gateway checks cancellation, account generation, resource version, and schema identity again after every suspension and rejects stale results.
7. ContextEngine applies the existing PrivacyEngine to bounded returned content. External data remains untrusted; rejected secret-bearing content is not retained or sent to the model.
8. The existing IntelligenceRouter/pipeline answers using bounded facts. The response states authenticated retrieval provenance separately from visible-page recognition.
9. Task-scoped raw results are discarded. Disconnect/permission changes prevent subsequent retrieval and invalidate outstanding tasks.

Do not silently fall back to a different account, connector, model provider, browser automation, or write-capable tool. A disconnected account cannot be replaced by screenshot recognition while claiming an authenticated read.

## Resource and context ownership

Recognition precedence is explicit target, fresh browser URL, other structured context, then visual inference. Consequential conflicts are errors requiring clarification.

URLs use parsed host/origin and strict resource validation. `github.com.attacker.example`, lookalike hosts, userinfo, unsupported ports, dangerous schemes, encoded path separators, and ambiguous resource paths must not resolve as a permitted GitHub resource. Canonical resource fields are typed; arbitrary URLs never become transport destinations or credential targets.

Browser context is task-scoped and contains a context ID, monotonic version, timestamp, paired browser/tab identity, exact URL, title, and optionally bounded requested selection/page context. It does not collect history, all tabs continuously, cookies, session tokens, passwords, or unrequested content.

A native browser context snapshot owner replaces or invalidates its version on navigation, resource replacement, pairing loss, task cancellation, or disconnect. Resource reads bind to this snapshot. Future proposals and approvals bind to the same context identity/version; a destination change requires resolution and a new approval.

Screen freshness currently validates request identity, capture time, PID, front-window identity/bounds, and display geometry/layout. It does not prove that a browser stayed on the same issue inside that window. Browser navigation needs its own version binding; screen geometry validation cannot substitute for it.

## Screen privacy

Continue single-request ScreenCaptureKit capture and local Vision/Foundation Models handling. No continuous recording or cloud vision route is introduced.

The audited capture filter excludes Suzzme's own windows, including its same-process overlay. It does not yet implement arbitrary configured private-app/window exclusions. A full-display OCR secret check is useful but is not equivalent to excluding sensitive neighboring windows. Extend the existing source's filter and existing privacy owner before claiming those exclusions are supported.

All visible content needs privacy filtering. Being focused on GitHub does not make another visible banking, health, password-manager, or messaging window safe. Captures remain ephemeral and do not enter memory, history, or connector payloads. Any future cloud vision change requires truthful explicit disclosure and separately approved privacy architecture.

## Browser bridge and IPC gate

The Chrome extension may use explicit `activeTab` interaction and Native Messaging. Safari support is not implied. Extension ID allowlisting, native-host identity/path installation, pairing, signed executable packaging, direction checks, and the native app delivery channel must all be verified on the actual Mac.

Native Messaging alone authenticates neither the connected account nor the user's write approval. Treat browser input as untrusted data. The native host must not accept arbitrary local process output as paired browser context.

The signed native host/App Group or equivalent authenticated local IPC delivery and installer lifecycle are pending. Do not present a mock bridge, file drop, or inactive host as working browser connectivity. Pairing requires explicit native consent, a Keychain secret, per-launch session authentication, request/task IDs, protocol version, bounded frames, schemas, direction validation, and safe failure on mismatch. Runtime directories/socket permissions must be private where applicable.

Only the native application grants approval. An inbound helper/browser message cannot manufacture an `approval.grant`, choose a different account, mutate a pending proposal, or call the action coordinator's confirmation path.

M2/M3 acceptance remains pending until installation, signing, pairing, cancellation, navigation versions, upgrade/uninstall behavior, and actual browser delivery are observed. The initial explicit-target GitHub path can operate independently of this pending browser milestone, with that limitation visible.

## Future writes: production gate closed

M6 remains disabled until real GitHub read-only runtime acceptance has passed. The first write is GitHub issue creation only, in an explicitly authorized dedicated test repository/account. No comments, merge, delete, workflow dispatch, release, or arbitrary file write capability is enabled by this design freeze.

Extend the existing SuzzmeActionExecutionCoordinator rather than adding a second confirmation/execution system:

- Freeze a typed resolved proposal with connector identity, account identity, reviewed tool/schema, canonical repository, complete title/body/labels, attachment hashes if supported, context identity/version, nonce, expiration, and digest.
- Hash canonical arguments and all authority-relevant fields after resolution. Any account/content/destination/label/attachment/schema/context change invalidates the grant.
- Display the complete final proposal through the native review UI and forward approval through the existing action ID/request ID ownership checks.
- Use an explicit single-use approval, with a provisional two-minute expiry. Unused approvals do not survive restart.
- Revalidate policy, account generation, repository authorization, resource version, schema digest, argument digest, approval, cancellation, and ownership at the final dispatch boundary.

### Existing execution limits and durable extension

The audited coordinator's executed IDs, pending plan, commit consumption, and evidence are in-memory. Its five-minute age check and equality guard establish bounded process-local callback protection for existing capabilities. They do not provide durable exactly-once external execution.

The coordinator currently checks active request ownership after capability execution before recording evidence. A remote write can have completed before local cancellation. Future remote execution must persist its outcome independently of stale UI ownership rather than discarding that fact or implying the side effect was undone.

Add a non-secret durable execution ledger dependency under this same coordinator. States are pending, running, succeeded, failed, cancelled, and unknown. Persist the execution identity/dispatch intent before the mutation leaves the process; consume the grant once; record provider response/verification even if the UI task was retired. Restart converts unreconciled running writes to unknown.

Timeout or cancellation after possible dispatch is unknown, not proof of failure. Reconciliation performs a reviewed read and verifies the provider result where possible. Never blindly resend a consequential write. Provider idempotency is used only if officially documented and verified. Local cancellation cannot undo a completed external issue creation.

The current implementation must not claim durable write safety, issue-creation availability, or write runtime acceptance before this extension and dedicated-account acceptance are complete.

## Cancellation and account generations

AppEnvironment retires presentation ownership synchronously before actor hops. SuzzmeCore rejects late continuations through its active request ID and cancels action/settings/memory capabilities. MacScreenContextSource independently owns capture/OCR cancellation. Extend the same Core cancellation method to native integration reads and ephemeral resource context.

Account disconnect rotates the selected account generation first, invalidates matching tasks/proposals/grants, attempts supported provider revocation, removes that account's Keychain credentials, and updates its connection state. Historical non-secret receipts follow explicit retention policy; personal Memory is not erased.

Gmail's existing ephemeral grants and generation validation before/after network requests provide the precedent. A token refresh, account switch, revoked permission, schema change, or failed recheck cannot silently restore old task authority.

## Threat model and deterministic controls

| Threat | Required control | Acceptance evidence |
| --- | --- | --- |
| Lookalike/encoded URL or target conflict | Strict parsed origin/resource schema and conflict handling | URL/resource negative cases; no connector dispatch for invalid targets |
| Prompt injection in issue/README/page/tool result | Untrusted data framing, read-only model session, independent native policy | Malicious issue summary causes zero writes, account changes, credential exposure, or policy changes |
| Tool description/annotation masquerades as safe capability | Reviewed native tool/schema allowlist; unknown classifications disabled | Unknown/write tool names and changed schemas cannot dispatch |
| Connection inferred from visible page/Keychain presence | Explicit account identity/capability verification | Disconnect blocks authenticated reads while recognition remains distinguishable |
| Wrong or switched account | Explicit account selection, repository policy, generation checks | Two-account ambiguity and in-flight switch/disconnect cases |
| Stale browser destination | Context ID/version bound to resource and future proposal/grant | Navigation from resource A to B invalidates old proposal |
| Forged local approval/browser message | Paired authenticated IPC, message directions, native approval authority | Forged/mismatched/oversized frames fail before context or tool acceptance |
| Secret leak in results/diagnostics | Keychain-only secret boundary, bounded redacted diagnostics, privacy checks | No credentials in persistence/model/receipt/log payloads |
| Neighboring private screen/window | Existing ScreenCaptureKit exclusions and local privacy preflight | Actual mixed-window capture exclusions on the Mac |
| Timeout/restart/duplicate remote write | Durable dispatch ledger, unknown state, reconciliation, no blind retry | At most one dedicated-test issue after uncertain response and restart |
| Arbitrary custom endpoint/redirect/private network | Custom connectors disabled; later modern SDK + DNS/origin/SSRF controls | Redirect/private-target/DNS-rebinding checks before M7 enablement |
| Giant content or runaway tool loop | Bounded frames/results/calls/pagination/deadlines | Boundary cases reject oversize/over-budget work and cancel active requests |

Provisional budgets: at most eight connector calls per interactive task, ordinary reads about 15 seconds, slow reads about 30 seconds, overall task about 60 seconds, and bounded result bytes/pages. These are design limits to measure, not performance results.

## Custom and additional connector gate

M7 stays disabled until the modern protocol/SDK path, remote authentication, endpoint trust/SSRF protections, schema review, and browser/IPC pairing are stable and verified. A fixed reviewed legacy GitHub endpoint is not approval for arbitrary remote servers.

Do not execute pasted shell commands or arbitrary local stdio servers. There is no automatic MCP installation or arbitrary executable discovery. Notion, Linear, Google Docs, and authenticated LinkedIn capabilities require their own current official verification and implementation. The catalog must describe unavailable/configuration-required states honestly.

## Release gates and evidence

| Milestone | Gate |
| --- | --- |
| M0 | Ownership/design freeze and primary external verification recorded; no accounts connected by the audit |
| M1 | Truthful native catalog, account representation, connection states, Keychain boundary, and capability detail UI |
| M2/M3 | Signed/installed paired native browser delivery, authenticated IPC, navigation versions, crash/cancel behavior verified on the Mac |
| M4 | Negotiated pinned MCP client, bounded discovery/pagination, reviewed schema/allowlist, call/cancel/tool-change/reconnect/shutdown behavior |
| M5 | Real authorized GitHub issue read; correct resource/account; grounded answer; disconnect and malicious-content checks |
| M6 | M5 accepted first; native exact approval, durable dispatch ledger, unknown reconciliation, duplicate prevention, and dedicated-account write acceptance |
| M7/M8 | Modern connector trust/SSRF/authentication stability and service-specific verification before additional capabilities |
| M9 | Nested signing/hardened runtime/notarization/stapling, legitimate native host installation, migration, clean-machine and measured M2 8 GB performance |

Mandatory real GitHub read acceptance includes opening a permitted real test issue, obtaining exact browser resource context when browser delivery is enabled, reading through the selected authorized account, answering from that response, disconnecting, and proving authenticated retrieval is no longer claimed. An explicit-target-only run cannot establish browser-context acceptance.

Mandatory future writes show account, repository, operation, full title/body/labels; cancel creates zero issues; approve creates one; proposal mutation invalidates approval; uncertain response/restart reconciles with at most one issue. Account ambiguity, stale navigation, prompt injection, and forged IPC are separate security cases.

Software checks establish their named deterministic boundaries. Synthetic tests do not establish account access, provider-side read-only behavior, native browser installation, screenshot exclusions, physical Mac operation, packaging, performance, or external write outcomes. Keep those gates explicitly pending until observed.

## Implemented read limits and validation checkpoint

The native read adapter permits at most three `tools/list` pages per discovery and runs discovery before and after exactly one reviewed `tools/call`: at most seven connector operations per resource task. Legacy initialize/initialized and an optional tool-change stream are protocol traffic, not hidden extra tool executions. A server requiring more discovery pages fails closed. The entire SDK session has a 30-second deadline; frame limits are 64 KiB outgoing and 256 KiB incoming, with the Core resource payload further capped at 32 KiB. No automatic read retry is installed.

Configuration transactions retire active reads before their first credential or persistence suspension. New reads are refused during configuration, preventing a verification snapshot from overwriting a concurrent account failure. Request IDs also have a unique invocation owner, so replacing a request cannot let an older continuation dispatch or erase the newer binding.

The synthetic SDK harness exercises the actual official Client JSON-RPC handshake and read flow using an in-process transport. It is not evidence about a real hosted GitHub deployment. The Core harness verifies that these read results never become extracted items, native actions, Session Memory facts, or durable Memory. Existing native action requests containing a URL keep their existing confirmation route.

## 9 October 2026 connector amendment

A fixed Linear GraphQL read connector is now part of the implementation scope. It stores the personal API key in Keychain, sends it only to `https://api.linear.app/graphql`, and exposes fixed viewer and issue queries. Each account allowlists at most 32 issue identifiers; issue text is request-scoped and bounded. Linear comments, team-wide search, and all mutations remain unavailable. The connection form directs the user to make a key with Read permission and selected teams.

This amendment records code scope only. Build validation, live Linear account verification, and runtime acceptance remain pending. Authenticated LinkedIn and Google Docs access remain unimplemented until their OAuth app settings and intended data scope are ready. WhatsApp chat access is out of scope.
