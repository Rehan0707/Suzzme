# Suzzme — public Clicky conversion

## Implemented

The available public Clicky project is preserved as an 80-file MIT-licensed source snapshot in `Suzzme/ReferenceSource/Clicky`. Its original checkout is unchanged. A SHA-256 inventory records every copied file. Local secrets, Git history, caches, signing credentials, user Xcode state and reference agent instructions were excluded.

Shipping Suzzme now uses Clicky-derived native Mac control-panel and cursor-response adapters. `MacCompanionMenuController` owns one menu-bar status item and one reusable nonactivating panel. It provides keyboard entry, outside-click/Escape dismissal, display-bounded geometry and native Settings/Home/Source navigation. `MacMenuBarView` presents the Suzzme Face, real capability/permission state, typed questions, Talk, screen questions, Daily Summary and the cursor preference.

`MacCursorCompanion` provides opt-in, click-through Face/transcript/response/speech-progress presentation near the pointer. It uses mouse events instead of a permanent polling timer, respects Reduce Motion, clamps to each display, retires superseded requests and removes monitors when hidden. Interactive screen consent and action confirmations remain with their existing owners.

All requests still use one `AppEnvironment`, `SuzzmeCore`, `VoiceSessionController` and Assistant State. Existing screen consent/OCR/grounded pointing, Mac notch, iPhone Live Activities, memory, summary, source-health, web connections and Step 8 authorization/execution/verification remain in place. Clicky's cloud model, transcription, TTS, Worker, PostHog and updater are reference-only and do not ship. The MIT license is bundled in the application.

## Validation

- macOS Debug: PASS, no compiler warnings.
- macOS Release: PASS, no compiler warnings.
- iOS simulator Debug: PASS, no compiler warnings.
- 36 validation suites: PASS. MCP's initial invocation lacked its required SDK-products environment variable; rerun with the pinned products path passed 28/28.
- New native adapter checks: 47 passed / 0 failed. They exercise shipping panel-owner methods with environment/view doubles; AppKit panels, monitors, geometry and preference storage are real. This is not hardware or microphone acceptance.
- Locked regression floors preserved: Step 6 53/53; Step 7 90/90; Step 8 198/198; Step 9 156/156; Step 10 194/194.
- Existing UI, global shortcut, Space and real AppEnvironment checks pass.
- `git diff --check`: PASS.
- Snapshot integrity: PASS.

Runtime observed in the rebuilt Mac application: converted panel renders; a typed binary-search question receives a natural local answer; its follow-up receives a contextual answer; a Swift-actor question receives a local answer; repeated panel invocation works; Escape hides it; Sources opens the existing screen; Settings opens the native Settings scene; the cursor toggle can be changed and restored.

The iPhone app was installed and launched on the existing iOS 27 test simulator; onboarding rendered correctly. This was a startup check, not full iPhone runtime or physical-device acceptance.

Runtime testing found an accessibility-click dismissal defect: native accessibility activation can target the panel without moving the physical cursor, so a global-coordinate-only local click check dismissed the panel. Local dismissal now checks the event's actual window before outside coordinates. The native panel background also changed to Suzzme's semantic canvas after rendered testing showed excessive material translucency.

Evidence: `Suzzme/Validation/Reports/2026-10-07-clicky-conversion/validation.json` and adjacent per-suite logs. Build logs: `/private/tmp/suzzme-clicky-{mac-build,mac-release-build,ios-build}.log`.

## Limits

This is an adaptation of the available public companion, not a claim of equivalence to private HeyClicky. Clicky's own README states newer functionality is private. Its public Worker has cloud AI/STT/TTS routes, not Gmail/WhatsApp integration code.

Gmail remains unavailable with placeholder Google OAuth client IDs; registered IDs and real sign-in are required. WhatsApp uses explicit shared text, not live account/private-database access. Notion/Linear/Google Docs and native browser-host deployment retain their existing limitations. No mock connection or permission success was added.

Apple Foundation Models readiness was shown by the running app; local answers were observed. Native Apple voice replaces ElevenLabs; copying an ElevenLabs API client cannot reproduce its voice offline. Voice quality, microphone/barge-in/TTS, physical notch alignment, global shortcut hardware behavior, real Dynamic Island, real account access and full iPhone acceptance remain PENDING.

## Main added/modified files

- `Platform/macOS/MacCompanionMenuController.swift` — adapted status item/control panel and native scene handoff.
- `Platform/macOS/MacMenuBarView.swift` — converted companion control UI.
- `Platform/macOS/MacCursorCompanion.swift` — local cursor-side response adapter.
- `Platform/macOS/MacGlobalInvocationController.swift` — feeds and retires cursor presentation through existing ownership.
- `Platform/macOS/MacCompanionCommands.swift` — native panel command.
- `App/SuzzmeApp.swift` / `App/ContentView.swift` — one menu owner and destination handoff.
- `Core/Invocation/AssistantPresentation.swift` / `Features/Invocation/PresenceSettingsView.swift` — persisted opt-in cursor setting.
- `Resources/Clicky-MIT-LICENSE.txt` — shipping license attribution.
- `Validation/clicky-companion-check.py` — focused adapter regression harness.
- `ReferenceSource/Clicky/` / `ReferenceSource/CONVERSION.md` — available public source and subsystem conversion map.

Before-conversion source backup: `/private/tmp/Suzzme-before-clicky-conversion-2026-10-07.tar.gz`. No user changes were reset, staged or committed.
