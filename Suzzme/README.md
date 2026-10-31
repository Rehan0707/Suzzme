# Suzme

Native Mac assistant with an iPhone/iPad companion. The Mac connects sources and prepares AI summaries; the signed-in phone receives and reads the prepared result without a local language model or source-intake runtime. Open `Suzzme.xcodeproj`, select **Suzzme**, then an iOS simulator or My Mac. One shared application target and an iOS WidgetKit extension; Swift 6; minimum iOS 17 / macOS 14. Current validation uses Xcode 27 / Swift 6.4. Google account sign-in connects the same account across devices; Gmail source access is a separate Mac permission.

The product intent and non-negotiable privacy, intelligence, action, and Presence principles are recorded in [PRODUCT_VISION.md](PRODUCT_VISION.md).

For physical iPhone development, sign in under Xcode Settings → Apple Accounts and use the same team for the app, Share extension, and Presence widget. Debug builds use `Suzzme-iOS-Debug.entitlements` without Sign in with Apple so a Personal Team can provision the app; the Apple sign-in entry point is hidden in these builds. Release builds retain `Suzzme-iOS.entitlements` and Apple sign-in, which require an eligible Apple Developer Program team and matching provisioning profiles.

## Source layout

Paths below are relative to this directory. The application source lives inside `Suzzme/`; sibling folders hold separate packages, extensions and tooling.

```text
Suzzme/
  App/             App entry point, service composition, routing and onboarding
  Core/            Actions, context, intelligence, integrations, persistence and voice
  DesignSystem/    Shared SwiftUI components, layout, effects and theme tokens
  Features/        Screens grouped by product area
  Intents/         App Intents that use the shared app services
  Platform/        iOS, macOS and shared platform adapters
  Assets.xcassets/  Runtime colors, app icons, logo and integration brand marks
Packages/          Local Swift packages with separate manifests
PresenceShared/    Models shared by the app and Live Activity extension
ShareShared/       URL inbox shared by the app and Share extension
Validation/        Standalone checks, native tests and historical fixtures
```

Xcode uses synchronized source groups. Add app Swift files under the appropriate `Suzzme/` folder; separate package and extension sources stay in their own targets. Name screen files after their primary view: `HomeView.swift` owns Home, `DailyContextView.swift` owns Today, and `AskSuzzmeView.swift` owns the conversation screen.

## Ownership

- `AppEnvironment` composes services and owns main-actor presentation state. `SuzzmeCore` remains the single request coordinator.
- `Core/Intelligence` uses availability-checked Apple Foundation Models with deterministic local fallback. Generated text has no mutation authority.
- `Core/Context` reads bounded, permitted current context. EventKit remains authoritative over memory for Calendar and Reminders.
- `Core/Actions` owns typed planning, deterministic resolution, confirmation, commit authorization, execution and verification. Voice, views, Presence and App Intents cannot write EventKit directly. Typed local settings also verify readback and exact request ownership.
- `Core/Memory` holds bounded ephemeral session continuity. `Core/LongTermMemory` stores selectively admitted facts and relationships in SwiftData. It does not ingest raw activity or page text.
- `Core/Information` owns normalized source observations and SourceHealth in a separate SwiftData store. Watched Links retain earlier explicitly configured public HTTPS pages; network retrieval and new intake are paused for connection-level network safety. Saved history remains inspectable/removable, and future checking requires individual review rather than silently resuming old links. [Transport design and evidence](WATCHED_LINKS_SECURITY.md) distinguish socket/TLS tests from the remaining DNS and acceptance gates. Gmail uses explicitly authorized, bounded reads; body summaries require separate read-only consent. Selected Messages text is imported by the user and expires after at most seven days. macOS can also read only the WhatsApp chats the user selects from an explicitly chosen local folder.
- `Core/Proactive` contains the one actor-isolated relevance, Daily Summary, opportunity and evolving Today orchestration layer. Its versioned JSON remains separate from Personal Memory and Information.
- `Core/Voice` has one session controller and speech ownership. Mac conversations can use recognition; iPhone playback reads the Mac-prepared summary without opening microphone capture or generating a new summary.
- `DesignSystem`, `Features`, `Platform` share native SwiftUI components and state-driven Presence. Mac Home provides a focused Face, Talk action, typed composer and context choices. iPhone uses Today, Summary, and Settings tabs for its shared account and readouts; Mac offers an optional sidebar, native Settings and a menu bar window. The app-owned Mac invocation controller retains panel, shortcut and voice ownership when the main window closes.
- `SuzzmePresenceWidget` and `PresenceShared` render real ActivityKit session updates on the Lock Screen and supported Dynamic Island presentations. The system controls placement and animation. Idle decorative Live Activities and hardware-notch modification are not supported.

## Current release evidence

