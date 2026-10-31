# Suzzme — connection continuation

2026-10-08. Read-only Notion added to the existing connection architecture. Live account acceptance remains pending.

## Implemented

- A production Notion REST client verifies an internal connection’s bot identity and explicitly shared page access. Only fixed-origin GET requests to `api.notion.com` are exposed; no external AI or TTS service was introduced.
- Connect, verify, replace token, choose the read default, and disconnect use the existing IntegrationController, IntegrationGateway and device-only Keychain boundary. Notion defaults cannot replace a GitHub default.
- Up to eight explicit page IDs/official page URLs can be allowed. Reads fetch live identity, page metadata and one bounded top-level text excerpt. Nested/paginated omissions are labeled. No workspace search, child-page traversal, attachments, writes or background ingestion are enabled.
- Notion content reaches the existing Context/IntelligenceRouter/SuzzmeCore path as untrusted request data. It is not added to Memory, Information Store, Daily Summary or action planning.
- Existing GitHub metadata decodes unchanged. Credentials keep their established Keychain namespace and unique account UUIDs.

The adapter pins the documented [Notion API version](https://developers.notion.com/reference/versioning) and uses [token identity](https://developers.notion.com/reference/get-self), [page retrieval](https://developers.notion.com/reference/retrieve-a-page), and [block children](https://developers.notion.com/reference/get-block-children). Users must enable Read content and share pages with their internal connection as described in [Notion authorization](https://developers.notion.com/guides/get-started/authorization).

## Defects repaired

1. An old Ask presentation dismissed the latest global request instead of its own. Typed/Talk requests now capture ownership before dispatch; dismiss and cancellation preserve newer requests. Existing global voice rendering remains shared.
2. Cancelling connection setup during metadata saving could still publish Connected. Both new provider connections now check after the commit and perform uncancelled credential/metadata rollback; unprovable cleanup disables access.
3. Page/repository URL slugs containing words such as `Update` were misclassified as mutation requests. URL target data is excluded from intent checks; explicit write requests remain denied.
4. Concurrent credential loads could bypass the eight-read limit. Capacity is checked again immediately before creating a provider task.
5. Direct integration-detail navigation did not load saved accounts. It now loads through the existing controller.
6. A recovered metadata load left an old storage error visible. Load-origin errors now clear on recovery without erasing operation failures.
7. Live page permission/identity failures now retire readiness and require explicit verification.
8. The answer badge called all retrieved context local. It now says “Using context for this request”; processing remains local even when a provider supplies authorized data.

## Validation

| Check | Result |
| --- | --- |
| iOS Debug simulator build | PASS, 0 warnings/errors |
| macOS Debug build | PASS, 0 warnings/errors |
| macOS Release build | PASS, 0 warnings/errors |
| Complete behavioral/regression run | 41 suites PASS |
| Notion client | 100 passed / 0 failed |
| Notion gateway/storage/races | 78 passed / 0 failed |
| Notion client → gateway → Core | 21 passed / 0 failed |
| Existing integration safety | 181 passed / 0 failed |
| UI behavior/ownership | 68 passed / 0 failed |
| Step 6 locked floor | 53 / 53 |
| Step 7 locked floor | 90 / 90 |
| Step 8 locked floor | 198 / 198 |
| Step 9 locked floor | 156 / 156 |
| Browser protocol/resource checks | 55 / 55 and 60 / 60 |
| Whitespace validation | PASS |

The connector harness uses synthetic HTTP and credentials with isolated temporary stores. The Core harness composes the shipping Notion client and Gateway with actual SuzzmeCore, Context, router, SwiftData and Step 8 coordinator. It confirms provenance, assistant progress, injection resistance, no durable Memory/items or action execution, honest fallback excerpts, native action confirmation, external-write denial and disconnect recovery. This establishes code/data-flow behavior, not a live Notion login or hardware acceptance.

## Actual app runtime

The shipping Mac app was restarted and exercised through native UI: Settings/Integrations → Notion setup; page URL alone leaves Verify disabled; Cancel returns to an unconnected catalog; an unconnected Notion question returns connection recovery. A subsequent ordinary typed question received an actual local answer, then Done returned to Home. Light appearance and System/Dark appearance were inspected; the original System preference was restored.

The shipping iPhone simulator app was installed and launched normally. Home dark appearance was inspected in `iphone-home-dark.png`. Launch-only overrides bypassed onboarding for that visual check; no mock source content or replacement app entry point was used. Interactive iPhone connector navigation remains unverified because this Xcode installation has no Simulator GUI.

No live account token was entered, no provider data was mutated, and physical voice/notch/Dynamic Island acceptance was not claimed.

## Files added

- `Suzzme/Core/Integrations/NotionIntegrationClient.swift`
- `Suzzme/Features/Settings/NotionConnectionSheet.swift`
- `Validation/NotionClientChecks.swift`, `Validation/notion-client-check.sh`
- `Validation/NotionGatewayChecks.swift`, `Validation/notion-gateway-check.sh`
- `Validation/NotionCoreChecks.swift`, `Validation/notion-core-check.sh`

## Files modified in this continuation

- IntegrationModels, IntegrationResource, IntegrationStore, IntegrationGateway, IntegrationController, IntegrationCredentials.
- IntegrationsView, AskSuzzmeView, AppEnvironment’s existing invocation API.
- IntegrationSafetyChecks, IntegrationPresentationChecks, integration-safety-check.sh, FinalUIBehaviorChecks.

## Remaining acceptance and scope

- Notion: user creates a read-content-only internal connection, shares selected pages, and enters its token into the app. Live provider login/read/revocation/restart acceptance is PENDING. Do not paste credentials into chat.
- GitHub: live PAT/MCP account acceptance remains PENDING.
- Gmail: registered Google OAuth configuration remains missing.
- Linear, Google Docs and authenticated LinkedIn clients are not implemented; their catalog remains truthful.
- Browser native-host pairing/deployment is not installed. WhatsApp/Messages support explicit shared text, not live private inbox access.
- Physical microphone, barge-in, TTS, Mac notch geometry/first-click/auto-hide and real iPhone Dynamic Island acceptance remain PENDING. Previous Step 5/7/8/10 hardware statuses are unchanged.

This pass completes the bounded Notion connection implementation and related defects, not an entire conversion of proprietary HeyClicky/Sentient functionality.

Evidence: `Validation/Reports/2026-10-08-notion-connection/validation.json` and individual suite/build logs. No commit or staging performed.
