# OpenClicky review and Suzzme adoption

Reviewed 4 November 2026. Reference: `/Users/rehan/Documents/Projects/openclicky-main/`. The reference repository was read only; no app, daemon, downloaded model or background agent from it was run.

## Useful patterns

| Reference implementation | Suzzme decision |
| --- | --- |
| `cursor-buddy/OpenClickyAppSkillContext.swift` — app-specific capabilities and workflows | Keep Suzzme's reviewed browser app catalog and supported-use hints. App recognition suggests setup; it never grants account access. |
| `cursor-buddy/ClickyNextStageParityModels.swift` — permission-guide snapshot, readiness and response-card provenance | Add Connection Health, backed by actual model capability, verified account results and existing information-source health. Link directly to browser permission recovery and existing source controls. |
| `cursor-buddy/OpenClickyLocalModelStatus.swift` — present files versus verified runtime | Use Suzzme's Apple Intelligence runtime capability rather than a downloaded-model badge or a new Python server. Model readiness and account access remain separate checks. |
| `cursor-buddy/OpenClickySettingsWindowManager.swift` and `ClickyCodexConfigTemplate.swift` — optional Composio Connect MCP endpoint | Retain Suzzme's account-pinned, bounded read gateway. Add a verified return-from-sign-in status path; do not turn on an unrestricted tool runner. |
| `OPENCLICKY_ARCHITECTURE_REVIEW.md` | Treat this as review commentary, not proof that all advertised paths work. Check shipping callers and runtime owners before adopting a feature. |

## Implemented

- Browser **No** (30 days) and **Not now** (one hour) decisions persist through app restarts. Stored values contain only known service IDs and expiry dates. Invalid or excessively distant dates are discarded. Reset dismissed app suggestions clears the preferences and retires outstanding resolution/expiry work.
- Browser suggestions includes **Open Accessibility Settings**, **Check Access**, and reset controls. The existing optional signed Chrome bridge remains available. Native Safari/Chromium detection uses only exposed document URLs and requires Accessibility permission.
- **Sources → Connection Health** shows Apple Intelligence readiness, saved connector setup, verified active-account count, reconnect status, source enablement/health, last successful checks and partial-source limitations. Its retry action refreshes accounts, permissions and authorized enabled sources through their existing owners.
- Composio can now verify a browser sign-in using the exact connected-account ID issued with the link. Both server and native workspace recheck access before showing success. The manual confirmation-code path remains for older/provider-specific flows.
- Deployment export now includes the GitHub activity modules needed by the connector and checks that relative module imports exist in the export.
- Summary narration no longer depends on the network connector type merely to remove a trailing GitHub activity URL. Resource opening and authorization still use the connector's stricter URL policy.

No cloud inference, computer-control agent, private macOS API, silent source enrollment or automated outgoing communication was added. Those are separate products/access scopes and do not improve Suzzme's selected-source Daily Summary path.

## Live evidence and remaining setup

The signed Mac build was installed with the prior application retained as a backup. The live Connection Health screen reported Apple Intelligence ready, connector setup saved, zero active Composio accounts, and successful Calendar/Reminders refreshes. The Daily Summary screen displayed Calendar/Reminders provenance and an explicit incomplete-Gmail warning. This is not evidence of successful Gmail retrieval or WhatsApp synchronization.

The tested connector was deployed to the existing Worker; `/healthz` returned `ok`. Its configured providers are Gmail and Slack. Other advertised provider recipes need their reviewed server auth configs or their existing direct setup. A catalog entry does not mean an account has been authorized.

Browser Accessibility permission, successful provider OAuth and user-selected summary resources are still required for live browser-to-account-to-summary acceptance. WhatsApp is a separate explicit local-folder/chat or supported extension intake flow; it is not a consumer WhatsApp connection through Composio.

## Validation

- Signed macOS build: passed, including the final incremental build. The arm64 iPhone Simulator build also passed after the Mac-only WhatsApp route was corrected.
- Connector suite: 89 passed, including account substitution, ownership/config mismatch, expiry, authentication, legacy fallback and idempotent status checks.
- Native connector client: 77 passed using fictional transport fixtures.
- Browser handoff: 134 Swift checks and 98 JavaScript checks passed; catalog checks cover the 32 implemented service mappings.
- Real native Connection Health navigation and source refresh inspected. Screenshots are under `Validation/Reports/OpenClickyAdoption/`.
- Full validation sweep and iPhone build results are recorded in `validation-results.md`. Hardware/provider acceptance is distinct from compilation and synthetic checks.

Composio link response contract: [Create a new authentication link](https://docs.composio.dev/reference/api-reference/connected-accounts/postConnectedAccountsLink).

## Gmail owner handoff

The earlier blocked Google sign-in still needs the owner's custom OAuth configuration. Composio's [Gmail guide](https://docs.composio.dev/kb/guide/toolkits-gmail) calls for creating the auth config with custom OAuth credentials before starting a connection. In the same Composio project as the deployed connector:

1. Create a custom Gmail OAuth auth config with the owner's Google client ID and secret. Keep the secret in Composio's credential form; do not paste it into chat or repository files. Use only the reviewed read scopes required by this connector.
2. Copy the exact `oauth_redirect_uri` from that config into the Google OAuth client's authorized redirect URIs. [Composio's custom-auth guide](https://docs.composio.dev/docs/auth-configuration/custom-auth-configs) stresses an exact match; API-version defaults can differ.
3. If the Google project is in Testing, add the intended account to its test users. Google documents [audience/test-user limits](https://support.google.com/cloud/answer/15549945?hl=en) and [restricted Gmail scopes](https://developers.google.com/workspace/gmail/api/auth/scopes). Public production access can require verification. Do not bypass a blocked-app screen.
4. Configure this custom auth config's ID for `gmail` on the existing connector, redeploy, then start a fresh Suzzme connection. Retired/blocked sign-in links should not be reused. Verify an active account, opt into its inbox resource, then refresh sources and prepare the summary.

This owner credential/consent handoff was not completed automatically. The downloaded OAuth secret was not copied into this repository.
