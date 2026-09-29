# Suzzme

Native, local-first assistant for iPhone, iPad and Mac. Open `Suzzme.xcodeproj`, select **Suzzme**, then an iOS simulator or My Mac. One shared application target; Swift 6; minimum iOS 17 / macOS 14. Current validation uses Xcode 27 / Swift 6.4. There are no third-party package dependencies.

The product intent and non-negotiable privacy, intelligence, action, and Presence principles are recorded in [PRODUCT_VISION.md](PRODUCT_VISION.md).

## Ownership

- `AppEnvironment` composes services and owns main-actor presentation state. `SuzzmeCore` remains the single request coordinator.
- `Core/Intelligence` uses availability-checked Apple Foundation Models with deterministic local fallback. Generated text has no mutation authority.
- `Core/Context` reads bounded, permitted current context. EventKit remains authoritative over memory for Calendar and Reminders.
- `Core/Actions` owns typed planning, deterministic resolution, confirmation, commit authorization, execution and verification. Voice, views, Presence and App Intents cannot write EventKit directly. Typed local settings also verify readback and exact request ownership.
- `Core/Memory` holds bounded ephemeral session continuity. `Core/LongTermMemory` stores selectively admitted facts and relationships in SwiftData. It does not ingest raw activity or page text.
- `Core/Information` owns normalized source observations and SourceHealth in a separate SwiftData store. Watched Links read only explicitly configured public HTTPS pages, with bounds and no crawling.
- `Core/Proactive` contains the one actor-isolated relevance, Daily Summary, opportunity and evolving Today orchestration layer. Its versioned JSON remains separate from Personal Memory and Information.
- `Core/Voice` has one session controller, on-device recognition requirement, system speech output and session ownership. Unsupported voice devices/locales retain typed use.
- `DesignSystem`, `Features`, `Platform` retain shared native SwiftUI, three compact tabs, native Mac sidebar/Settings, accessible Presence and app-owned Mac panel. No fake Dynamic Island or hardware-notch tint. Mac uses one main window so panel/hotkey ownership cannot duplicate.

## Honest capabilities

Calendar, Reminders, Contacts, microphone and speech access are optional and permission-controlled. Calendar/Reminder mutations require specific confirmation and verified readback. Public watched pages require network access; private context processing does not use a cloud LLM. Exact background timing is not guaranteed. Cross-device policy exists; transport is **not implemented**. No Gmail, WhatsApp, private Messages/Mail database access, account backend, analytics or autonomous actions.

“Daily Summary” is the product term. Validated internal Briefing types retain their names.

## Validation and acceptance

Run the scripts in `Validation/`: `check.sh`, `persistence-check.sh`, `step3-check.sh` through `step12-check.sh`, and `ui-recovery-check.sh`. `step8-check.sh` includes its Core integration suite. The optional `step12-web-probe.sh` fetches only the three public URLs named in that fixture; all other behavioral fixtures use isolated temporary stores/doubles.

```sh
xcodebuild -project Suzzme.xcodeproj -scheme Suzzme -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Suzzme.xcodeproj -scheme Suzzme -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
# Repeat with -configuration Release for both platforms.
```

Unsigned builds establish compilation, not distribution readiness. An ad-hoc Mac signature verifies generated entitlements only. See `Validation/Reports/Step12/` for current risk inventory, logs, data inventory, release limitations and hardware checklist. Historical acceptance reports are not substitutes for fresh checks. Physical acceptance for Steps 5, 7, 8, 9, 10, 11 and 12 remains **PENDING** until the documented real-device matrix is executed.

## Data and recovery

Data stays in app-local SwiftData, bounded JSON and preferences. Voice audio is not written to files. No private notification payload or production prompt/transcript logging. OS backups remain outside local deletion scope.

Malformed or future JSON stores fail closed and retain the original file. Explicit, confirmed recovery controls can reset Watched Links or proactive data/preferences; they never run automatically. SwiftData creation failures preserve the existing database and surface unavailable features rather than inventing data. Do not delete a user's store as a migration shortcut.

The privacy manifest declares app-owned UserDefaults access and no tracking. Release configuration excludes developer tools and disables development entitlement injection. Distribution provisioning, notarization/TestFlight, real permission behavior, VoiceOver, audio routing, display geometry and energy use require separate acceptance.
