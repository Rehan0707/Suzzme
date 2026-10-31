# Render deployment — prepared, not yet published

Use a dedicated private repository containing **only** this connector bundle. Do not upload the full Suzzme app, `.env.local`, tokens, Xcode files or validation reports. `prepare-render.mjs` copies a fixed allowlist into `../Release/ConnectorServer-render/` with file hashes; it refuses to merge an existing directory. No deployment command is run by bundle preparation.

The blueprint explicitly selects Render's free plan, Node 24, Singapore, manual deployment and HTTPS health checks. There is no database, paid plan or automatic deployment configured. Before publishing, inspect the actual account's billing and service form. Render free services sleep after 15 minutes idle and may take about a minute to wake. Suzzme's requests can time out while the service is waking. Check `/healthz`, wait for a response, then retry in the app. Daily production use needs an independently approved always-on plan; no paid subscription is authorized here.

## First deployment

1. Sign in to Render yourself. Account terms, CAPTCHA, provider permissions and any new Git-provider access must be reviewed before acceptance. Existing Composio credentials do not sign you into Render.
2. Review the connector-only bundle. Authorize the specific repository upload/Render access before publishing. If using a private Git repository, restrict Render access to that repository.
3. Create one Node web service from the bundle. Use `render.yaml`, or set the free plan, Node 24, build command from the blueprint, start command `node hosted.mjs`, and health path `/healthz`. Do not add secret files to the repository.
4. The first deploy runs in **setup-required** mode with no project key and no account access. Every route except GET `/healthz` returns 503. A successful Render health check proves that the process runs; it does not prove Composio configuration or account access. Render assigns the public HTTPS origin. No custom domain is required.

## Activate the connector

5. In Composio's project General settings, set OAuth user verification to `https://YOUR-RENDER-HOST/oauth/verify`. Keep two-factor authentication enabled. This changes authentication routing and needs explicit approval before saving.
6. Create reviewed auth configs for the desired providers. Start with one test account and minimal supported permissions. Do not accept GitHub's seven default scopes as read-only; `repo` includes writes even though Suzzme's bridge exposes reads only.
7. With specific approval to transfer the server credentials to Render, add private environment variables in its service dashboard: `COMPOSIO_API_KEY`, `SUZZME_CONNECTOR_URL` (the allocated HTTPS origin), `SUZZME_USER_ID`, `SUZZME_DEVICE_TOKEN`, `SUZZME_AUTH_CONFIGS`. Finally set `SUZZME_CALLBACK_VERIFIER_CONFIGURED=yes` only after step 5 actually succeeds. Local key storage approval is not permission to transfer it to a hosting provider. Never paste secrets into chat or the Git repository.
8. Redeploy. GET `/healthz` should return `{"status":"ok"}`; `/v1/accounts` without a bearer token should return 401. Confirm valid device authentication, matching owner/config and live account state separately. Setup-required mode never activates a connection or fabricates a callback-verification flag.
9. Enter the HTTPS origin and separate device token in Suzzme. Authorize the selected provider and complete its confirmation code. Test one known source, answer, cancellation and revocation before personal use. Data flows through Render and Composio; local AI inference remains separate. Composio's inspected project stores API payloads in logs while Zero Data Retention is off. Check Render access-log/query retention too; OAuth verifier URLs contain temporary secrets. Do not enable request-body logging.

`hosted.mjs` binds Render's assigned port on `0.0.0.0` only when the Render runtime marker is present. `server.mjs` retains loopback-only local startup. In-memory confirmation codes/attempts expire after ten minutes and are lost on service restart; restart the sign-in flow if interrupted. Use one instance; pending authorization is not shared across replicas.

References checked 20 October 2026: [Render web services](https://render.com/docs/web-services), [Blueprint specification](https://render.com/docs/blueprint-spec), [free service limitations](https://render.com/docs/free), [Composio scoped keys](https://docs.composio.dev/reference/authenticating-to-composio/project-api-key-permissions).
