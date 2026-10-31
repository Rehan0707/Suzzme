# Step 19 — iOS startup investigation

The current iOS Release simulator build succeeds and installs on the retained QA device. **An accepted launch and first rendered screen remain blocked. The reported white screen has not been reproduced or fixed in this pass.**

## Source diagnosis

Reviewed SuzzmeApp, SuzzmeAppStartup, ContentView, MobileRootView, AppEnvironment, SuzzmeUnderstandingPipeline and AppleIntelligenceService.

- The App owns one observable startup and injects the ready environment into ContentView. Preparing/recovery render the original Face, background, progress/explanation and explicit recovery controls. No intentional empty root branch was found.
- SwiftData containers open through the existing `@concurrent` preparation method. Contexts and the production environment are constructed afterward. Store failures produce recovery UI without deleting data.
- Routing uses the existing welcome preference. Onboarding leads to the same native mobile root. Presence sits outside NavigationStack; destinations share the existing router/environment. Scene cleanup belongs to the aggregate runtime owner.
- Account restoration, source refresh and summary preparation run in view tasks after the app branch exists. No generation request is awaited in the App body or preparing view.
- Foundation Models is actor-owned and generation checks availability. This review is not a measured first-frame guarantee. Synchronous service construction after storage preparation still needs a device trace if the owner reproduces a launch hang.

No startup source change was justified by this evidence. No speculative root/persistence replacement was made.

## One controlled runtime attempt

Only **Suzzme Full App QA 2026-10-16**, `A4E6594C-838C-474A-B2BA-25A23BA6CEAD` (iPhone 18 Pro / iOS 27.0), was booted. No XCTest or heavyweight build ran alongside it.

| Operation | Result |
|---|---|
| Baseline iOS Release arm64 build | BUILD PASSED; ios-build.log |
| Boot | Exit 0; 2.01 seconds |
| Wait for boot | Exit 0; 7.05 seconds |
| Install | Exit 0; 31.14 seconds |
| Launch rehan.Suzzme | Timeout, interrupted after 45.35 seconds; exit -2; no PID returned |
| Simulator launchctl list | Timeout, interrupted after 30.57 seconds; exit -2 |
| Read recent logs | Bounded at 47.59 seconds; SIGINT returned 0, **not accepted as completed**; only getpwuid_r uid 501 warning and header, no app events |
| Simulator frontend | Expected Developer/Applications directory and Simulator.app absent; Contents/Applications also lacks Simulator.app; no simulator window in native app inventory |
| Shutdown QA device | Exit 0; data retained; erased=false |

Host load rose from about 2 before boot to over 120 during launch. A read-only process snapshot did not show an iOS Suzzme executable. The stalled process query supports an infrastructure block, but does not establish the cause of the owner's earlier white screen. Raw commands/durations are in evidence/ios-runtime.json; shutdown in evidence/ios-shutdown.json.

No iOS runtime screenshot, text input, keyboard layout, voice presentation or light/dark acceptance is claimed. The simulator contains the pre-refinement baseline product; the final refined product is built separately afterward. There was no second simulator session.

## Owner-run Xcode acceptance

1. Use a complete Xcode installation with an accessible Simulator window. Open `/Users/rehan/Documents/Projects/Suzzme/Suzzme/Suzzme.xcodeproj`, choose scheme Suzzme and the retained QA simulator. Keep signing/capabilities unchanged; do not erase data.
2. Run with Command-R. Capture the first screen and console. Expect Preparing Suzzme, sign-in/onboarding or Home according to local state. Storage failure must expose Try again and Continue with available features.
3. If the screen remains white, pause execution and save the main-thread backtrace and console before retrying. This distinguishes pre-main/scene failures from preparation/environment construction.
4. If onboarding appears, continue without an account and skip optional permissions. Open Assistant, type, inspect the composer with the keyboard open, dismiss the keyboard, follow up, scroll upward and use Latest message.
5. Inspect Home, navigation, voice UI without granting optional access, and light/dark. Restore System appearance. Record physical-device checks separately.

Input Monitoring, signing settings, entitlements, provisioning, app groups, owner data and simulator data were preserved.
