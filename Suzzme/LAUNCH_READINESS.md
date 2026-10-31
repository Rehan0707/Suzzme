# Suzme release evidence — updated 31 October 2026

Status: **release acceptance incomplete**. Preserve target/bundle/store identifiers `Suzzme` / `rehan.Suzzme`. This report separates source implementation from account, physical-device and distribution acceptance. No provider account was authenticated in this pass. Gmail OAuth configuration and the browser bridge's Team ID, App Group and extension ID setup remain incomplete. No configuration values or credentials are reproduced here. The 31 October update adds a bounded one-time Local Knowledge folder import and optional same-day Mac Daily Summary source; it also records the already-present, explicitly selected macOS WhatsApp local source. Neither is a hosted WhatsApp connector or an iOS chat reader.

## Source and consent matrix

All private reasoning uses the shared local intelligence pipeline. Network retrieval is separate from local reasoning. “Implemented” below means code exists, not that a real account passed acceptance.

| Source | Implementation and scope | Consent / credentials | Network | Platforms | Evidence / blocker |
|---|---|---|---|---|---|
| Calendar | EventKit context and information; deterministic confirmed actions with readback | OS permission; explicit mutation confirmation | No app-owned retrieval network; OS account sync separate | iPhone/iPad/Mac | Steps 8/9; real permission/action acceptance pending |
| Reminders | EventKit tasks/deadlines; confirmed verified mutations | OS permission; explicit mutation confirmation | Same OS sync distinction | Both | Steps 8/9; physical acceptance pending |
| Contacts | Authorized bounded local contact context | Contacts permission | No app-owned retrieval network | Both | Source code; real permission acceptance pending |
| Watched pages | **Paused for network safety**. Saved URLs/updates remain inspectable and removable; new intake/refresh are disabled | Saved records require individual review before future resumption; optional consent revision preserves existing JSON | No watched-page requests in the current default fetcher | Both | Direct numeric socket and original-host TLS passed isolated tests; complete DNS and platform acceptance remain gates. See [transport evidence](WATCHED_LINKS_SECURITY.md) |
| Selected Messages | Pasted user-selected text or bounded selected plain-text files, local recent information, up to seven-day expiry | Review/import/delete | No | Both | Connector fixtures; no private Messages database access |
| Gmail | Up to 30 recent inbox headers: sender, subject, date; no bodies, attachments or mutations | GoogleSignIn, valid platform OAuth clients, metadata scope, explicit consent; Keychain | Google | Both | Connector fixtures; OAuth clients and real consent/expiry/revoke acceptance pending |
| GitHub direct | Read-only allowed repositories and supported exact resources | Dedicated credential in Keychain; explicit repository scope; verify/disconnect/retry | GitHub | Both | Gateway/security fixtures; live connect/read/disconnect pending |
| Notion direct | Read selected allowed pages; bounded supported text; omitted content disclosed | Keychain credential and allowed page IDs | Notion | Both | Notion fixtures; real account acceptance pending |
| GitHub/Notion/Slack via Composio | Exact issue / top-level page text / one channel message; no replies or attachments | Owner HTTPS server, device token in Keychain, separate provider consent | Owner server + Composio + provider | Both | Mocked client/server suites; real deployment and revocation acceptance pending. Forget removes local setup only |
| LinkedIn | **Partial: explicitly shared text or screenshots only**; no profile/feed/inbox account retrieval | User chooses content, reviews OCR text before asking | No provider retrieval | Both; screen awareness Mac only | Connector rejects profile connect/read before network; legacy authorizations need owner revocation |
| Chrome active tab | **Partial: setup suggestion only**, app/service ID or canonical GitHub repository slug; no general page-content delivery | User enables extension/helper, real signed IDs, expiring pairing, explicit approval | Native Messaging/XPC locally; subsequent provider setup separate | Mac Chrome | Protocol fixtures; installed signed chain pending |
| Safari | **Partial: URL-only native Share extension implemented**; no tab pairing/monitor or page-content read | Explicit system Share, URL review and Send; owner signing/App Group setup | No extension network | Both | Shared inbox checks and final builds; signed installed handoff pending |
| iOS share handoff | **Partial: embedded URL-only Share extension implemented**; user returns to the app to review | Explicit Share/Send plus real provisioned App Group | None until separate user-authorized provider read | iPhone/iPad | Signed App Group/device acceptance pending; no automatic containing-app launch |
| Local Knowledge | User-selected text/Markdown, pasted notes, and bounded one-time folder import (up to 8 small UTF-8 text/Markdown files within 2 folder levels); saved excerpts can be included in the Mac Daily Summary only on their analysis day | Explicit file/folder picker or pasted note; inspect/search/export/delete; no persistent folder bookmark or watcher | No model upload; local on-device analysis | Both for library/Q&A; Mac only for Daily Summary intake | 49 deterministic Local Knowledge fixtures passed, including folder bounds and same-day summary scope; live model and platform picker acceptance pending |
| Shared screenshots/text | Explicit selected image OCR/text, bounded request-local evidence, review and cancel | File picker/paste; user reviews text | No | Both | Shared-context suite; unsupported cases remain actionable |
| WhatsApp local | Explicitly chosen macOS shared folder; up to 20 selected chats; today's bounded text only; on-device summaries; no send/reply/API access | User selects the WhatsApp for Mac folder and chats; macOS Full Disk Access may be required; disconnect clears local setup and summaries | No cloud WhatsApp API or browser ingestion | Mac only; iOS receives only the separate prepared Daily Summary if opted in | WhatsApp SQLite/WAL fixture checks pass; real WhatsApp schema, Full Disk Access, and Mac account acceptance still pending |
| Other catalog entries | Native read recipes exist for some providers; remaining entries are **catalog only** | Per-provider token/OAuth scope and verification required | Provider only when connected | Both | See `ProviderReadRecipe` / `GoogleProviderRecipes`; fixtures do not certify live APIs |

