# Optional Composio account connections

## Composio MCP integration (2 November 2026)

The native Composio connector now initializes MCP, discovers the configured read tools, and calls them at `POST /v1/mcp`. Existing Connect → provider sign-in → confirmation-code verification and separate Daily Summary source selection remain in place. Both one-off questions and opted-in summary refreshes use the new transport through `ComposioConnector.read`.

The full path is **Suzzme → authenticated Suzzme MCP gateway → account-pinned Composio hosted MCP session → provider API → validated excerpt → Apple Foundation Models**. No cloud model is used. The client never receives the Composio project key or hosted session URL.

| Configured app | Tool exposed to Suzzme | Read scope |
| --- | --- | --- |
| GitHub | `suzzme_read_github_issue` | One exact issue URL |
| Slack | `suzzme_read_slack_message` | One channel-message permalink, after workspace/channel checks |
| Notion | `suzzme_read_notion_page` | Selected page's top-level text, with existing metadata checks |

Only configured apps appear in discovery. This does not enable the entire Composio catalog, mail ingestion, writes, or arbitrary model-selected tools. Gmail, calendar and other existing direct integrations are independent.

`composio-mcp.mjs` creates a hosted session using `/api/v3.1/tool_router/session`, with exactly one toolkit, auth config, owner ID and connected account. It verifies the returned account scope before initializing the returned MCP URL. The URL must share the API origin; redirects are never followed. Connections management, sandbox, instant usage, search and multi-execution are disabled. The server alone calls `COMPOSIO_PROXY_EXECUTE` using the existing deterministic read recipes. This general-purpose upstream tool is never exposed to the native client or the model. Tool hint filters do not restrict proxy execution: the server's fixed recipes are the read boundary.

Hosted sessions are cached in memory for at most five minutes per account, capped at 100 entries. They are discarded locally on failure; there is no automatic retry or silent REST fallback. Provider ownership/access is still checked before and after every read, including reads with a cached session. Both JSON and SSE upstream responses are bounded to 256 KiB. Remote sampling/elicitation is not supported and cannot authorize an operation. Source results remain capped at 4,500 characters. No source excerpts are cached by this module.

### Upgrade and live acceptance

Deploy the updated connector before using this native build's Composio source reads. The gateway keeps `/v1/read` for older clients; new clients use MCP and report an update-required error when the endpoint is absent. Existing owner URLs and device tokens do not need to change.

The server project key needs **Session management**, **Session tool execution**, **Proxy execute**, and the existing connected-account read/write permissions. Confirm the exact scopes in Composio's dashboard; keep the key on the server. Keep the existing OAuth verifier and provider auth configs. Each supported provider still requires its own successful consent and account verification.

Run `npm test` for the server, worker, deployment-bundle and hosted-MCP fixtures. Run `zsh Suzzme/Validation/composio-client-check.sh` from the repository root for native transport checks. These tests use fictional accounts and are not live OAuth acceptance. On 2 November, 72 server tests and 62 native checks passed, the Mac app built, and Wrangler validated and deployed Worker version `b1b77bec-08ea-4707-956f-4fc7d6d979e5`. The live configuration enables Slack only; GitHub and Notion need their auth configs added. Real hosted-session permissions, provider consent and source reads remain unverified. The supplied `clicky-main` source files were cloud placeholders and could not be read during this implementation, so this is based on Suzzme's existing flow and Composio's official contracts, not a verified copy of Clicky's implementation.

Post-deployment checks returned HTTP 200 for public health, 401 for unauthenticated MCP discovery, and 403 for a browser-origin request. The rebuilt Mac app opened the configured connector, loaded its Slack status and successfully generated a secure Composio sign-in link. It reported **No verified connection**; no provider permission was granted and no real message was fetched during this check.

Live acceptance remaining: complete provider verification in Suzzme, read a selected source, confirm the displayed account and source, opt that source into Daily Summary, then disconnect/revoke and verify subsequent reads fail. Test another account with the same provider to verify explicit account selection. This remains a **single-owner connector**, not shared sign-in isolation for a public multi-user service; do not distribute the same device token to different users.

