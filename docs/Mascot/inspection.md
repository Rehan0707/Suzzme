# Mascot implementation inspection

Inspected 24 October 2026 before the companion integration. Existing uncommitted work is retained.

## Actual product targets

`Suzzme/Suzzme.xcodeproj/project.pbxproj` contains three production targets:

| Target | Supported platforms | Deployment floor |
| --- | --- | --- |
| Suzzme | iPhone/iPad device and simulator, native macOS | iOS 17, macOS 14 |
| SuzzmePresenceWidget | iPhone/iPad device and simulator | iOS 17 |
| SuzzmeShareExtension | iPhone/iPad device and simulator, native macOS | iOS 17, macOS 14 |

The shared SwiftUI app uses Swift 6. Device family `1,2` means iPhone and iPad. There is no iPhone Duo target, layout, entitlement, specialized display API, or simulator configuration in this checkout. That requested target cannot be verified or claimed functional; the shared iPhone/iPad adaptive layout is the applicable existing implementation.

## Existing architecture and integration points

| File/component | Existing responsibility and intended mascot change |
| --- | --- |
| `Suzzme/Suzzme/App/AppEnvironment.swift` | Main-actor presentation owner; reuse its actual `presenceState`, microphone RMS and speech progress. Preserve request ownership and stale callback protection. |
| `Suzzme/Suzzme/Core/Models/SuzzmeAssistantState.swift` | One assistant lifecycle, including listening, processing phases, speaking, success and error. Map this to a visual expression without creating an independent assistant lifecycle. |
| `Suzzme/Suzzme/Core/Voice/VoiceSessionController.swift` | Existing capture/speech owner; real RMS and owned utterance progress already available. No synthetic microphone activity or playback is needed. |
| `Suzzme/Suzzme/DesignSystem/Components/SuzzmeFace.swift` | Reused assistant face and motion policy. Preserve compatibility for existing consumers while adopting the supplied character through the reusable mascot component. |
| `Suzzme/Suzzme/DesignSystem/Components/SuzzmeMascot.swift` | Intended new reusable component for explicit character states, sizing, animation policy, callbacks and accessible semantic status. |
| `Suzzme/Suzzme/Assets.xcassets/` | App asset catalog. Preserve the source artwork and add real shared reference assets; avoid nonexistent state-image references. |
| `Suzzme/Suzzme/Features/Home/HomeView.swift` | Home companion, real Talk/typed actions and status; keep the primary task layout. |
| `Suzzme/Suzzme/Features/Home/AskSuzzmeView.swift` | Existing conversation, response, task processing and cancellation surfaces. |
| `Suzzme/Suzzme/App/LaunchExperience.swift` | First-run/onboarding companion presentation. |
| `Suzzme/Suzzme/DesignSystem/Components/SuzzmeAssistantPresenceView.swift` | Compact/expanded state-driven companion surfaces; existing text communicates activity accessibly. |
| `Suzzme/Suzzme/Platform/macOS/MacAssistantPresence.swift`, `MacCursorCompanion.swift` | Existing floating/notch/cursor companion. Reuse panel ownership, geometry, hit testing, consent and click-through behavior. |
| `Suzzme/PresenceShared/`, `Suzzme/SuzzmePresenceWidget/` | Privacy-safe system ActivityKit presentation; app and extension have separate resource membership. Do not assume an app asset is available to the extension. |

`ContentView` and `AppRouter` retain existing native iPhone navigation and Mac sidebar. `SuzzmeTheme` owns spacing, typography, colors and motion preferences. Optional integrations, onboarding, authentication and action confirmations remain owned by their existing screens/services.

## Existing validation infrastructure

Production project has no committed XCTest target or shared scheme. `Suzzme/Validation/native-platform-runtime.py` creates a disposable project with `NativePlatformAcceptance`, `NativePlatformUnitTests` and `NativePlatformUITests`, copies production Swift sources unchanged and uses a distinct bundle identifier to protect installed app data. Native tests exercise startup recovery, conversation ownership, local voice assets, shared lifecycle, first run/onboarding, routes and typed conversations.

Standalone checks use isolated temporary executables and cover real production models. Required preserved baselines include Step 6 53, Step 7 90 and Step 8 198 checks. Historical-store scripts intentionally regenerate fixture inputs and must not be run as routine regression checks.

Local simulator inventory includes iOS 27 iPhone 18 Pro, iPhone 17/17 Pro/17 Pro Max/17e/Air and iPads. These are simulator options, not hardware acceptance. CoreSimulator and Swift macro execution require the existing execution environment's approved unsandboxed path.

Fresh command results are recorded separately in the implementation validation report; this inventory does not assert build, render or runtime success.
