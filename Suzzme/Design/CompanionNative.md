# Companion native surfaces

Companion (01) is implemented in the iOS app's existing ActivityKit extension and a new `systemSmall` WidgetKit widget. The browser lab remains a design reference; native surfaces consume actual app state.

## Behavior

- ActivityKit owns compact, minimal, expanded and Lock Screen geometry. The Lock Screen card uses standard 14 point margins, semantic typography, a static recognizable cloud character and one deep link to the related app content.
- Thinking/checking/speaking reflect the existing assistant and voice controllers. Summary playback now exposes an opaque output ID so playback without a conversation request can own a real Live Activity. Preview audio never owns one.
- There are no fabricated percentages, source counts, continuous waveform meters, polling loops, or repeating avatar animations in the extension. Phase changes use bounded transitions. Reduce Motion, reduced-luminance Always-On, and stale content disable movement.
- Success ends an owned ActivityKit session with a generic “Session complete” state; playback completion does not imply a newly generated summary. Its final card can remain on the Lock Screen for 15 minutes. Cancellation retires immediately. User-dismissed sessions are not resurrected.
- A cached summary does not start a new Live Activity. The client no longer registers push-to-start tokens. The updated delivery source sends completed summaries as ordinary notifications, or ends an existing activity with a retained final card. Legacy delivered activities are also ended on app reconciliation. The backend source change is prepared locally, not deployed; remote delivery still depends on signed push configuration.
- The iPhone app is a companion: its summaries are prepared on the Mac. This change does not invent an iPhone summary engine or remote generation progress.
- The square widget is a Home Screen widget. WidgetKit controls its size, standard content margins, rendering mode and refresh schedule. It gets status-only timeline entries at meaningful changes, with scheduled expiry entries. It never fetches accounts or runs the assistant.
- Session snapshots expire after three minutes, then fall back to a still-fresh summary or the empty state. Summary availability expires using the app's existing two-hour briefing freshness. New sessions with the same phase have distinct opaque identities, so deduplication cannot keep an expired previous session.
- The shared App Group payload contains phase, session token, appearance and dates. It contains no account identifiers, credentials, source details, transcripts, summary text, contact details or action arguments. Account clearing immediately removes the snapshot and requests a widget reload.
- Presence settings offer a Live Activities switch. Switching it off ends activities and omits activity push tokens from subsequent account registration. System authorization remains authoritative. The settings style example uses regular app UI rather than a fake system Island.
- Summary links survive cold launch and authentication, then select the Summary tab. The app's existing account checks still control access to private content.

## Signing and device acceptance

Both iOS app configurations and the extension declare `group.rehan.Suzzme.presence`. A physical-device provisioning profile must include that App Group; Xcode automatic signing is configured. Missing App Group access gives the widget an empty state instead of falling back to an unrelated preferences domain.

Debug builds without code signing verify compilation but do not establish App Group provisioning, remote push, physical Dynamic Island geometry, Always-On behavior or VoiceOver acceptance. WidgetKit may defer reloads and does not guarantee instantaneous updates.

`Validation/companion-native-render.sh` builds an isolated iOS Simulator review app from the shipping view source. `CompanionNativeRender.swift` exports Light, Dark and Accessibility-size component sheets and actual card heights. These are native SwiftUI renders of sample states, not evidence of an ActivityKit request or system delivery. Production app entry points are not replaced. Simulator installation stalled during this run, so those iOS exports and actual system presentation were not verified. The fallback `companion-native-host-render.sh` rendered the exact shared production views on macOS in light and dark appearances. These host sheets are visual review evidence, not iPhone geometry or system-delivery evidence.

## Apple references

- https://developer.apple.com/design/human-interface-guidelines/live-activities
- https://developer.apple.com/design/human-interface-guidelines/widgets
- https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
- https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities

Validation logs and render evidence are saved under `Validation/Reports/CompanionNative/`. Check that folder for the actual results and limits of this run.

## Verification — 3 November 2026

- iOS app and widget extension: Debug simulator build passed, code signing disabled.
- macOS app: Debug build passed.
- Focused checks: Live Activity/widget 65/65, voice lifecycle 34/34, companion push 39/39.
- Native host light/dark sheets visually inspected; project and entitlement plist lint passed.
- Broader regressions retain four failures in unchanged behavior/expectations: step9 live-context routing, step12 recovery summary retention, and two UI recovery source checks expecting older tab/settings labels. These are not claimed as passing.
- Physical-device signing, App Group sharing, APNs delivery, VoiceOver, Always-On and system-rendered Dynamic Island/Lock Screen acceptance remain unverified. No backend deployment was performed.

Shared production layout: `PresenceShared/SuzzmeCompanionSurfaces.swift`; character and state styling: `PresenceShared/SuzzmeCompanionStyle.swift`. WidgetKit configuration remains in the extension target.
