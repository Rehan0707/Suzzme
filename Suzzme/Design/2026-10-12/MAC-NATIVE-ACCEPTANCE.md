# Native macOS acceptance — 12 October 2026

The development-signed production `rehan.Suzzme` app genuinely launched with its App Sandbox entitlement, original `@main`, production environment, persistence, and services. Its owned Home and notch windows were captured and inspected. The Home is readable, uses native navigation and window chrome, and displays actual daily context. The notch displayed the real “Daily Summary ready” state. These captures establish startup/rendering evidence; they do not establish voice or keyboard activation.

- [Production launch metadata](evidence/mac-production-launch/production-runtime.json)
- [Production Home](evidence/mac-production-launch/suzzme-window-1508.png)
- [Production notch](evidence/mac-production-launch/suzzme-window-1509.png)
- [Bounded acceptance summary](evidence/mac-acceptance-limits/summary.json)

The separate copied app uses bundle ID `dev.suzzme.NativeAcceptance`, unchanged production entry/environment, and dev-scoped sandbox/keychain metadata. Its app and UI-test target compiled. The recorded source snapshot matched all 341 production source/resource files. Signing was tested locally with the complete sandbox/audio/network/calendar/address-book/selected-file/keychain capabilities retained; no new profile was generated.

Mac XCTest could not initialize automation mode with either the locally signed or existing development-signed runner. Both executions timed out before any test case. The copied dev app also failed to spawn through LaunchServices (`NSCocoaErrorDomain 256`, underlying `RBSRequestErrorDomain 5`). Current development-certificate trust verification returns `CSSMERR_TP_NOT_TRUSTED` for both bundles; the original production process had already launched and remains available. Certificate trust and system permissions were left unchanged. No isolated light/dark image was produced or presented as successful evidence.

The external driver has Screen Recording authorization but no Accessibility authorization. It captures only the supplied app’s own windows, records executable and bundle identity, checks App Sandbox before launch, and requests no TCC access. It cannot establish interactive acceptance on this host. Mac navigation clicks, repeated conversations, physical Control + Option, microphone/TTS, and haptics remain unverified.

Targeted implementation checks passed: native menu/status-item lifecycle 48/0 and the exact global-shortcut monitor callback/reducer 79 checks. Their environment/view and OS syscall doubles are identified in the scripts and evidence; these results are not physical keyboard or voice acceptance.

Failure results remain separate at `/tmp/SuzzmeNativePlatformMacAcceptance-20261012-runtime.xcresult` and `/tmp/SuzzmeNativePlatformMacAcceptance-20261012-development-runner.xcresult`. Logs are retained in `evidence/mac-acceptance-limits`. No user app, preference, data, TCC grant, or certificate trust was reset.
