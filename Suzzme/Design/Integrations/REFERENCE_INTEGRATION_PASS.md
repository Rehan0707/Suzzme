# Clicky / Sentient reference integration pass — 7 October 2026

Status: partial implementation. This is not acceptance of live Gmail, WhatsApp, or every catalog service.

## Reference findings

Inspected Clicky's Apple Speech implementation, global push-to-talk and ElevenLabs client, and Sentient's Direct MCP connector architecture, Gmail reader, WhatsApp reader and notch shapes. Clicky is MIT licensed; Sentient's root license is AGPL-3.0. No source code from either repository was copied in this pass.

Clicky's premium transcription, intelligence and TTS depend on external providers. Suzzme retains its existing VoiceSessionController, required on-device recognition, AVSpeechSynthesizer, local intelligence and central SuzzmeCore ownership. Its existing public-API notch and keyboard implementation remains intact.

Sentient's Gmail reader uses a cloud CLI connector/model, and its WhatsApp reader accesses a private desktop database. Neither was transplanted. The useful connection principles—account binding, live readiness, cancellation, limited reads, untrusted content and credential separation—remain in Suzzme's existing native integration gateway. Arbitrary tools cannot bypass its action boundary.

## Actual changes

- Gmail transport now pins the Google metadata endpoint, refuses redirects, has no cookie/cache/credential storage, streams within a 64 KiB limit, and bounds a refresh to 60 seconds of HTTP work after obtaining a grant. Response identity, message IDs, duplicates and list limits are checked before intake. Tokens remain outside inference and persistence.
- A completed user-initiated Gmail connection enables the existing recent-updates preference and starts its source refresh. Restoring a sign-in does not silently change the saved preference. Access grants also check the controller's current authorization state.
- Integrations exposes the existing Gmail and shared-message paths; Sources exposes Integrations. There is no second account or ingestion manager.
- A selected UTF-8/UTF-16 text file (maximum 64 KiB) can be reviewed. An explicit excerpt of at most 720 characters enters the existing InformationEngine/privacy/store path. Oversized previews remain visible and cannot be imported; they are not silently truncated. No original message dates are invented from the sharing time.
- The Mac Release sandbox grants read-only access to user-selected files, rather than home directories or private app containers.
- Native button styling and a readable in-row disclosure address issues found while exercising the form.

Production startup continues to use real local stores and authorized sources. MockIntelligenceService is confined to the explicitly constructed preview environment. Synthetic responses exist only in validation fixtures.

## Validation

- Connector acceptance: 60 passed / 0 failed (existing assertions retained; 28 added).
- Step 9 intake: 156 passed / 0 failed across six checks.
- Step 10 Daily Summary: 194 passed / 0 failed, including header-only Gmail → InformationEngine → Daily Context → Summary, and removal on authorization revocation.
- Central integration Core boundary: 18 passed / 0 failed.
- iOS Simulator Debug: build passed, no compiler warnings/errors in the final log.
- macOS Debug: build passed, no compiler warnings/errors in the final log.
- macOS Release: ad-hoc signed build passed, no compiler warnings/errors in the final log. This is not distribution signing acceptance.
- Native Mac runtime: new catalog routes observed; oversized preview rejected without saving; file chooser produced a modal state and Escape returned to the unchanged form. The chooser's own contents were not exposed by the automation surface, and no user chat file was imported.
- Normal app launch: Listening and Cancel → idle observed. A separate directly terminal-launched process aborted under TCC, reporting a missing speech usage description; its diagnostic attributed responsibility to Codex/ChatGPT. Both built app plists contain the required description, and the normally launched app subsequently entered Listening. Launch attribution is the suspected cause, not an established missing source plist key. Full voice/transcription/TTS and physical acceptance remain pending.

Behavioral tests use isolated stores and synthetic provider fixtures. They do not establish real account or physical-device acceptance. Prior validation reports are preserved.

## Remaining requirements

Both Google platform client IDs are still placeholder values in the project. The user's instruction to use existing configuration was checked; no usable Suzzme OAuth registration exists there. Owner-provided registrations matching the bundle IDs, Gmail API/consent configuration and real sign-in are required before Gmail can work. No credentials were borrowed from the reference apps, CLI tools or browser sessions.

Gmail remains an inbox-header reader (maximum 30 recent messages), not a mail-body/attachment reader or sender. WhatsApp remains explicitly shared text, not connected live chats. Notion, Linear and Google Docs remain unimplemented/unconfigured catalog entries. GitHub retains its existing reviewed read-only connector; real account acceptance and external writes remain pending. Native Calendar/Reminders depend on device authorization; the running ad-hoc test app reported Calendar unavailable, so a populated real-calendar summary was not accepted.

No cloud inference, external TTS, private Messages/WhatsApp database access, autonomous writes or fake connection states were added. Real-account, iPhone runtime, voice and physical notch/Dynamic Island acceptance remain pending.
