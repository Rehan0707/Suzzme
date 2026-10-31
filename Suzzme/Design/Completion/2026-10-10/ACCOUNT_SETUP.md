# Account configuration and live acceptance

No OAuth flow, private account sign-in, credential entry or live external-provider mutation was performed in this pass. Do not paste access tokens or secrets into a chat or source file.

## Google registration required

Current build settings still contain placeholder IDs. Supply registered **public** iOS and macOS OAuth client IDs for the actual Suzzme bundle identity `rehan.Suzzme`; confirm the Google Cloud project and consent-screen ownership. Do not provide a web client secret.

1. Register the supported platform clients in Google Cloud using the actual bundle/team configuration. Review the macOS installed-app flow supported by GoogleSignIn before choosing its client type. Do not substitute an unrelated application's IDs.
2. Set `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_MACOS_CLIENT_ID` and their reversed-ID build settings for the intended configurations. Existing `GIDClientID`, platform reversed-ID metadata and URL types must agree. Reversed form is `com.googleusercontent.apps.<client-id-prefix>`.
3. Enable only the APIs being tested. Configure consent, privacy policy, authorized test users and required scope verification with Google. Gmail uses metadata scope; do not broaden to message bodies/attachments.
4. Build a signed application and test platform callback routing, SDK state handling, cancellation, restored sign-in, refresh, changed scopes, revocation and account switching. Fixture coverage cannot accept the SDK/server interaction.
5. Connect each selected service through its own UI, grant only its requested read scope, set resource IDs where required, verify a real bounded read, then disconnect and check local/provider revocation separately.

The existing GoogleSignIn/AppAuth stack owns authorization state and token refresh. This pass did not replace it with hand-written OAuth or claim placeholder configuration works.

## Established connectors

| Provider | Configuration entered locally | Required live tests |
|---|---|---|
| GitHub | Dedicated fine-grained token, selected repositories, read-only Contents/Issues/PR permissions | Identity, allowed/denied repo, exact commit file, issue/PR, schema change, expiry, revocation, local disconnect |
| Notion | Read-only internal connection token, explicitly shared pages and page allowlist | Bot/workspace identity, shared/unshared page, bounded blocks, pagination disclosure, revocation |
| Linear | Personal API key with Read permission/team restrictions, allowed issue IDs | Identity, allowed/denied issue, status, changed account, GraphQL partial errors, rate limit, revoke |
| Gmail | Registered Google clients and metadata consent | Header-only read, populated summary, account switch, token refresh/expiry, permission revoke, deletion |

For the three selected-resource summary adapters: connect alone must produce no intake; select an exact allowed URL separately; refresh; inspect minimal retained provenance; ask a daily question and follow-up; disable selection; verify observations/cache/follow-up no longer expose it.

## Newer adapters: implemented, live acceptance pending

All 24 have synthetic HTTP coverage. No row is live-account accepted.

| Provider group | Services | Remaining configuration/acceptance |
|---|---|---|
| Personal credential | Asana, Airtable, ClickUp, GitLab, Figma, Todoist, Typeform, Pushbullet, Harvest, WakaTime, YNAB, Contentful, Eventbrite | Enter a dedicated least-privilege credential locally and exact resource scope shown by its setup screen; verify provider identity, first read, pagination, empty result, denial/expiry/revocation and local disconnect |
| Google OAuth | Drive, Calendar, Docs, Sheets, Slides, Tasks, Classroom, Meet, Analytics, Search Console, BigQuery | Real platform clients, consent/test-user/API registration, explicit service scope and resource IDs; accept refresh/revoke/account switching and real responses |

PATs are user-managed credentials; some providers issue broadly privileged tokens. Suzzme dispatches fixed reads only, but users should still restrict/expire the token at its provider. Local disconnect cannot falsely promise provider-wide PAT revocation.

LinkedIn has no authenticated account adapter. Screen context explicitly shared by the user grants no profile, inbox, messaging, publishing or analytics API access. WhatsApp chats, contacts and messages remain intentionally excluded.

## Browser and custom MCP prerequisites

The GitHub URL handoff is implemented; it is not the authenticated browser bridge. Production browser pairing needs a real allowlisted extension ID, reviewed App Group/IPC configuration, signed bundled native host, native approval/Keychain pairing UI and signed installer/registration. See `../../../BrowserExtension/README.md` for the exact wire/trust requirements. No invented IDs or unsigned shell host were supplied.

Custom MCP remains visibly unavailable. The current reviewed tool registry authorizes specific GitHub reads, not arbitrary discovered server tools. Before enabling custom servers, define reviewed read schemas, approved origins/transports, credential/trust lifecycle and mutation policy. Do not allow arbitrary local commands or treat tool annotations/output as authority.
