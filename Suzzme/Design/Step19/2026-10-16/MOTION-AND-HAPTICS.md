# Step 19 motion, feedback and accessibility

Existing native navigation, sheets, Assistant lifecycle, voice controller, Face, Mac presence panel and Live Activity owner remain. No new assistant state machine, repeating timer, synthetic microphone level or generated progress was introduced.

| Interaction | Implementation / acceptance limit |
|---|---|
| Navigation / sheets | Existing NavigationStack, NavigationSplitView and native presentations; Command-K opens Assistant and Escape/Done dismiss it. |
| New turn / return to latest | Shared 0.28-second disclosure motion drives existing ScrollViewReader scrolling. Reduce Motion returns nil. Native scroll visibility tracks the bottom marker on iOS 18+/macOS 15+; older OSes retain prior lifecycle fallback. |
| Thinking / activation / cancellation | Actual existing environment phases drive Face, text, disabled input and Cancel. Cancellation retires the existing request owner. |
| Listening / processing / speaking | Existing microphone amplitude, controller phases and real speech progress drive presentation. Voice activation and cancellation observed on Mac; spoken end-to-end and interruption acceptance remain pending. |
| Presence expansion / dismissal | Existing shared spring, actual presentation identity and native panel sizing retained. Hardware notch/phone Island acceptance is not established by previews. |
| Idle | No ambient animation added. |

The final visibility callback replaces unsuccessful lifecycle-only and coordinate-based attempts. The callback is a native SwiftUI API: [Apple scroll visibility documentation](https://developer.apple.com/documentation/swiftui/view/onscrollvisibilitychange(threshold:_:)). SDK availability was also checked directly. Older supported OS fallback is compiled, not runtime-accepted here.

## Haptics

The existing SuzzmeHaptics owner still checks its stored preference and iOS hardware capability, uses UIKit for discrete activation/recording/selection/completion/warning feedback, and requests AppKit confirmation/completion feedback on eligible trackpads. Visual state and controls remain available without haptic hardware.

Step 19 changes only selection delivery: the shared selection modifier now checks scenePhase == active. Programmatic route/onboarding changes while inactive therefore do not request selection feedback. There is no second feedback service and no feedback on animation frames.

**PHYSICAL DEVICE VERIFIED: none** for phone/trackpad sensation, real notch, Live Activity or complete spoken ASR → model → TTS. Simulator execution cannot establish sensation.

## Accessibility

- Important Assistant transitions (Listening, Awaiting confirmation, Success, Error) post a native AccessibilityNotification announcement only while their scene is active. Partial transcripts/audio samples do not repeatedly post announcements.
- Existing state text, labeled voice/send/cancel controls, attribution and confirmation ownership remain. Latest message has a 44-point minimum target, label, hint and stable identifier.
- Summary text retains system type, full text, selection and wrapping. No fact/string segmentation was introduced.
- Existing composer safe-area inset, interactive keyboard dismissal and accessibility-size in-scroll controls remain. iOS keyboard runtime is blocked.
- Semantic surfaces and the existing Increased Contrast/Reduce Transparency fallbacks remain. No color-only status was added.
- Native AX trees were captured; full spoken VoiceOver, largest Dynamic Type, contrast/transparency permutations, reduced-motion timing and all minimum/maximum device/window sizes remain pending. A source check is not substituted for those observations.