The broader catalog includes existing provider recipes (Asana, Airtable, ClickUp, GitLab, Todoist, Typeform, Pushbullet, Harvest, WakaTime, YNAB, Contentful, Eventbrite and Google services). These are inherited code, not newly verified live integrations. Catalog-only cards grant no access. Provider-specific consent text describes supported fields; token permissions may exceed Suzzme's read paths and must be reviewed.

## Intelligence, voice, memory and presence

Apple Foundation Models are availability-checked, with deterministic local fallback. Hardware, OS, locale and model readiness determine availability; simulator compilation does not prove model availability. No private context is silently sent to a cloud LLM. Daily context, Daily Summary and inspectable long-term memory use separate stores. Generated text has no action authority. OS background scheduling does not guarantee an exact execution time.

Home already contains the lavender/pearl/pale-blue brand tile and animated three-chevron Face. Listening/reasoning/speaking/success/error, Presence Themes, reduced motion and audio progress remain on the existing pipeline. The existing 1024px iOS icon was visually inspected and matches this identity. No icons or identifiers were regenerated in this pass.

Mac Control–Option uses tap-to-start; key release does not finish recording. Done finalizes transcription, then the current owned request can produce spoken output. Typed interaction remains available. Unsupported on-device speech recognition retains typed use. The optional natural voice downloads pinned model assets from Hugging Face after a user action; synthesis stays local. The default Apple voice remains available without that asset download. Hardware permissions, silence, audio routing, rapid invocation, cancellation and window-close behavior require physical acceptance. No raw audio file retention is implemented.

## 31 October 2026 verification update

The current checkout builds successfully for unsigned Debug macOS and iOS Simulator targets. `zsh Validation/local-knowledge-check.sh` passes 49 deterministic fixtures, including the new bounded folder importer and the rule that old saved notes do not replay into later Daily Summaries. The isolated WhatsApp local-reader fixture passes. `npm --prefix ConnectorServer test` passes 56 server tests. These checks do not authenticate a provider, exercise real user data, prove physical-device permissions, or make the app distributable.

## Changes in this pass

- Fixed dark-appearance Home contrast: the pale branded tile now keeps dark Face ink while retaining live state/motion/audio behavior.
- Gated browser startup/window-focus tab queries on explicit automatic-prompt opt-in; repaired stale browser test doubles and permission expectations.
- Added the native URL-only Share extension, bounded expiring App Group inbox, explicit Sources review and signed-installation setup instructions. No text/chat ingestion or automatic app launch is added.
- Corrected the watched-page capability claim: current fetching/intake is paused for network safety.
- Added a direct numeric-socket transport with maintained SwiftNIO HTTP/TLS parsing, normal system hostname/certificate evaluation and certificate network fetching disabled. Production enablement remains gated.
- Added individual watched-link re-consent, bounded cancellable HTML extraction, frozen legacy inspection/deletion, and exact-provenance revalidation before cached watched details can enter Daily Summary or opportunities.
- Removed LinkedIn profile connect/read choices and blocked retrieval before network in native client and server; kept legacy records so the owner can identify old authorizations.
- Browser LinkedIn setup now opens the shared-content explanation.
- Made WhatsApp catalog-only, removed it from source selection, and reject legacy labeled imports without changing stored identifiers.
- Added boundary regression checks; updated setup and release documentation.
- Preserved staged/unstaged/untracked owner work; no reset, clean, stash, commit or broad rename.