See [LAUNCH_READINESS.md](LAUNCH_READINESS.md) for the source and consent matrix, verification results, and remaining owner acceptance gates. Code availability does not establish live provider or distribution readiness. LinkedIn uses explicitly shared text/screenshots only. WhatsApp is a separate macOS-only local source: the user grants the folder, selects chats, and must allow macOS privacy access; there is no WhatsApp account/API connector or iOS chat reader.

## Honest capabilities

Calendar, Reminders, Contacts, microphone and speech access are optional and permission-controlled. Calendar/Reminder mutations require specific confirmation and verified readback. Watched-page network checking and new intake are currently paused for connection-level network safety; saved pages remain inspectable. An authorized Gmail connection requires network access; private context processing does not use a cloud LLM. Gmail reads up to 30 recent inbox message headers (sender, subject and date), without message bodies, attachments or mail changes. Gmail sign-in is unavailable until the build has valid platform OAuth client IDs.

On Mac, an explicit screen question requests consent before one local capture; it is not continuous monitoring. Selected Messages text can be pasted or opened from a text export for recent summaries, with local retention and deletion explained before import; this is not an SMS/iMessage account connector. Chat file attachments and continuous screen sharing are **not implemented**. Local Knowledge supports user-selected text/Markdown files and a bounded, one-time folder import (up to eight files, two folder levels, small UTF-8 text/Markdown only); it stores inspected excerpts locally and does not watch or rescan the folder. On Mac, the user may separately opt these same-day excerpts into Daily Summary. WhatsApp reads only today's bounded text from up to 20 chats explicitly selected from the chosen local WhatsApp for Mac folder; it requires macOS Full Disk Access where the OS requires it and uses on-device summarization. It does not use WhatsApp Web, a WhatsApp API, or cloud chat ingestion. Shared app context supports explicitly selected PNG/JPEG screenshots with text review before asking. Suzzme does not read private Messages/Mail databases or other apps' notification history.

With Visual Guidance enabled, a literal request such as “Point to Save on this screen” can highlight one uniquely recognized text label using local Vision OCR, even without model vision. Duplicate, weak, missing, incomplete or stale OCR evidence produces no pointer for that request. The measured text regions are transient; the existing consent, source validation and brief click-through marker remain in charge. See the [Clicky source audit and adaptation](Design/CLICKY_SOURCE_RESEARCH.md) for the original cloud boundaries, source links and current implementation evidence.

On Mac, enabling **Show companion near cursor** also lets the existing Face/response card briefly move beside that verified target, then return beside the current pointer. Normal motion uses a finite native animation; Reduce Motion and Minimal keep guidance still, and cross-display placement resolves instantly. App/Space/display changes, cancellation, reviews, expired evidence and disabled preferences retire the trip. The target ring remains separate and unobscured; no mouse movement or click is synthesized. [Point-and-return evidence](Validation/Reports/PointReturn-20261022/README.md) distinguishes real native lifecycle checks from arranged component previews and remaining permission/accessibility acceptance.

Exact background timing is not guaranteed. Daily Summary’s preferred time schedules a private, repeating local notification when notification access is granted. On Mac, **Settings → Daily Summary & Suggestions → Background on This Mac** separately enables automatic local preparation at that time, using already-permitted Calendar/Reminders and enabled source summaries. It remains active after Home closes while Suzzme is running and the Mac is awake; wake/relaunch catches up on the current local day. It does not wake the Mac or run after quit. Prepare Now uses the same serialized worker. Notifications remain private reminders and do not claim a completed run. Disabling Daily Summary pauses automatic preparation and cancels its notification; taps open Daily Summary. Notifications may be delayed or silenced by Apple and user settings. iPhone retains system background limits and refreshes on opening. Optional iPhone sharing publishes one bounded, prepared Mac summary through the Firebase-identified account. The companion-summary database schema is deployed; real same-account transfer still needs device acceptance testing. It does not provide live Mac access or wake the Mac. See [account backend](../docs/account-backend.md) and [iPhone companion plan](../docs/iphone-mac-companion-ui-plan.md).

The [Sentient OS source audit](Design/SENTIENT_OS_RESEARCH.md) documents the reference architecture and its local/provider boundaries. Suzzme's independently authored background worker reuses the existing information and proactive engines; it never starts microphone/screen capture, modifies another app, or adds background summaries to the interactive conversation. A separate bounded JSON file retains at most 32 preparation receipts containing times, status, counts and a summary reference, without copying source text. Interrupted work is recorded and busy work has bounded retries. Resetting proactive preferences turns automatic preparation off; receipt metadata remains bounded history.

On Mac, open **Background Tasks** from the sidebar or menu bar to inspect this worker, prepare a summary, stop an active preparation, and review its recent results. Daily Summary and its settings also link to the same view. A stopped run shows **Stopping** until its runner has returned, so another preparation cannot overlap it. Upcoming retries appear only while the matching retry is actually scheduled. History contains metadata for up to 24 automatic and 8 manual preparations; retries update the same automatic receipt. **Read Current Daily Summary** opens the current summary, rather than a historical receipt. [Background Tasks evidence](Validation/Reports/BackgroundTasks-20261023/README.md) records checks and isolated native previews.

