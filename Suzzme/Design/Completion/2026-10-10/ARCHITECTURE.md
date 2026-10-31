# Completion architecture and initial audit

10 October 2026. Actual source and fresh checks take precedence over historical reports.

## Initial audit, before this pass

- Shared SwiftUI application: `AppEnvironment` owns UI services; `SuzzmeCore` owns conversation routing. Existing Observation/MainActor UI and actor-isolated processing were preserved.
- One `VoiceSessionController`, one proactive orchestration engine, the existing Information store and separate long-term Memory store already existed.
- Native Calendar/Reminders use EventKit. Step 8 owns action planning, confirmation, commit authorization, execution and read-back verification. External connectors have no mutation permission.
- The provider directory had 121 entries, while domain descriptors described only six. Storage allowed 128 accounts but the gateway/safety tests expected 16. Linear had an implemented read client but outdated unavailable-state assertions.
- Reproduced four integration safety failures and a Linear presentation failure. Missing source dependencies also prevented some isolated harness builds. Both targets required fresh build verification.
- 24 newer fixed-endpoint read adapters existed but lacked comprehensive response/edge-case coverage. Google OAuth build settings were placeholders. Connecting did not establish proactive intake.
- Browser JavaScript and GitHub URL handoff existed. Signed native host, pairing, authenticated IPC and installation were absent. Custom MCP servers had no reviewed invocation policy and were correctly unavailable.
- Existing voice/Presence/model fallback/native actions were functional code with automated coverage, not new physical-device or live-account acceptance.

## Changes in this pass

The central account policy remains **16 persisted provider accounts**. Directory size does not widen account authority or storage. Google authorization remains separately owned by the existing Google controller.

Every persisted provider identifier now has one descriptor. Descriptors derive actual read capabilities from the existing recipes; reserved identifiers have no authentication or executable effects. Catalog-only entries remain non-connectable. Setup, repair and account-capacity controls use the same policy.

`IntegrationInformationSource` is an adapter into the existing pipeline:

```text
Explicit account verification + allowed-resource scope
    → separate selection of up to four allowed URLs per account
    → globally bounded eight resource reads per refresh
    → native minimal title/status normalization
    → existing Information privacy/dedup/SwiftData/freshness
    → existing ProactiveIntelligenceEngine / Today / Daily Summary
    → existing Core / Session Memory follow-up projection
    → fresh account-owned read through IntegrationGateway
```

Eligibility covers selected GitHub issues/PRs, Notion pages and Linear issues only. It is not permission: connecting, restoring metadata, or enabling the global source does not populate the URL selection. Legacy metadata decodes with an empty selection. Generic provider reads remain request-local; Gmail keeps its existing header-only source.

Account UUID and resource hash identify observations. Raw provider bodies, credentials and inferred deadlines are not retained. Full fetched content stays in the ephemeral request. Selecting a resource adds inspectable preference evidence, not automatic urgency. The existing freshness, expiration and source-health rules remain authoritative. There is no second intelligence engine or life-history database.

Summary follow-up references carry account ID, canonical URL and permission generation. The gateway validates that exact selection before and after the network read. Ambiguous references across accounts fail closed, including the same URL selected under multiple accounts. A changed selection retires prior references and in-flight ownership.

Disconnect/selection changes remove relevant local observations through the existing Information engine. Reads recheck permission; cached derived summaries and ephemeral conversations are invalidated if a referenced selected resource is no longer permitted. This never grants durable Memory admission or action authority.

## Limits

- Snapshot-based checks run when the existing source refresh/summary flow runs; no new polling daemon, webhook backend or continuous sync.
- Notion intake retains page titles, not a semantic digest of body changes. Linear custom status labels are data, not inferred completion authority. GitHub closed/merged state is recognized by its native structured projection.
- No imported dates are guessed from body prose. Deadlines require a future reviewed structured field integration.
- Eight resource reads per cycle and four selected resources per account; partial coverage is disclosed by source health. This is not a complete account inbox.
- OAuth registration, live provider acceptance, signed browser bridge, custom MCP policy, physical devices and release acceptance remain separate unfinished work.

## Acceptance dependency order

1. Stable capability/account contract → current-source builds and original safety/presentation checks.
2. Response adapters → fixture parsing/security/ownership tests → real configured accounts.
3. Separate intake consent → Information persistence/dedup → grounded summary → account-owned follow-up → revocation.
4. Existing voice/presence regressions → physical microphone/output/notch/Island acceptance.
5. Real signing/extension identity/App Group → authenticated native host → installed browser acceptance.
6. Hardware + live accounts + performance + signing/privacy/distribution review → release acceptance.

Expected affected files were the integration domain/store/gateway, connector settings, central source registration, Information model, proactive projection and Core routing, plus isolated validation dependency lists. The final changed-file inventory accompanies this report; unrelated staged and unstaged work was preserved.
