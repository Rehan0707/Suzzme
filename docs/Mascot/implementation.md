# Suzzme cloud companion

Implemented 24–25 October 2026 in the existing shared SwiftUI application. The supplied PNG is the source of truth; the in-app character uses supplied artwork and no animation dependency is used. The separately generated app icon uses that same character as its reference. Existing uncommitted changes were retained.

## Component and assets

`Suzzme/Suzzme/DesignSystem/Components/SuzzmeMascot.swift` defines `SuzzmeMascot(state:size:isAnimated:)`, with optional Presence animation preference, measured capture level, speech progress, welcome/rest poses, accessibility label and tap callback. Display sizes are bounded to 16–320 points; invalid audio and size values cannot produce invalid geometry.

The existing `SuzzmeAssistantState` remains the only assistant lifecycle. `SuzzmeMascotPose` is a value projection of that lifecycle, with no event subscriptions, task execution or microphone authority. Welcome/rest poses apply only while the real assistant is idle.

The original transparent 1254 × 1254 PNG is unchanged in:

- `Suzzme/Suzzme/Assets.xcassets/SuzzmeMascot.imageset/mascot_idle.png` (runtime catalog).
- `Suzzme/Design/Character/SuzzmeMascot-Original.png` (retained reference).

Native eyelids overlay the supplied artwork. Real speech uses the supplied matching 16-frame GIF when motion is allowed, with a small progress-driven speech opening as the loading/failure fallback. The greeting uses a slight hand flutter from a clipped copy of the same artwork. No nonexistent expression filenames are referenced. Themes continue to color the surrounding intelligence surface; the character stays blue in light and dark appearances. The former three-stroke geometry has been removed. Legacy `SuzzmeFace` layout callers now render the cloud; sign-in, settings, startup recovery, the Mac menu bar, Share extension and system activity also use the cloud. The menu-bar image keeps its original colors rather than template tinting.

## Real state and motion

| Presentation | Actual input | Behavior |
| --- | --- | --- |
| Idle | `.idle` | Gentle breathing and an occasional blink. |
| Greeting | Onboarding introduction / empty assistant opened while idle | Brief entrance and hand flutter, then neutral idle pose. |
| Listening | Voice capture `.listening` | Breathing/pulse plus bounded real capture RMS; existing microphone status and cancel remain visible. |
| Thinking | Transcribing, understanding, context, reasoning, planning, acting | Restrained continuous floating; existing phase text distinguishes these operations. |
| Speaking | Real speech start/progress callbacks | Matching supplied speaking GIF, shown only during real speech. The static fallback articulates from real word/playback progress. This is activity synchronization, not phoneme-level lip sync. |
| Success | Existing task/speech completion `.success` | Brief lift, then the existing state controller returns to idle. |
| Sleeping | Explicit idle rest pose | Closed eyes and slower breathing; active work always overrides it. Inactive scenes stop motion. |
| Error | Existing recoverable failure `.error` | Reassuring original smile, slight pose change and existing attention/recovery text. |

SwiftUI tasks cancel on disappearance, motion policy changes and state changes. Sleep/wake changes restart only the breathing/blink task. Each task resets only the animation values it owns. Native scroll visibility pauses offscreen motion on iOS 18/macOS 15 and later; back-deployed geometry observation covers the iOS 17/macOS 14 deployment floors. Minimal, Reduce Motion, inactive scenes and `isAnimated: false` stop motion. Hidden cursor/notch panels release their hosted views. The retained menu bar draft uses a static mascot.

The mascot exposes a semantic accessibility label/value when meaningful. Shared status rows hide the redundant artwork from VoiceOver and keep the existing status text. Optional mascot interaction uses a native button with a minimum 44-point target. Existing Dynamic Type layouts, cancel/review controls and privacy boundaries are preserved.

## Integration

Updated Home (128-point companion), Ask's shared status (48-point), in-app presence (44-point), compact Mac presence (existing geometry), splash/onboarding, briefing loading, Presence settings preview, Mac menu bar and cursor companion. Shared presence automatically supplies the Mac notch/fallback surface. Existing navigation, authentication, source permissions, confirmations and request execution are retained.

Lifecycle fixes required by real state integration:

- iOS audio interruption now retires both native speech and natural speech preparation/playback.
- Speech preparation remembers the current presentation revision. Stopping it settles only that owned presentation, preserving a newer interaction.
- The existing assistant controller rotates a presentation revision on transition/reset. A late Brain Lab extraction cannot reset or publish over a newer request, voice session or same-session presentation.
- Existing utterance/player/request ownership still rejects late callbacks. Success/error settlement remains cancellation guarded.

## Target scope

The project has one shared iPhone/iPad/macOS application, an iOS Presence widget and a native Share extension. There is **no iPhone Duo target, configuration or specialized display API** in the supplied repository. The existing adaptive iPhone layout uses the same mascot. No separate Duo build or hardware acceptance is claimed. See [inspection](inspection.md).

## Verification

Fresh results and any remaining acceptance limitations are recorded in [validation](validation.md). `Validation/mascot-render.sh` builds an isolated native preview app with the production asset catalog and renders labelled static state fixtures; it does not simulate microphone, assistant or speech events. New Swift Testing cases cover presentation precedence, invalid audio values, motion gates and stale extraction ownership. `MascotRuntimeTests` uses the unchanged production app in a separate test installation for Home accessibility and a real typed request.

## Supplied color and speaking archives

The two additional user-provided archives were inspected as media, with only flat PNG/GIF/MP4 members extracted into `Suzzme/Design/Character/Supplied/`. They contain eight transparent 1254-point character PNGs and eight matching opaque 520-point GIFs (16 frames, 90 ms per frame, 1.44 seconds per loop). The blue MP4 and contact sheet remain reference artifacts; native GIF playback avoids a separate video/audio player.

Settings → Presence → Character offers Blue, Pink, Red, Orange, Yellow, Green, Teal and Purple using the existing preference storage. Blue remains the default identity. Each selected color uses its supplied PNG and matching speaking GIF, with no automatic color changes based on activity. Brand marks and the widget retain the original blue identity.

`SuzzmeMascotArtwork.swift` performs bounded ImageIO decoding off the main actor. One shared cached sequence serves concurrent surfaces; replacing the selected color retires the previous cache/load. GIF white backgrounds are masked using the supplied transparent PNG silhouette, retaining opaque eye whites. The timed animation subtree exists only during actual speaking, visible/active scenes and permitted motion. Cancellation, speech completion, Minimal and Reduce Motion immediately restore static artwork.

The runtime catalogs for the app, Share extension and widget each contain the original cloud asset, so extension presentations do not rely on an unavailable containing-app resource. All eight platform app-icon PNGs have been replaced with opaque RGB exports of `SuzzmeAppIcon-Master.png`. See [icon provenance](icon-provenance.md).