References checked for this change: [Composio sessions via MCP](https://docs.composio.dev/docs/sessions-via-mcp), [session creation REST schema](https://docs.composio.dev/reference/api-reference/tool-router/postToolRouterSession), [MCP proxy tool](https://docs.composio.dev/toolkits/meta-tools/proxy_execute), [MCP HTTP transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).

## Cloudflare free deployment preparation

`worker.mjs` adapts the reviewed bridge routes to Cloudflare Workers. The SQLite-backed Durable Object binding in `wrangler.toml` is eligible for Workers Free and keeps one owner's short-lived OAuth attempts together. It writes no provider excerpts, credentials, or confirmation codes to Durable Object storage. An evicted instance loses pending sign-ins; restart the connection flow in that case. Request logging is disabled. Free quotas still apply.

Earlier deployment work stored the project key as `COMPOSIO_API_KEY` in Cloudflare Secrets Store and deployed the Worker at https://suzzme-connector.suzzmeai.workers.dev with a separate device secret. The configured Slack auth config is `ac_ZFadHeq1Ix9k`. The checked-in verifier flag is now `yes`; that flag and a healthy endpoint alone do not prove provider consent, MCP permissions or a working source read. Live MCP acceptance remains unverified for this change. No secrets are included in the repository or native app.

Deploy with Wrangler from this folder only after the owner approves its deployment permissions. Configure the project's OAuth verification URL to the deployed `/oauth/verify` address, add a separate strong `SUZZME_DEVICE_TOKEN` Worker secret, and set the verifier flag only after that callback setting is saved. Keep the project key on the backend; the app receives the separate device token through its existing Keychain setup form. This is still a single-owner bridge, not a public multi-user account service.

This is an owner-operated **single-user** connector bridge for Suzzme. It is not a public multi-tenant account service. It uses Node 24 built-ins with no package installation. AI generation remains in Apple Foundation Models on the device. Selected provider data passes through this server and Composio.

Supported reads are an exact GitHub issue URL, your own basic LinkedIn OpenID profile, one Slack channel message selected by permalink, and top-level text from one selected Notion page. LinkedIn access is profile-only; feed, inbox, messages, contacts, and publishing are unavailable. The bridge exposes no generic tool runner, posting, messaging, deletion, browser-cookie extraction or personal WhatsApp Web access. It does not use an LLM. The existing direct integrations and Shared App Context continue independently.

## Owner setup

1. Create your own Composio project and OAuth auth configs for the providers you enable, including `linkedin` only if you intend to connect it. For LinkedIn, review the auth config and request only the `openid` and `profile` scopes; Suzzme reads only `/v2/userinfo` fields for the user's basic name. Feed, inbox, messages, contacts and publishing are not supported. Review every provider consent screen. GitHub OAuth grants may be broader than the bridge's issue-only read policy. Prefer a dedicated test project/account and least available scopes.
2. Deploy this bridge on a host you control behind a TLS reverse proxy. Its public origin must have a valid HTTPS certificate, standard port 443 and no path prefix. Proxy to **127.0.0.1:7079**; never expose the loopback HTTP service directly. Forward `/v1/*` and `/oauth/verify`. Disable proxy access/body/query logging for OAuth and API paths: callback queries contain a temporary authentication secret. Add rate limits at the proxy; cap requests and do not cache responses.
3. In Composio project settings, set the **OAuth callback verifier URL** to `https://YOUR-HOST/oauth/verify`. The bridge deliberately requires this step. It does not treat an ordinary `status=success` redirect as authorization. Set the confirmation environment flag only after configuring this project setting.
4. Configure these environment variables in the server's secret manager/service environment. Never commit real values or paste them into chat:

   | Variable | Value |
   | --- | --- |
   | `COMPOSIO_API_KEY` | Project API key; server only |
   | `SUZZME_CONNECTOR_URL` | Your public HTTPS origin |
   | `SUZZME_USER_ID` | Stable opaque ID for this one owner; not a client-supplied user ID |
   | `SUZZME_DEVICE_TOKEN` | Separate random bearer credential, at least 32 random bytes encoded base64url (43+ characters) |
   | `SUZZME_AUTH_CONFIGS` | JSON object mapping enabled service to its auth-config ID, e.g. `{"github":"ac_GITHUB","slack":"ac_SLACK","notion":"ac_NOTION"}` |
   | `SUZZME_CALLBACK_VERIFIER_CONFIGURED` | `yes`, after step 3 |

5. Run `node server.mjs` from this folder using your service manager. It binds only loopback. Preserve the environment securely; do not put secrets in shell history. No deployment, account authorization, signing change or remote service was performed by Codex.
6. In Suzzme: **Settings → Sources → Integrations → Connect accounts with Composio**. Enter the public HTTPS origin and the **device token**, never the Composio project key. Suzzme stores that setup in a device-only, non-synchronizing Keychain item.
7. Choose Connect, then Open Secure Sign-in. Inspect the provider's consent screen. After sign-in, the server's verification page gives a single-use code. Return to Suzzme, enter it, and select **Confirm Account Connection**. Only do this for a connection you initiated. The server redeems the opaque OAuth session using its independently authenticated, fixed owner identity; mismatched service/user/config/status is rejected. Codes and connection attempts expire in ten minutes and are lost on server restart.
8. Choose the verified account, paste an exact GitHub issue URL, Slack channel message permalink or Notion page link, enter a question, and select Read Source and Ask Suzzme. The bridge permits only the three fixed content-read recipes plus Slack's channel-type check and fixed read-only identity probe (`auth.test`, which uses POST with an empty body). It rechecks account ownership/access after retrieval; Suzzme checks again after local inference and discards revoked results. Review the shown source text.
9. Separately, choose up to four exact supported links for that account under **Daily Summary**, then save the selection. The device allows up to eight selected links across Composio accounts, so every selected link can be checked in a refresh. Only those selected resources are read when information refreshes or a scheduled summary runs. Suzzme keeps bounded titles, GitHub status, and short on-device summaries for Slack and Notion; source excerpts are not stored. This consent is device-only and separate from connecting the app.

## Boundaries and acceptance

The bridge token authenticates this owner's devices, not different people. Do not distribute it to unrelated users or reuse this server as a shared SaaS service. A future public deployment needs real per-user sign-in, session management, authorization and operational review rather than a shared token.

Provider secrets remain with Composio; the project key remains server-side. Device removal deletes the local Keychain items and retires the selected-resource summary permission plus its local derived facts. Revoke provider grants separately in Composio/provider settings. No disconnect button claims remote revocation.

One-off Q&A results are transient and bounded to 4,500 characters. Daily Summary is a separate explicit opt-in: only derived local titles/statuses and short on-device summaries are retained, never the source excerpts. These facts do not enter long-term memory or action planning. Oversized responses fail rather than silently truncate. Privacy classification runs locally before model input; it cannot prevent provider data from reaching the connector used to fetch it. There is no cloud inference fallback. Cancel clears a Q&A result and prevents late UI publication; it cannot undo a request already received by Composio.

Run `node --test server.test.mjs` for fictional upstream fixtures and a temporary loopback HTTP test. This is **not** live OAuth/provider acceptance. Live acceptance remains pending until owner setup is complete. Test connect, cancellation, expired-code recovery, granted scopes, read, source display, revocation, token removal and both platforms before enabling this for personal accounts.

## Verified references (2026-10-19)

- [Connect Link REST API](https://docs.composio.dev/reference/api-reference/connected-accounts/postConnectedAccountsLink)
- [Callback identity verification](https://docs.composio.dev/reference/api-reference/connected-accounts)
- [Complete deferred OAuth](https://docs.composio.dev/reference/api-reference/connected-accounts/postConnectedAccountsCompleteAuth)
- [Proxy Execute API](https://docs.composio.dev/reference/api-reference/tools/postToolsExecuteProxy)
- [Token custody](https://docs.composio.dev/docs/security/token-custody)
- [LinkedIn OpenID Connect](https://learn.microsoft.com/linkedin/consumer/integrations/self-serve/sign-in-with-linkedin-v2)
- [GitHub issue read API](https://docs.github.com/en/rest/issues/issues#get-an-issue)

The v3.1 REST API manages authorization and account validation. New native reads use hosted MCP sessions with deterministic Proxy Execute; the legacy REST read route remains for older clients. No retired `initiate()` flow or model-discovered unrestricted tools are used.

## LinkedIn profile reads

Add the LinkedIn auth-config ID to `SUZZME_AUTH_CONFIGS` to enable its one-click Composio sign-in. The native client only offers LinkedIn when the authenticated connector reports it as configured. The supported read is the user's own basic profile from `/v2/userinfo`; the server returns the name fields only and does not expose email, feed, inbox, messages, contacts, or publishing. The connector rejects every other LinkedIn resource. No access is granted by opening the sign-in link; the user must approve LinkedIn consent and finish Suzzme's verified confirmation flow.

The Composio OAuth config must be registered and reviewed by the owner. This source change does not update a deployed Worker or establish live OAuth acceptance. Follow the setup checklist, enable only the desired profile scope, then deploy and test with the owner account.

## Slack message reads

Enable the `slack` auth config in `SUZZME_AUTH_CONFIGS`; existing GitHub- and LinkedIn-only configurations remain valid. Review Slack consent scopes and workspace approval requirements. Channel history and channel-type verification need the appropriate history/read permissions; this path does not require message-send, file-download or DM-history permissions. Managed OAuth grants may be broader than the implemented reads; use the least available scopes and follow workspace policy.

In Suzzme, open the Slack catalog entry, review access and configure the connector. Select the Slack account, paste a top-level channel message permalink and ask a question. The bridge checks Slack's authenticated workspace URL and verifies channel type with `conversations.info`, then requests a one-message timestamp interval and verifies an exact timestamp match. It does not fall back to a neighboring message. A renamed workspace or alias must match the authenticated workspace origin; copy a fresh link if needed.

Supported links use `https://WORKSPACE.slack.com/archives/CHANNEL/pTIMESTAMP`. Channel IDs beginning with `C` are supported; the returned conversation must also explicitly identify a channel and exclude both DM types. Direct messages and legacy `G` conversations are excluded to avoid group-DM ambiguity. Optional `thread_ts` and `cid` parameters are accepted only when they match that same parent message and channel. Thread replies, attachments and attachment-only messages are unsupported; files and full threads are never fetched. Only the selected message text and its posting/edit timestamps reach the native app/model; retrieval time is recorded separately.

Rate limits are surfaced without automatic retries or pagination. Depending on Slack app distribution, reads may be limited to one per minute. Missing scopes, inaccessible channels, unsupported messages, workspace mismatch and revoked connections fail without returning a substitute source. Live Slack acceptance still requires the owner's server and authorization; fixture checks do not establish real workspace access.

Official contracts checked 19–20 October 2026: [Slack single-message history](https://docs.slack.dev/reference/methods/conversations.history/#retrieving-a-single-message), [Slack identity probe](https://docs.slack.dev/reference/methods/auth.test/), [Composio Slack toolkit](https://docs.composio.dev/toolkits/slack).

## Selected Notion page reads

Enable a `notion` auth config in `SUZZME_AUTH_CONFIGS`. Authorize only the pages you intend to use and review Notion’s read-content capability. The server never searches a workspace or follows child pages, database content, files, links, comments or synced blocks. Existing direct Notion connections, token storage and allowed-page lists remain independent.

Open the Notion catalog entry, choose Composio, then select a verified Notion account and paste a page link containing its 32-character or hyphenated page ID. Supported hosts are `notion.so`, `www.notion.so` and one workspace subdomain of `notion.site`. Use a single page path, optionally prefixed by an ASCII title; remove query parameters such as `pvs` and fragments. Custom domains, shortened links and arbitrary URLs are rejected. Only the extracted page ID reaches fixed Notion API endpoints; the pasted URL is never fetched.

The bridge performs GET page metadata, GET its first child-block page (`page_size=100`), and GET metadata again, with a server-pinned `Notion-Version: 2026-03-11` header. It verifies page identity, archive/trash flags, title, creation/edit times, block parent IDs and duplicate IDs. Metadata edits or removal during retrieval invalidate the excerpt; this is a best-effort consistency check, not an atomic snapshot. Account access is rechecked afterward. Rate limits surface without automatic retries.

The result is explicitly a **top-level excerpt**. Supported blocks are paragraphs, headings 1–3, list items, tasks, toggles, quotes, callouts and code. Tasks retain done/to-do state. Nested blocks, unsupported blocks, non-text mentions/equations and pagination receive omission notices; they are never silently described as full-page evidence. Mention-only, unsupported-only and empty pages fail. The 4,500-character output and 256-KiB upstream caps fail rather than truncate text. Oversized pages may need the existing direct connection or a user-selected shared excerpt. No page content is saved automatically.

Live Notion OAuth/read acceptance is pending owner server setup and authorization. Fictional fixtures establish request policy and extraction behavior only.

Official contracts checked 20 October 2026: [Retrieve a page](https://developers.notion.com/reference/retrieve-a-page), [Retrieve block children](https://developers.notion.com/reference/get-block-children), [Composio Proxy Execute](https://docs.composio.dev/reference/api-reference/tools/postToolsExecuteProxy), [Composio Notion toolkit](https://docs.composio.dev/toolkits/notion).

## Local preparation and startup

Node 24 is required; there are no npm dependencies to install. From `Suzzme/ConnectorServer`:

```sh
npm run setup
npm run check
npm test
```

Setup creates `.env.local` with mode `0600`, a random opaque owner ID and a separate 32-byte device token. It never displays those values and refuses to overwrite an existing file or symlink. The file is ignored by Git. Keep `.env.example` free of real values. Enter the server project key privately in `.env.local`; never put it in the native app, command arguments, screenshots or chat.

`npm run check` prints readiness booleans only. An `INCOMPLETE` result and exit 1 are expected until the project key, HTTPS origin, enabled auth-config IDs and callback verification are configured. A `CONFIGURED` result validates local syntax only; it does not establish OAuth success, provider access, public HTTPS reachability or a rendered app screen. Keep the callback flag `no` until the actual project verifier is set correctly. When configured, `npm start` starts the existing loopback-only backend on port 7079. No public deployment or host is created by these commands.

For MCP, add **Session management** and **Session tool execution** to the bridge key's existing **Connected accounts: Read + Write** and **Proxy execute** permissions. Auth configs can be created separately in the dashboard. Connected-account write supports initiating/managing authorization; proxy execution includes this bridge's fixed provider reads. The key can perform broader API operations than the bridge exposes, so it belongs only on the server. [Official scoped-key permissions](https://docs.composio.dev/reference/authenticating-to-composio/project-api-key-permissions).

Dashboard inspection on 20 October 2026 found two-factor authentication enabled, OAuth user verification unset, and Zero Data Retention off on the current project. Its UI states that request/response payloads are stored in logs. Suzzme's transient local excerpts do not imply zero retention by Composio. Review project retention before connecting private accounts; no billing upgrade or retention change was made. GitHub's managed OAuth draft also selected seven scopes by default, including `repo`, `workflow` and `codespace`; that draft was not saved or authorized. Review scopes explicitly rather than accepting those defaults as read-only.

## Prepared Render hosting

[Render deployment instructions](RENDER-DEPLOYMENT.md) and `render.yaml` provide an explicit free-plan first deployment. Run `node prepare-render.mjs` to create the connector-only allowlisted bundle in `../Release/ConnectorServer-render/`; it excludes `.env.local` and all native app files. Nothing is uploaded by this command.

The hosted entry point is `node hosted.mjs`, using Render's assigned port and TLS proxy. Local startup stays loopback-only. A new hosted service without complete configuration exposes GET `/healthz` as `setup-required` and rejects every other route with 503. This lets the owner obtain the HTTPS origin before configuring OAuth verification. With valid configuration, health becomes `ok`, while all account operations retain device authentication and ownership checks. Health is not live-account acceptance. Configuration failures never activate a connection or cause a cloud inference fallback.

## Returning from sign-in (4 November 2026)

`POST /v1/connect` optionally returns `supportsStatus: true` when Composio supplied a connected-account ID. The bridge pins that ID to the expiring connection attempt; the client never chooses it. The authenticated `POST /v1/connection-status` accepts only `{ "attempt": "…" }` and returns either `{ "state": "pending" }` or a verified active account with `state: "ready"`. Ownership, toolkit, reviewed auth config, private account and exact account ID must match. An arbitrary redirect does not complete sign-in. Ready checks are idempotent until the ten-minute attempt expiry, so a failed native account refresh can be retried.

Suzzme checks once on returning to the active scene, or when **Check Sign-in** is pressed. It then refreshes accounts independently before displaying a connected notice. There is no background status polling. Older links without a pinned account still use the existing confirmation-code flow. Code-based completion also enforces the pinned account when one exists.

The existing Cloudflare Worker was updated and its public health endpoint returned `ok`. This verifies deployment/configuration only; it does not prove a working provider authorization or mailbox read.
