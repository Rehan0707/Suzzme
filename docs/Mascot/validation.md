# Mascot validation — 24–25 October 2026

Results below describe commands actually run for this implementation. Simulator/native component checks are not physical-device acceptance. The workspace already contained substantial uncommitted work; no existing changes were discarded.

## Completed focused checks

| Check | Result |
| --- | --- |
| Foundation extraction/state harness | Pass |
| Step 6 privacy | 53/53 |
| Step 7 context/memory | 90/90 |
| Step 8 action integration | 198/198 (176 behavior + 22 Core) |
| Step 9 information | 132/132 main + 24/24 separate-process persistence checks |
| Global voice, including interruption and preparation ownership additions | 96/96 |
| Voice lifecycle, including revision/settle cancellation additions | 34/34 |
| Live Activity | 36/36 |
| Companion presence geometry | 66/66 |
| Premium presence lifecycle/layout | 20/20 |
| Native Presence lifetime, hidden-panel and CPU checks | 51/51 |
| Native cursor companion | 48/48 |
| Native Space/observer cleanup | 20/20 |
| UI source contracts | 48/48 |
| Modified screen Swift syntax parse | 11/11 files |
| Mascot native rendering | Production asset resolved; light/dark eight-state galleries and 320/390/440-point accessibility layouts rendered and visually inspected |
| Existing Mac presence render matrix | 48 native PNGs generated |
| Source reference integrity | Runtime and retained reference SHA-256 both `f0fcd9e0af1c583ea05cafcce2ebbe9b14f529730eac858a63168fa137311418` |

The global voice/voice lifecycle and native companion checks were executed by delegated agents against the final event/source changes. Focused compile harnesses use whole-module compilation to avoid repeating SwiftUI type checking; test sources and assertions are unchanged except the explicitly added lifecycle coverage and obsolete Home glyph contract update.

The existing global voice suite had four stale assertions that rejected usable partial transcription after an explicit Done/release, although the current voice pipeline intentionally supports that fallback. Those assertions now verify the exact existing fallback transcript/session. New negative cases ensure a recognition error before Done and an empty Done cannot submit.

`FinalUIPresenceRender` had a stale browser connection fixture initializer; its missing `.github` service argument was restored. Manual Swift compile lists now include the mascot. Preview tools compile real asset resources into disposable app bundles so their production image references resolve.

## Known existing failure

`voice-quality-check.sh`: **41/44 pass; 3 fail**. Its warm/calm pitch and between-phrase delay expectations differ from the existing shipping `configuredUtterance` settings (warm pitch 1.06 / pause 0.14; calm pitch 0.97 / pause 0.20). These settings predate this work and were preserved. No success is claimed for this suite.

## Platform and native application checks

The initial integrated mascot passed both iOS Simulator and macOS Debug production builds. After the follow-up requests to replace all branding and add the supplied color/speaking archives, both final Debug builds passed again (arm64 iOS Simulator and native macOS). Hosted unit/UI tests were not completed: the first runner builds were interrupted during compilation; a sequential iOS retry compiled through its targets but stopped advancing during Xcode's explicit-module pruning, before test execution. These attempts are not counted as test results. The broader baseline runner completed Foundation and persistence, then was interrupted; no full-matrix success is claimed.

New native test sources are `NativePlatformUnitTests/MascotTests.swift`, `AssistantPresentationOwnershipTests.swift` and `NativePlatformUITests/MascotRuntimeTests.swift`. The disposable acceptance project copies production sources unchanged and changes only test installation identity/targets, protecting the installed app's data. The focused UI test opens Home in both appearances with large text and submits a real typed request, without starting a microphone.

## Evidence and remaining acceptance

Rendered evidence and retained logs are under `Suzzme/Validation/Reports/Mascot/`; broader baseline results are under `Suzzme/Validation/Reports/MascotRegression/`. These generated evidence directories are ignored by Git. Reproduce the mascot gallery with `zsh Validation/mascot-render.sh` from `Suzzme/`.

There is no iPhone Duo target in this repository, so no separate Duo build is possible. Physical microphone/audio routing, VoiceOver interaction on devices, older-OS runtime checks, hardware notch alignment, animation energy profiling, distribution signing and any specialized Duo hardware remain outside the simulator/native checks. Supplied speaking GIFs run only during actual speech, with native word/playback progress supplying fallback articulation; phoneme-level lip sync is unavailable in the current pipeline. Static galleries deliberately freeze motion and do not establish animation timing or real capture behavior.

## Follow-up branding and archive checks

- Retired `SuzzmeFaceGlyph` geometry and `SuzzmeFaceShape` are absent from runtime source; legacy `SuzzmeFace` is only a cloud-compatible layout wrapper. No runtime `Image("SuzzmeLogo")` reference remains. The old logo PNG has also been replaced, and the Mac menu-bar artwork is no longer template-tinted.
- All eight exported app-icon PNGs were inspected for expected 16–1024 pixel dimensions and opaque RGB encoding. The iOS master is 1024 × 1024 without an alpha channel.
- The app, Share extension and WidgetKit catalogs each contain the original blue cloud bytes. All eight PNG color variants and speaking GIFs were inspected and are bundled for companion use.
- The native renderer resolved every supplied color resource, decoded all eight GIFs as 16 frames / 1.44 seconds, and rendered static/open-mouth frames against light and dark backgrounds. The transparent PNG silhouettes retain eye whites while removing the GIFs' white canvas. These are labelled visual fixtures, not simulated speech activity.
- UI source contracts pass 48/48 after the branding changes. Python validation scripts parse successfully and `git diff --check` is clean.

## Color personalization and Liquid Glass UI polish — 25 October 2026

- The latest macOS and iOS Debug production builds both pass after adding the post-login color carousel, reactive palette, custom sign-in layout and app-wide shared glass surfaces. The iOS build targets generic iOS device; the earlier recorded Simulator build is from the preceding mascot integration.
- A follow-up audit added Liquid Glass to assistant presence and recovery panels, plus the Mac cursor companion and guidance label. Latest iOS and macOS Debug builds pass after those additions.
- All seven alternate icon catalogs plus the blue primary icon catalog parse as JSON. Build output includes the alternate iOS icons.
- `git diff --check` passes for the updated sign-in, theme, shared component, page layout, Home, navigation and personalization documentation files.
- No test suite or physical-device visual run was performed for this UI pass. The Liquid Glass modifier keeps an opaque Reduce Transparency fallback and native material on supported older OS versions.
