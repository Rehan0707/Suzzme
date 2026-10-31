# Step 18 runtime acceptance — first batch

**The first production UI batch is implemented and exercised on macOS. The entire Step 18 mission is not complete. iOS visual/runtime acceptance is blocked.**

## Status distinctions

| Status | Acceptance achieved | Limit |
|---|---|---|
| BUILD PASSED | Final macOS Release arm64 and iOS Release arm64 simulator products | Successful compilation does not establish iOS launch or device signing acceptance |
| TEST PASSED | Six targeted existing suites; results below | Some boundaries use controlled fixtures; not live-provider or physical acceptance |
| RUNTIME OBSERVED | Actual production Mac launch, seven main routes, Settings, refined Assistant/Voice/Integrations, real on-device follow-up, light/dark screens | Regular Mac window only; not every supported size |
| RUNTIME OBSERVED | Real in-app Listening, Cancel recording, then Ready; no voice input submitted | Existing microphone/speech access used; not a human ASR → model → TTS session |
| PHYSICAL DEVICE VERIFIED | No hardware haptic, physical-notch, phone Island, or spoken end-to-end acceptance claimed | Still requires deliberate hardware checks |
| OWNER APPROVED | Scope of implementation/testing requested by owner | Final visual approval has not been recorded |
| BLOCKED | iOS runtime/white-screen acceptance, live-panel presence text evidence, complete accessibility/size matrix and current onboarding runtime | See Remaining Work |

## Targeted tests

| Suite | Result |
|---|---|
| Integration presentation | 117 passed / 0 failed |
| Voice quality | 23 passed / 0 failed |
| Voice lifecycle | 31 passed / 0 failed |
| P0 regressions | 71 passed / 0 failed |
| Product flow | 39 passed / 0 failed |
| Step 8 confirmation | 198 passed / 0 failed |

The prior full-app report remains baseline evidence for the 58-command validation pass and 10 Mac hosted cases. Those full suites were not rerun or relabeled as new results. Only the six relevant suites were repeated for this batch. Initial compiler/setup failures and rejected sizing capture are preserved separately.

## Observed production behavior

- Restarted the rebuilt production Mac product before final captures. All seven native sidebar destinations opened. Home, Settings, Voice, Integrations, Presence settings and Assistant were inspected in actual light/dark renders.
- The first wider Assistant layout clipped inside macOS default form sizing. The rejected image is retained as `diagnostic-clipped-sheet.jpg`. Availability-gated native fitted sizing corrected the observed regular-window clipping; no clipping was accepted as a final result. macOS 14 fallback is compiled but not runtime-verified here.
- “What can you do?” produced the real deterministic Core answer. “Explain photosynthesis in one sentence” showed real thinking/cancel state, then a result attributed “Generated on this device,” retaining the first answer. No mock response was injected.
- Sources opens its existing destination and Back/Done return correctly. Empty Send remains disabled.
- Pace is one visible control group and has one slider accessibility label with Natural value. Haptic preference is visible, but no physical feedback sensation is claimed.
- Search finds Bitbucket while catalog inclusion is off and correctly labels it unavailable. The catalog filter expands the existing directory; a nonmatching query shows the genuine empty state. Clear restores results. The access disclosure retains its full privacy/account explanation.
- GitHub setup opened and cancelled with credential fields untouched and Verify disabled. No account was connected.
- Voice was activated once with existing access: UI reached Listening, then Cancel recording restored Ready without sending. Other voice failure/interruption paths are covered only by the targeted behavioral suites in this pass.
- App appearance was temporarily changed for requested Light and Dark checks, then System was confirmed restored. The app was left on Home. Input Monitoring, voice/rate/haptics preferences and owner stores were not reset. Normal local test conversations and source-cache refreshes can still be created by using the app.

## iOS runtime attempt

Tried the retained dedicated QA device alone before heavyweight builds, with no XCTest runner in parallel. Boot completed in approximately 30 seconds. Installing the previous simulator Release product timed out after 45 seconds as host load climbed; no current iOS screen was captured. Simulator UI acquisition also failed through the available computer-use entry points. The dedicated device was shut down successfully with its data retained.

The final iOS product compiles, but **the blank white-screen issue is not claimed fixed**. The updated product has not received an accepted iOS runtime launch or keyboard-safe composer inspection. No signing/provisioning/entitlement/app-group repair was attempted.

## Remaining limits

Current onboarding neutral surfaces are BUILD PASSED only; the owner’s welcome state was not reset to force a capture. Presence Settings includes a clearly labeled live preview; that is not physical notch or Live Activity evidence. Existing ImageRenderer presence fixtures still omit supplied ScrollView response/confirmation text and require a native-panel investigation. Physical haptics, VoiceOver, all accessibility setting combinations, minimum/maximum windows and phone sizes, real-account integrations, and physical phone presentations remain unaccepted.

New evidence: **23 native Mac screenshots**, accessibility trees, source fingerprints, exact batch diff, and build/test logs. Screenshots contain real local source information and should remain private.

[Visual audit](VISUAL-AUDIT.md) · [Production changes](PRODUCTION-UI-CHANGES.md) · [Before/after](BEFORE-AFTER.md) · [Motion/haptics](MOTION-AND-HAPTICS.md) · [Remaining work](REMAINING-WORK.md) · [Machine-readable acceptance](acceptance-results.json)