The Mac notch surface, its non-notch fallback, and the menu bar also show real preparation activity: preparing, stopping, an armed retry, a recent failure, or a completed summary matching the current result. The transient notch card hides after eight seconds; Escape or holding it hides the card while work continues. **Stop** applies only to the run displayed by that control. **Open Tasks** uses the existing Background Tasks route, and **Open Summary** appears for a matching completed result. Conversations, consent reviews, browser connection requests, and time-critical information keep priority. A manual preparation does not hide an automatic retry that is still scheduled. [Background Presence evidence](Validation/Reports/BackgroundPresence-20261023/README.md) records native checks, component previews, and the repaired Home/URL regression checks.

On Mac, **Launch Suzzme at Login** is an optional system login item under Startup on This Mac in Daily Summary settings. It starts the main app when you sign in so the existing local scheduler can catch up for the current day, including when Home has no open window. It does not turn on automatic preparation or bypass Daily Summary and source permissions. System Settings can require approval or turn off the login item; Suzzme shows that actual status. Turning the switch off stops future login launches while leaving the current app session running. [Launch at Login evidence](Validation/Reports/LaunchAtLogin-20261023/README.md) records the source checks; [live Mac evidence](Validation/Reports/LaunchAtLoginLive-20261023/README.md) records the signed install and remaining sign-out acceptance.

“Daily Summary” is the product term. Validated internal Briefing types retain their names.

## Validation and acceptance

Use the [validation guide](Validation/README.md) to choose checks by subsystem. The baseline scripts are `check.sh`, `persistence-check.sh`, `step3-check.sh` through `step12-check.sh`, and `ui-recovery-check.sh`, plus the presence, global invocation, connector, voice lifecycle and Live Activity acceptance suites. `step8-check.sh` includes its Core integration suite. `final-ui-check.py` runs native Mac UI behavior checks with the actual package dependencies. The optional `step12-web-probe.sh` fetches only the three public URLs named in that fixture; all other behavioral fixtures use isolated temporary stores/doubles.

From this directory, compile both configurations on both platforms:

```sh
xcodebuild -project Suzzme.xcodeproj -scheme Suzzme -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/SuzzmeDerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Suzzme.xcodeproj -scheme Suzzme -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/SuzzmeDerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Suzzme.xcodeproj -scheme Suzzme -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/SuzzmeDerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Suzzme.xcodeproj -scheme Suzzme -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/SuzzmeDerivedData CODE_SIGNING_ALLOWED=NO build
```

Unsigned builds establish compilation, not distribution readiness. An ad-hoc Mac signature verifies generated entitlements only. See `Validation/Reports/Step12/` for the hardening risk inventory, logs, data inventory, release limitations and hardware checklist, and `Design/2026-10-07/` for the prototype implementation and UI evidence. Historical acceptance reports describe their recorded build and are not substitutes for fresh checks. Physical acceptance for Steps 5, 7, 8, 9, 10, 11 and 12 remains **PENDING** until the documented real-device matrix is executed.

Distribution requires the owner's Apple signing/provisioning setup for both the app and widget extension, followed by the chosen TestFlight/App Store or Mac distribution process. The project contains public Google OAuth client IDs, has Gmail API enabled, and has both restricted Gmail scopes saved in Google Auth Platform Data access. The Verification centre reports that branding must be verified and published before restricted-scope review can be requested; a real demo video and scope verification also remain before broad release. A real authorization test on each platform is required. In Sources, `gmail.metadata` allows selected inbox headers; a separate `gmail.readonly` consent enables bounded on-device message analysis. Apple’s on-device model extracts important or urgent grounded facts from up to 12 selected messages per refresh; only those summaries can enter Daily Summary, subject to the configured cutoff. Header-only access does not add Gmail items to Daily Summary. Neither scope permits sending or changing mail.

The native URL-only Share extension and its owner signing/App Group setup are described in [SHARE_HANDOFF.md](SHARE_HANDOFF.md). It queues explicitly shared URLs for review; it does not read page contents or automatically open the app. Safari tab pairing remains unavailable.

## Data and recovery

Suzzme's saved items, Personal Memory and normalized recent information stay in app-local SwiftData, bounded JSON and preferences. Connected services retain their own source data and account infrastructure. Voice audio is not written to files. No private notification payload or production prompt/transcript logging. OS backups remain outside local deletion scope.

Malformed or future JSON stores fail closed and retain the original file. Explicit, confirmed recovery controls can reset Watched Links or proactive data/preferences; they never run automatically. SwiftData creation failures preserve the existing database and surface unavailable features rather than inventing data. Do not delete a user's store as a migration shortcut.

The privacy manifest declares app-owned UserDefaults access and no tracking. Release configuration excludes developer tools and disables development entitlement injection. Distribution provisioning, notarization/TestFlight, real permission behavior, VoiceOver, audio routing, display geometry and energy use require separate acceptance.
