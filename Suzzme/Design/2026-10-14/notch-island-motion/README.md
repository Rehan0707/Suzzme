# Notch and Dynamic Island motion — 14 October 2026

The Mac notch now uses distinct native opening/dismissal easing, a lightly damped silhouette transition, and a finite highlight traveling along the open rim on assistant state changes. The highlight shares the existing notch shape, settles to stillness, and cancels/restarts with the current state. Listening continues to use real measured audio; spoken progress continues to come from the speech delegate.

The ActivityKit extension now fades changing status/detail content and confirmation controls, and gives each existing session phase a distinct small face scale with a restrained spring transition. The face is shared by compact, minimal, expanded and Lock Screen presentations. Existing symbol replacement remains active. Reduce Motion, the Minimal preference, stale content and reduced-luminance Always-On presentation disable animation. No timer or synthetic waveform was added to the extension.

Apple controls the Island's outer expansion and dismissal. Custom content changes use supported update animations below the system's two-second limit: [Apple animation documentation](https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities).

The existing lifecycle still ends idle/success/error sessions; the change does not create a persistent Island to show decorative terminal states. Mac success/error cues retain their existing finite feedback. Input Monitoring remains unchanged.

## Verification

Both macOS and iOS simulator Release builds passed; see `build-results-authorized.json`. The first sandboxed attempts could not access Xcode caches/services and are retained separately.

The targeted suite passed Live Activity 36, companion presence 66, premium layout 20, and native panel runtime 51 checks. Locked regressions passed Step 6 (53), Step 7 (90), Step 8 (198), its Core checks (22), and all Step 9 groups. `test-results.json` records exits; **All 46 regression suites subsequently completed with exit 0.** `all-regression-results.json` records each outcome and log hash; `remaining-regressions.json` retains timing for the broader run.

A validation-shell regex incorrectly treated the optional-chain question mark as a quantifier; its source assertion now uses fixed-string matching. No behavioral assertion was removed.

The rebuilt Mac app was opened and its real listening → Escape → Ready path observed. `Rendered-States/` contains native development renders of all assistant states, explicitly labeled simulations; these static images do not demonstrate animation timing or physical-notch alignment. Physical iPhone Island animation, Always-On and device-size acceptance still require device verification. No physical iPhone acceptance is claimed.