## Verification

Four unsigned builds completed after the Share target was added: Debug and Release for iOS Simulator and macOS, all exit 0. Their logs are `Validation/Reports/Launch-20261021/logs/{debug-ios,debug-macos,release-ios,release-macos}.log`. They predate the current Watched Links changes and do not certify this revision. Fresh transport checks and platform builds are recorded separately below. Simulator rendering and physical-device acceptance are still unverified. The earlier `/tmp/suzme-launch-20261020/` evidence was removed during an interruption; results identified as historical below are retained observations. Initial sandbox attempts could not access CoreSimulator/default caches or launch compiler macro plugins; these were environment failures, not behavioral passes.

Fresh completed checks on 21 October: Share queue 38/38; integration safety 191/191; shared text/screenshots 35/35; Step 6 53/53; Step 7 90/90; Step 8 198/198; Step 9 156/156 including persistence; Step 12 410/410; voice 31/31; shortcut 29/29; integration presentation 119/119; UI recovery 46/46; server 45/45; browser protocol 60/60; browser GitHub 98/98; screen privacy 7/7; backend invariants 6/6. Foundation and persistence aggregate checks also passed. Real Vision OCR passed after a slow first Apple Neural Engine compilation on this host; physical latency remains an acceptance item.

## Watched Links security verification — 22 October

**Fetching remains disabled.** The new direct numeric socket passed original-host TLS and exact-peer tests. The cancellable DNS-SD wrapper separately requests A/AAAA and rejects every unsafe delivered result, but `MoreComing` only describes queued callbacks: it does not prove the complete initial answer set. This is the remaining engineering gate, rather than a claim that DNS preflight proves the connection. The app never silently resumes old links. See [the complete authority trace and proof limits](WATCHED_LINKS_SECURITY.md).

Commands below ran from `Suzzme/`. Evidence is retained under the ignored `Validation/Reports/WatchedTransport-20261021/` directory; final Core logs are in `logs/`.

| Command | Final observed outcome |
|---|---|
| `zsh Validation/watched-url-policy-check.sh` | 216 passed, 0 failed; local URL/address and legacy storage fixtures |
| `zsh Validation/watched-transport-check.sh` | 132 passed, 0 failed; Core orchestration, shrinking deadlines, consent and stale ownership |
| `zsh Validation/watched-dns-resolver-check.sh` | 65 passed, 0 failed; six real LocalOnly daemon descriptors closed in about 1.76–2.09 ms; 40 scripted races separate from native evidence |
| `zsh Validation/watched-extraction-check.sh` | 49 passed, 0 failed; worst full-size hostile input 0.162 s; active cancellation 0.0002 s |
| `zsh Validation/watched-pinned-connection-check.sh` | 19 methods / 60 cases; 52 actual local TLS GETs, zero decoy/AIA connections; Release excludes test trust overrides |
| `zsh Validation/step10-check.sh` | 194 passed, 0 failed; architectural checks passed |
| `zsh Validation/step11-check.sh` | 244 passed, 0 failed, including 21 new cached-provenance/revocation checks |

The first Step 10 run passed all behavioral checks but its static scan misclassified an inert `web:https://` provenance identity as an external dependency. The scan now checks network APIs and endpoint construction; the rerun passed. Earlier DNS test failures are retained: one fixture Sendable compile error and an incorrect assumption that DNS-SD closes dispatch-source descriptors synchronously. The final native test measures actual asynchronous closure. This host resets excess TCP backlog connections, so a stalled TCP handshake was not induced; pre-connect socket ownership and actual stalled TLS closure were tested separately. No public provider account or arbitrary internet host was used as connection proof.

Final unsigned app builds on 22 October all exited 0:

| Configuration | Destination | Evidence in `Validation/Reports/WatchedTransport-20261021/logs/` |
|---|---|---|
| Debug | `generic/platform=iOS Simulator` | `debug-ios-final.log` |
| Debug | `platform=macOS` | `debug-macos-final.log` |
| Release | `generic/platform=iOS Simulator` | `release-ios-final.log` |
| Release | `platform=macOS` | `release-macos-final.log` |

