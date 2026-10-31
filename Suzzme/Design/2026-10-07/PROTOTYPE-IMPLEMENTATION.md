# Native prototype implementation

The editable prototype is now implemented in the SwiftUI app's navigation and companion entrance, alongside the earlier shared component and secondary-screen polish.

## Implemented

- Home is the default route on iPhone and Mac: centered Face, quiet introduction, primary Talk action, three useful shortcuts, and a bottom question composer.
- Send submits the entered question into the existing assistant pipeline when the conversation opens. Talk uses the existing microphone, Speech Recognition, voice lifecycle, and permission handling.
- The previous daily dashboard remains available as Today; Daily Summary, Memory, Sources, History, and Settings remain reachable.
- iPhone uses a native navigation stack with compact navigation, History, and Settings controls. Returning from a secondary route restores Home. Summary notifications still select the Summary route.
- Mac starts with the native sidebar hidden. The system sidebar toggle reveals all routes when needed. History, Settings, and Ask are compact toolbar controls; Command-K opens Ask.
- A window-style Mac menu bar entry offers the shared live state, typed input, Talk, Open Suzzme, and Settings. Voice invokes the existing transient companion panel.
- Context opens real source controls, selected Messages text import, Memory, connected services, and the consent-governed Mac screen request.
- Answers, voice transcript, cancellation, action review, destructive confirmation, permission recovery, Settings, and secondary views retain their existing validated behavior and shared design system.

## Product boundaries

The prototype's demonstration data is not copied into production. Pasted Messages text uses the existing protected-data checks and local seven-day retention, with removal controls. The current app does not support file attachments, continuous screen sharing, account sync, or arbitrary iPhone screen capture. Context explains these limits rather than presenting simulated controls as working features. iPhone Live Activity and Mac notch surfaces continue through the existing platform controllers.

## Verification

Both final macOS and iOS Simulator Debug builds passed. The existing native UI behavior harness passed all 53 checks. All 28 shell acceptance suites passed, including Step 6 (53), Step 7 (90), Step 8 (198), voice ownership, screen consent, source recovery, and privacy regressions. The UI layout checks now inspect the new Home implementation and retained navigation routes; action, privacy, and voice assertions were not relaxed.

Native Mac Home and main-window captures cover light, dark, and accessibility text. Live native interaction verified Context navigation and Home submission through a completed assistant answer. Actual iPhone simulator rendering remains unverified because the earlier CoreSimulator installation stalled; iOS compilation passed.

`PROTOTYPE-IMPLEMENTATION.diff` compares app source with the snapshot taken immediately before this implementation, excluding preexisting user edits.
