# Suzzme · Step 1

A local-first SwiftUI foundation for iPhone, iPad, and Mac. Open `Suzzme.xcodeproj` and select the **Suzzme** scheme. The existing single multiplatform application target is preserved; choose an iOS simulator or My Mac as its destination.

## Requirements

- Xcode 27 (validated), Swift 6 language mode
- Minimum iOS 17 / macOS 14
- No dependencies, network access, accounts, or permissions

## Architecture

- **App/** owns dependency composition, observable main-actor state, and window-local routing. `AppEnvironment` loads the service, handles cancellation/errors, and refreshes stale daily data on foreground entry.
- **Core/Models/** contains Codable, Sendable value models. IDs survive encoding. Dates are absolute instants; the mock uses the supplied calendar to create local schedule times.
- **Core/Intelligence/** exposes one async throwing `IntelligenceService` boundary. `MockIntelligenceService` is injected at composition. Future Foundation Models integration belongs behind this boundary and must availability-check its own framework/device requirements.
- **DesignSystem/** contains adaptive color assets, native semantic typography, spacing, bounded page layout, cards, rows, the shape-based mark, and in-app halo.
- **Features/** owns Today, Briefing, Memory, Sources, History, and Settings. Details are progressively disclosed with navigation. Future companion affordance explains its inactive state.
- **Platform/** owns compact iPhone tabs, regular-width iPad navigation, and native Mac sidebar navigation. Mac settings use a Settings scene and the standard Settings command.

Views read shared observable state; there is no view model per screen, global singleton, or DI framework. Navigation state belongs to each window. No empty infrastructure modules are introduced. Add persistence, inbox, and integrations when their behavior is defined.

## Product boundaries

All content is explicitly demonstrative. Five active sample items and one completed item form the daily briefing; the attention count deduplicates items and excludes completed entries. Times are illustrative for the entire sample day, including after those times have passed. There is no source access, inference, recording, task mutation, persistence, or real memory. Data resets when the process restarts. The user name is the requested sample persona, Rehan.

When adding SwiftData, keep these service-facing value models and map them to persistence records with the same UUIDs. Introduce a model container at app composition rather than putting persistence queries in every view. No persistence abstraction is needed yet.

## Design and accessibility

White canvas, #DAB1DA and #CBC3E3 decorative halo colors; darker purple text in light mode provides contrast. Dark appearance has independently chosen canvas/surface colors. Native system text scales; accessible sizes stack timed rows vertically. Meaning is carried by text as well as color. The halo respects Reduce Motion, Reduce Transparency, and foreground state; it is entirely inside the app. No Dynamic Island or notch access is implied.

Previews: Home light/dark/accessible type, halo states, item card, and Mac layout. The supplied Suzzme icon is installed for iOS and macOS; the in-app logo remains replaceable SwiftUI geometry.

## Dynamic Island and MacBook notch

`SuzzmeHalo` is an in-app visual anchor near the top centre of the window. It deliberately does not claim access to the physical Dynamic Island or MacBook notch. iOS only presents an app in the real Dynamic Island through a user-visible Live Activity, which requires an ActivityKit extension and a meaningful active activity. macOS exposes no public API to tint, replace, or draw around the hardware notch. A future Live Activity should reuse Suzzme's presence states (`idle`, `listening`, `thinking`, and `speaking`) for its own Apple-controlled Dynamic Island presentation.

## Validation

Run `./Validation/check.sh` for independent checks of counts, IDs, DST-safe local times, Codable round trips, service errors and same-day load caching.

```sh
xcodebuild -project Suzzme.xcodeproj -scheme Suzzme -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Suzzme.xcodeproj -scheme Suzzme -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

These unsigned builds validate compilation, not distribution signing. Before release, add final app icons and run physical-device VoiceOver and accessibility acceptance checks.
