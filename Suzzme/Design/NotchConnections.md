# Browser app suggestions in the Mac notch

Suzzme’s existing signed browser bridge identifies supported active HTTPS app tabs and delivers service metadata to the app-owned notch panel. It does not read page text for discovery. The updated panel uses bundled app artwork, supported-use hints, and No / Not now / Connect. Connect routes to that service’s existing setup. Notion browser invitations now use Composio setup; direct Notion setup remains available elsewhere.

After Composio completion succeeds, the workspace re-fetches accounts and verifies the returned account is active before posting a transient 12-second connected notice. OAuth redirects and cached account metadata do not independently produce success. The notice respects ongoing assistant interactions and can be dismissed. Summary intake is a separate opt-in.

Outlook discovery permissions now cover both outlook.live.com and outlook.office.com. Browser routes canonicalize GitHub repository case. Existing freshness, anti-replay, snooze and No controls remain in the handoff owner; cooldowns now persist on this device (see OpenClickyAdoption.md).

## Runtime prerequisites

Automatic detection is not installed or active in this workspace’s default build: BrowserBridge.json intentionally has no signing group or extension identifier. Configure the genuine installed Chrome extension ID and provisioned App Group, build with SUZZME_BROWSER_CONFIG, install the reviewed Native Messaging manifest, enable the helper and pair it, then enable Automatic tab prompts in the extension. See BrowserExtension/README.md for the existing procedure. Settings now explains the flow. No identifiers or permissions are fabricated.

Chrome is the currently supported target. Safari in the Clicky reference requires a separate Safari adapter, which this change does not implement. Personal WhatsApp uses the separate local-chat setup, rather than Composio’s Business-only API.

## Validation

- Signed macOS Debug build passed.
- Browser detection: 28 passed.
- Browser handoff Swift: 131 passed.
- Browser JS / production popup handler: 98 passed.
- Native Composio client: 61 passed using fictional transport fixtures.
- Production SwiftUI render sheets reviewed for Gmail invitations and verified-success samples, light/dark/accessibility and notch/fallback geometry. Samples are visual evidence only, not a claim of connected accounts.
- Real extension-to-notch acceptance remains pending signed configuration and browser installation. The prior Google-managed OAuth block remains separate from this presentation work.

## Native detection and expanded coverage — 4 November 2026

A native event-driven adapter now observes supported frontmost browsers (Safari, Chrome, Brave, Edge and Arc). The switch is in Sources → Browser suggestions. It requires explicit Accessibility permission and defaults off. It listens to application activation and accessibility window/focus/title events, debounces reads and bounds traversal/time. Only the document URL is inspected; page text, field values, screenshots and browser history are not read. The domain/path is used locally to identify the integration and only its service ID reaches the existing invitation flow. Private-window URLs can also be exposed by the browser; the setting states this. Turning the setting off detaches observers and retires its pending invitation.

Native URL availability differs by browser/version; if the browser does not expose it, status reports that condition and the paired Chrome extension remains a fallback. This does not disable or bypass native helper signature checks. Accessibility is a broad macOS permission despite Suzzme’s narrow URL-only read. No system permission was granted automatically.

BrowserExtension/app-catalog.json is the reviewed source for 32 available integrations. generate-app-catalog.py generates native and JS tables plus optional extension origins. Native/browser detection covers all services in ProviderReadRecipe and the existing GitHub/Notion/Linear/Composio/local WhatsApp flows. Apps marked catalog-only have no false connection invitation. Providers with existing direct setup continue using it; Composio supports only its implemented/configured provider recipes.

A route parser defect rejected service-only URLs without query parameters; this is fixed, including roundtrips for mixed-case provider IDs. Expanded native catalog checks: 117 passed; JS catalog checks: 139 passed; existing Swift/JS handoff checks: 131/98 passed; signed-message engine: 57 passed. Signed macOS build passed. Real Safari/Chromium event delivery remains unverified until Accessibility is granted. The installed app’s UI reported that permission as unavailable during this run.

The final signed build was installed and launched. Sources → Browser suggestions was opened in the native UI and the requested detector switch enabled. Its live status reports Accessibility access is required. User must grant Suzzme Accessibility in System Settings and select Check Access before live URL delivery can be verified. No Accessibility grant was performed by the agent. Final native build and project plist lint passed.
