# Distribution readiness — NOT RELEASE READY

The unsigned Debug builds establish compilation only. Signing, archive validation, provisioning, notarization, App Store review, installed browser communication and real accounts remain unaccepted.

| Area | Current fact / remaining acceptance |
|---|---|
| Application identity | `rehan.Suzzme`; existing team `VA9D6XP354`; version 1.0/build 1. Confirm intended production ownership/versioning before distribution. |
| Extension identity | `rehan.Suzzme.Presence`; iOS Live Activity widget target exists. Accept signed extension embedding and device lifecycle. |
| Deployment | iOS 17 / macOS 14; Foundation Models guarded for version 26 and capability availability. Test oldest supported OS and unavailable-model fallback on real devices. |
| Dependencies | Existing pinned GoogleSignIn 10.0.0, MCP Swift SDK 0.12.1 and transitive packages; no additional third-party dependency added. License/privacy/update review required. |
| macOS sandbox | Release entitlement file enables sandbox, audio input, outgoing network, user-selected read-only files, Calendar/Contacts. Review actual signed entitlements and each purpose. Do not remove sandbox for browser IPC. |
| Hardened runtime | Project configured; validate final nested code, installer, notarization and stapling with a real Developer ID distribution build. |
| App Groups / browser host | No reviewed/provisioned App Group or signed native host in this build. Browser pairing/deployment cannot be released. |
| Google OAuth | Placeholder public client IDs/reversed IDs; configuration and Google consent/API approvals required. No embedded client secret permitted. |
| URL schemes | Existing `suzzme` handoff and Google reversed schemes; validate real installed callbacks, duplicate/expired requests and hostile deep links. |
| Privacy manifest | App manifest declares UserDefaults CA92.1 and no tracking/collected data. Confirm all accessed APIs/transitive SDKs and actual distribution practices; this pass is not App Store privacy approval. |
| Permissions | Calendar/Reminders/microphone/speech/screen/input-monitoring descriptions and signing behavior need actual supported-device validation. |
| Background behavior | Local notification routing, not guaranteed exact-time fresh AI execution. Public copy must preserve this distinction. |
| Browser packaging | Chrome source/JS tests exist; production extension ID, host installation, signed distribution and clean upgrade/uninstall are missing. Safari extension not implemented. |
| Crash/performance | No external analytics/crash SDK added. Collect only approved redacted local diagnostics; sustained battery/thermal/model/audio measurements remain pending. |
| Accessibility | Automated/layout checks and sampled rendered UI do not replace full VoiceOver/keyboard/large-type hardware acceptance. |

Release gate: resolve blocker register, pass live-account tests, finish installed browser/custom MCP scope or explicitly exclude them from release, accept real iPhone/Mac audio/Presence, measure sustained performance, then validate signed archives and distribution/privacy requirements. Do not promote a compiler PASS to release acceptance.
