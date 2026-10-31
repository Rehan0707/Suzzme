# Step 18 motion and haptics

## Shared motion

| Interaction | Owner / implementation | Reduce Motion |
|---|---|---|
| Button feedback | Native SwiftUI button pressed/disabled states; existing `Motion.feedback` is 0.18 seconds where custom state feedback is already used | Custom feedback token returns nil |
| Navigation and sheets | Native NavigationStack/NavigationSplitView and presentation lifecycle; no second navigation or assistant state manager | System behavior and existing accessibility settings |
| Launch phases | Existing `Motion.transition`, 0.28-second smooth transition | Existing short opacity transition |
| Onboarding step changes | Reuses new `Motion.disclosure`, 0.28-second smooth transition with no bounce | No custom animation |
| Integration access expansion | Native DisclosureGroup driven by its real expanded binding; same shared disclosure token | No custom animation |
| Conversation insertion/following | Existing real entries and bounded scroll-to-bottom behavior in Ask | Existing reduce-motion guard retained |
| Assistant and voice states | Existing assistant state / voice lifecycle drives Face, text, disabled composer and Cancel | Existing minimal Face/presence behavior retained |
| Presence expansion | Existing spring duration 0.28 seconds, state-bound surface identity and rim | Existing guard bypasses expansion when Reduce Motion/minimal mode applies |
| Thinking and completion | Existing actual state labels/Face; no new timer, fake waveform or artificial listening phase | State text remains visible |

The batch introduces no ambient idle animation or polling loop. Search filtering is immediate; it does not animate an entire catalog on every keystroke.

## iPhone feedback

The existing `SuzzmeHaptics` owner uses Core Haptics hardware capability detection and the stored interaction-feedback preference. UIKit performs activation, recording start/stop, confirmation, completion, warning and selection feedback. This batch adds restrained selection feedback when pace editing ends, not for every slider value.

## Mac feedback

The same existing owner now requests AppKit `.alignment` for a confirmation and `.generic` for completion/success. Ordinary typing, sidebar selection, idle frames and recording phases do not request Mac haptics. AppKit routes these requests to eligible hardware; this does not assume every Mac has a haptic trackpad. The new Trackpad feedback preference is visible under Voice. Unsupported hardware keeps the existing visual status, confirmation controls and completion/error text.

## Acceptance limits

Build success and automated event/voice checks do not establish physical sensation. **PHYSICAL DEVICE VERIFIED: none in this batch.** Actual trackpad/iPhone feedback, VoiceOver announcements, Reduce Motion/system feedback preference combinations, and human microphone-to-speaker interruption scenarios still require hardware acceptance. Input Monitoring remains unchanged, so cross-app Control–Option hold/release is not accepted here.
