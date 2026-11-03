# Suzzme Companion lab

The selected Companion (01) design, extended to a Lock Screen Live Activity and a square Home Screen widget. Open http://127.0.0.1:4180/.

```sh
cd dynamic-island-lab
python3 -m http.server 4180 --bind 127.0.0.1
```

No installation, build step, external fonts, or remote scripts. This is a browser design prototype with fictional content, not an installed WidgetKit extension. The native app is not modified.

## Current experience

- `index.html`, `companion.css`, `companion.js`: the Companion lab.
- Two original iPhone 18 Pro CSS mockups: Lock Screen and Home Screen, using Apple's 402 × 874 pt display proportions derived from 1206 × 2622 pixels at 3×. Device radii and camera geometry are illustrative; this is not an official Apple asset or a hardware screenshot.
- Lock Screen banner: 374 × 152 pt, 14 pt inner margins, one contextual action. Cancel/Stop ends the simulated session. Read summary opens a fictional app destination; private summary text is absent from the public surface.
- Square widget: illustrative 170 × 170 pt canvas, 16 pt margins, whole-surface app destination. Native WidgetKit determines actual device-dependent sizing and margins.
- Presets: Summarizing, Thinking, Speaking, Summary ready. Presets simulate a new widget timeline entry.
- Full playback: 0–7 seconds summarizing, 7–12 thinking, 12–20 speaking, then completion. Play/pause/resume, replay moment, reset, scrub, and 0.5×/1×/2× speed are supported. Reset returns to no active Live Activity.
- The widget updates at meaningful state changes and manual refreshes. It has no live percentage or continuous audio meter. Refresh snapshot simulates a WidgetKit timeline reload. The Live Activity tracks the session's simulated progress.
- Content fades last 250 ms. A state change or Replay moment triggers a finite thinking/speech cue of up to 1.2 seconds. No animation loops are used. Updates are illustrative, not real microphone input or engine measurements.
- Always-On dims the Lock Screen and disables animation cues. Reduce Motion, larger text, increased contrast, light surfaces, dark surfaces, accessible control labels, and keyboard operation are included.
- Playback advances only while visible. Hidden-tab entry cancels cues and does not accumulate elapsed time. Pausing or resetting cancels in-flight cues.

## Native handoff

Reuse the existing `SuzzmeSessionActivity` and assistant lifecycle; map summary processing to gatheringContext/reasoning, speech to speaking, and completion to summaryReady/success. A shipped app must request/update/end ActivityKit from real engine changes and honor consent, authorization, stale dates, authentication, and error recovery. A completed card can remain on the Lock Screen for a short dismissal window after ActivityKit ends the session.

Use the existing native cloud character artwork. In SwiftUI, provide an `ActivityConfiguration` Lock Screen body, a separate systemSmall WidgetKit configuration and timeline provider, semantic text styles, system content margins, an adaptive container background, and App Intents only for essential actions. A square widget is a Home Screen widget; iPhone Lock Screen accessory widgets have separate system families. Use `widgetURL`/`Link` to the session or summary destination and keep private detail behind app authentication.

Content updates may animate for at most two seconds. Use bounded content transitions and still status indicators rather than repeating GIFs or continuous audio visualization. Respect accessibilityReduceMotion and isLuminanceReduced. Actual update scheduling and transition timing belong to iOS. The browser controls intentionally expose states for design review and are not native scheduling guarantees.

The current browser preview does not constitute native, simulator, VoiceOver, Dynamic Type, or physical-device acceptance. No Swift build or native validation suite was run for these HTML/CSS/JS-only changes.

## Original island exploration

`island-study.html`, `style.css`, and `app.js` preserve all three original Dynamic Island concepts, including the minimal/compact/expanded variants. The header's Island studies link opens this exploration.

## Research

- [Live Activities HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities): finite tasks, privacy, standard 14 pt margins, useful actions, Lock Screen layouts, and dismissal behavior.
- [Widgets HIG](https://developer.apple.com/design/human-interface-guidelines/widgets): system small family, standard 16 pt margins, glanceable content, whole-widget deep links, and timeline-based updates.
- [Animating data updates](https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities): maximum two-second animations and no animation on reduced-luminance Always-On displays.
- [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities): Live Activity lifecycle and 160 pt maximum Lock Screen height.
- [iPhone 18 Pro specifications](https://www.apple.com/iphone-18-pro/specs/): display proportions.