Each used `xcodebuild -project Suzzme.xcodeproj -scheme Suzzme -configuration <configuration> -destination <destination>`, with `CODE_SIGNING_ALLOWED=NO build`, `-jobs 1`, `-disableAutomaticPackageResolution`, `-skipPackageUpdates`, the dedicated `Validation/Reports/Launch-20261021/DerivedData` cache and the existing Xcode SourcePackages clone cache. [The command/result record](Validation/Reports/WatchedTransport-20261021/final-builds-results.json) preserves every exact argument and exit status. The initial iOS attempt caught a missing preview callback after adding Remove; that callback was fixed before all four final passes. The real adapter is type-checked even while runtime availability stays off.

## Earlier recorded commands and results (20 October)

Commands run from `Suzzme/` unless a full project path is shown. Behavioral compiler checks use `CLANG_MODULE_CACHE_PATH=/tmp/suzme-launch-20261020/module-cache`; approved host access was needed for compiler plugins.

| Command | Historical outcome; earlier logs no longer retained |
|---|---|
| `zsh Validation/check.sh` | Passed Foundation/fallback/grounding checks |
| `zsh Validation/persistence-check.sh` | Passed production pipeline and in-memory persistence |
| `zsh Validation/step3-check.sh` | Passed context/privacy/session/routing/action checks |
| `zsh Validation/step4-check.sh` | Passed query windows, timezone and cross-source context |
| `zsh Validation/step5-check.sh` | Passed |
| `zsh Validation/step6-check.sh` | 53/53 |
| `zsh Validation/step7-check.sh` | 90/90 plus architecture checks |
| `zsh Validation/step8-check.sh` | 198/198 (176 behavioral + 22 Core integration) |
| `zsh Validation/step9-check.sh` | 132 behavioral + 24 persistence-fixture checks; all passed |
| `zsh Validation/step10-check.sh` | 194/194 daily-context/proactive checks |
| `zsh Validation/voice-lifecycle-acceptance-check.sh` | 31/31 |
| `zsh Validation/global-shortcut-check.sh` | 29/29 reducer checks; hardware registration pending |
| `zsh Validation/connector-acceptance-check.sh` | 60/60; includes deliberate read-only store failure/recovery fixtures |
| `zsh Validation/integration-presentation-check.sh` | 119/119 |
| `node --test ConnectorServer/server.test.mjs` | 45/45; mocked providers and localhost only |
| `node BrowserExtension/Tests/protocol-check.mjs` | 60/60; includes disabled-discovery privacy regression |
| `node BrowserExtension/Tests/github-connection-check.mjs` | 98/98 including actual popup handler with browser double |
| `zsh Validation/browser-bridge-check.sh` | 57/57; signed installation remains unverified |
| `python3 Validation/screen-privacy-check.py` | 7/7 |
| `python3 Validation/backend-reliability-check.py` | 6/6 static invariants |
| `git diff --check` | Passed |

The initial browser fixture failures were stale expectations for a removed `scripting` permission and missing mocks for the current popup/startup APIs. Fixtures now assert the narrower manifest and exercise the actual handlers; no permission was added to make tests pass.

## Owner acceptance gates

1. Configure Apple signing/provisioning for app and widget, capabilities and Keychain groups. Choose TestFlight/App Store and Mac signing/notarization path; run signed archive validation.
2. Configure actual Google iOS/macOS OAuth clients and callbacks matching shipped bundle IDs. Exercise consent denial, successful metadata retrieval, expiration, retry, disconnect and provider revocation.
3. Use test GitHub/Notion accounts with least privilege; exercise scope denial, fresh read, offline/rate-limit/expired token and disconnect. If using Composio, deploy the reviewed server and verify provider revocation separately from local Forget. Revoke any earlier LinkedIn profile grant.
4. Supply actual browser extension ID, signing Team/App Group, sign host/broker/app, install Chrome extension and native manifest, approve helper, pair and revoke. Do not count fixture HMAC checks as installed IPC acceptance.
5. Configure and sign the Share extension/App Group, enable it in the Share menu, and execute [the handoff acceptance steps](SHARE_HANDOFF.md). Safari tab pairing is still unavailable. Watched-page fetching remains paused until complete initial DNS-answer-set semantics are proven and the full transport contract is accepted. The implemented socket/TLS path alone does not clear that gate.
6. Physically test iPhone/iPad and Mac: VoiceOver, accessibility text sizes, contrast/transparency/motion, microphone/speech permissions, Done/cancel/interrupt/retry/silence, Bluetooth/audio routing, Control–Option repetition and closed-window lifecycle, notifications/widget, migration/recovery and energy use.

Do not call this build distribution-ready or launch-ready until these gates pass.
