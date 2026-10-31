# Physical acceptance checklist — pending

Automated tests, rendered Mac UI and simulator observations do not accept microphone/audio quality, physical notch attachment, Dynamic Island, permissions, battery or thermal behavior. No new physical-device acceptance is claimed.

Record device, OS, signed build/commit, enabled sources, time zone, observed result and reproduction for each row. Use disposable, explicitly approved records for native write tests; remove them after verification.

| iPhone check | Status |
|---|---|
| Calendar permission and real event context | PENDING |
| Reminders permission and real task context | PENDING |
| Today/tomorrow populated summary and grounded follow-up | PENDING |
| Microphone/speech permission, on-device recognition availability | PENDING |
| Talk → transcript → context → answer → TTS → idle | PENDING |
| Repeated sessions, rapid Stop, cancellation, background/foreground | PENDING |
| Barge-in stops playback; stale callbacks cannot respond | PENDING |
| Human selection/acceptance of installed Apple voice | PENDING |
| Dynamic Island compact/expanded, Lock Screen, session end/restoration | PENDING |
| Summary notification routing and fresh/cached disclosure | PENDING |
| Safe Reminder and Calendar confirmation → execution → read-back | PENDING |
| Settings restart, VoiceOver, large Dynamic Type, light/dark | PENDING |
| Battery, CPU, memory pressure, thermal under sustained use | PENDING |

| Mac check | Status |
|---|---|
| Physical notch attachment, no gap, click region | PENDING |
| First click, Control+Option hold/release, repeated invocation | PENDING |
| Compact/expanded, listening/context/thinking/speaking/confirmation | PENDING |
| Success/error, long press, auto-hide/collapse, interrupted motion | PENDING |
| One non-orphaned panel; focus and keyboard behavior | PENDING |
| Fullscreen, Spaces, external/notchless displays | PENDING |
| Sleep/wake, microphone device changes, denial/revocation | PENDING |
| Audible voice quality, repeated sessions, barge-in, TTS completion | PENDING |
| Real authorized sources, populated summary/follow-up, native actions | PENDING |
| Explicit screen question, authorization, capture expiry/non-retention | PENDING |

Step 5, Step 7, Step 8, Step 10 and later hardware statuses stay PENDING. On-device Apple speech quality is limited to available installed voices; no Clicky proprietary voice or cloud speech service is used. Continuous iOS background wake-word listening and permanent idle Dynamic Island occupation are not promised.
