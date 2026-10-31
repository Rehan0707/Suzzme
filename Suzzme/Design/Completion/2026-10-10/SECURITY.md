# Security and privacy review

Scope: shipping Swift app, source intake, integration transports, credential metadata, browser contract, existing action/model boundaries. This is an engineering review and regression run, not a penetration test or third-party certification.

## Reviewed protections

- Provider credentials remain in the existing actor-owned Data Protection Keychain namespace, keyed by account UUID, `WhenUnlockedThisDeviceOnly`, non-synchronizing. Identity/scope metadata is separate bounded JSON; neither tokens nor raw fetched bodies belong there.
- One 16-account policy applies to storage, connection, repair and UI. Restarted stored accounts require verification; saved metadata is not live authorization.
- Fixed HTTPS endpoint/resource recipes, bounded scope identifiers and account identity checks prevent model-supplied URLs from becoming transport authority. Redirects are rejected. HTTP clients use ephemeral sessions without cookies, cache or stored URL credentials, request/resource timeouts and response limits.
- Newly fixed: decoded JSON strings and keys are inspected for the credential, closing an escaped-token echo path into identity metadata or answer text. The documented Todoist identity `token` field is discarded before projection. Control characters in credentials are rejected before dispatch. No provider error body is shown as trusted recovery copy.
- Generic reads are bounded to three pages; partial reads are disclosed. Rate-limit state prevents immediate retries. Cancellation and account-generation ownership are checked at suspended boundaries. These protections have fixture coverage; real server behavior remains unaccepted.
- Summary intake is a separate explicit URL allowlist and source setting. Four resources/account, eight reads/cycle; minimal title/status/account/resource hash only. Raw body instructions/dates never become stored tasks/deadlines. Permission is rechecked on retrieval and follow-up; revoked selected data invalidates derived cached content and ephemeral conversation context.
- Follow-up authority retains account UUID and generation, not just URL. A shared URL under two accounts is ambiguous. Changed selection/revocation rejects old references before HTTP.
- External facts are marked untrusted in the existing model prompt. Foundation Models has no EventKit/MCP mutation authority. External writes remain disabled. Native Calendar/Reminder actions still cross the central Step 8 confirmation, commit-boundary authorization, exactly-once execution and verification gate.
- Browser context sharing is explicit; URL/title/excerpt handling excludes form/editable inputs and strips URL query/fragment. JavaScript proof/replay/expiry checks exist, but no signed host/IPC/pairing/install exists; **do not call the browser channel authenticated or operational**.
- Custom MCP is unavailable rather than trusting arbitrary tools or local commands. LinkedIn capabilities are limited; WhatsApp ingestion remains excluded.

## Remaining security/release work

1. Live OAuth SDK/server acceptance: platform registration, state/callback routing, refresh, scope revocation and account switching. Placeholder Google IDs cannot pass this.
2. Signed browser host plus peer code-signing requirements, real extension identity, native pairing approval, Keychain revocation and installer. A URL handoff grants no account access and is not authenticated IPC.
3. Individually review the 92 catalog-only APIs and each future MCP tool's schemas/authority before enabling access. Tool discovery/annotations alone never authorize reads or writes.
4. Watched-web DNS preflight followed by URLSession DNS resolution leaves a DNS-rebinding/TOCTOU hardening concern. Do not market arbitrary watched URLs as a hardened network boundary until this is resolved/retested. Provider connectors use fixed official origins and do not accept custom host URLs.
5. Verify local database/file-protection and backup behavior in signed iOS/macOS distribution, deletion/recovery semantics, device lock and migration. Existing bounded retention is not evidence of device encryption/backup acceptance.
6. Review transitive Google SDK behavior, privacy manifests and store disclosures. “On-device reasoning” does not mean external approved source reads require no network. No external AI inference client was added.
7. Installed-app permission revocation, crash diagnostics/log minimization and production entitlements still need signed hardware acceptance. Existing Contact/Calendar/audio entitlements require purpose/scope review at release.

No access tokens, passwords or private account content are printed by this report or the new tests. Synthetic credentials exist only in test fixtures. Existing historical reports and reference-source directories are not evidence that cloud inference is used by the shipping target.
