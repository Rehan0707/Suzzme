# URL-only Share handoff

`SuzzmeShareExtension` is a native Share extension for iPhone/iPad and Mac. Safari can hand the selected URL to this extension through the system Share menu. It is separate from Chrome's signed Native Messaging pairing. There is no Safari tab monitor, private API, content script, automatic page read, or iOS responder-chain trick to launch the containing app.

The extension accepts one HTTPS DNS-name URL, shows its canonical form, and requires **Send URL to Suzme**. It never requests text, images, HTML or file contents. Credentials in URL authority, local addresses, IP literals and WhatsApp links are rejected; query strings and fragments are removed. This handoff does not ingest chat history or grant a provider account permission.

A dedicated, non-backed-up App Group queue holds at most ten records. Each is one URL, a random ID, schema version and share timestamp. Files are atomic, bounded, protected on iOS and guarded by a nonblocking cross-process lock. Repeated URLs are idempotent. Records expire for use after ten minutes; expired files are removed on the next app/extension queue operation, without promising exact background deletion. Unknown schemas remain untouched until explicit queue clearing. User actions recheck freshness and the exact reviewed record before using it. Nothing enters Daily Summary or Personal Memory automatically.

After sending, open **Suzme → Sources → Shared webpages**. Open the URL in the browser, review a question about a supported GitHub/Notion resource, or explicitly choose text/a screenshot for local understanding. Provider reads still need independent account permission and an explicit Send action. LinkedIn remains shared-content-only. Arbitrary watched-page fetching remains paused for connection-level network safety; this extension does not bypass it.

## Owner setup

1. Provision the existing app and the new `rehan.Suzzme.Share` extension with your real signing team for both destination platforms. Existing app/widget identifiers are preserved.
2. Create an App Group through Apple's supported developer configuration. Add its actual entitlement to **both the main app and Share extension** using Signing & Capabilities. Use the configured iOS/macOS entitlements files for the extension; keep all existing main-app entitlements. A dedicated group is preferable to granting the extension unrelated browser-helper access.
3. Set the project build setting `SUZZME_SHARE_APP_GROUP` to the actual provisioned group identifier, using SDK-specific overrides if needed. Both bundles expose it as `SuzzmeShareAppGroup`. Empty configuration intentionally leaves Send disabled and the app queue unavailable; there is no fallback to an unprotected or fabricated group.
4. Rebuild/sign/install the containing app with its embedded Share extension. Enable the extension in the system Share/Extensions controls if needed. On iPhone/iPad, use Safari Share → More/Edit to expose Suzme; on Mac enable the Share extension in System Settings if it is not listed.
5. Physically verify Safari → extension preview → Send → open app → Sources → Shared webpages on both platforms. Verify cancellation, missing setup, repeated sharing, expired links, queue-full/recovery and disconnecting provider accounts. A compiled `.appex` and temporary-store tests do not prove this signed App Group path.

App Groups are device-local. This is not cross-device delivery. The extension instructs the user to open Suzme manually; it does not claim an unsupported automatic app launch.

## Verification

Run `zsh Validation/shared-web-handoff-check.sh` for the real queue/policy with isolated temporary directories. `native-platform-runtime.py --output /tmp/<new-qa-folder>` copies all app, widget, Share and speech package sources for native UI acceptance under an isolated bundle ID. Source hashes include the shared/extension/package Swift files. No production services or app entry point are replaced.

The approach follows Apple's [app-extension sharing guidance](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html), [Share activation keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AppExtensionKeys.html), and [App Group configuration](https://developer.apple.com/documentation/xcode/configuring-app-groups).
