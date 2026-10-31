# Public Clicky to local Suzzme

The complete available public Clicky source is preserved in `Clicky/`, with its MIT license and SHA-256 inventory. Source revision is recorded in `Clicky/SOURCE_MANIFEST.json`; this snapshot also includes local source edits present during copying. It excludes Git history, caches, secrets, signing credentials, user Xcode state and third-party agent instructions. The original Clicky checkout is unchanged. This directory is outside Suzzme's synchronized app source group and is neither compiled nor bundled.

The shipping application remains `Suzzme/Suzzme.xcodeproj`, scheme `Suzzme`, for both iOS and macOS. Do not run the reference Xcode project or deploy its Worker to run Suzzme.

## Running conversion

| Public Clicky subsystem | Shipping Suzzme implementation |
| --- | --- |
| MenuBarPanelManager / CompanionPanelView | Adapted `MacCompanionMenuController` / `MacMenuBarView`: one nonactivating control panel, native keyboard entry, outside-click/Escape dismissal, actual permission state, voice, screen question, Daily Summary, Sources and Settings routes |
| CompanionResponseOverlay / cursor overlay | Adapted `MacCursorCompanion`: opt-in click-through Face, live transcript, answer and speech progress, event-driven cursor movement, display bounds, idle dismissal, Reduce Motion; existing grounded `MacGuidanceOverlay` supplies pointing |
| CompanionManager | Existing single `AppEnvironment`, `SuzzmeCore`, Assistant State and invocation owner; no parallel manager or assistant state machine |
| BuddyDictationManager / global shortcut | Existing `MacGlobalInvocationController`, listen-only `MacInvocationShortcutMonitor` and `VoiceSessionController`; hold/release/cancel ownership remains central |
| ClaudeAPI / OpenAIAPI | Existing on-device `AppleIntelligenceService` with Foundation Models availability detection and deterministic local fallback |
| AssemblyAI / OpenAI transcription | Existing Apple on-device speech recognition; never enable server recognition as a fallback |
| ElevenLabsTTSClient | Existing native `AVSpeechSynthesizer`, installed voice picker, cancellation and completion ownership; ElevenLabs' voice cannot be reproduced from its client code offline |
| Screenshot / ElementLocationDetector | Existing single-use consent, `MacScreenContextSource`, local OCR and grounded spatial references; no automatic background capture or unsupported model image input |
| Preferences / model selector | Existing persisted Voice, Presence, Memory, Daily Summary and Sources settings; actual model capability instead of cloud model choices |
| Worker / analytics / update feed / release tooling | Preserved as reference only. No Worker, PostHog, Sparkle, cloud inference endpoints or Clicky release credentials ship in Suzzme |
| Web integrations | Existing Suzzme Gmail OAuth/metadata intake, read-only GitHub MCP, watched links, selected text and browser-extension handoff retain their privacy/ownership boundaries |

Clicky's README explicitly states that newer HeyClicky code is private. Its public Worker exposes AI, STT and TTS routes, not a Gmail or WhatsApp connector. Copying this source does not supply private integrations. Suzzme's Gmail requires valid registered client IDs and a real sign-in; WhatsApp uses explicitly shared text, not live private database access. Browser-extension/native-host pairing remains subject to its existing deployment limitations.

Mac notch presentation and iPhone supported Live Activities remain Suzzme-owned. No fake Dynamic Island, cloud AI, autonomous UI clicking, silent consent, email collection, third-party telemetry or automatic login registration is carried over.

The [22 October 2026 source audit](../Design/CLICKY_SOURCE_RESEARCH.md) verifies the original checkout against all 80 snapshot hashes and adds deterministic local OCR-label guidance. Literal label requests can now reuse measured Vision boxes without model vision; ambiguous or incomplete observations cannot fall through to generated coordinates. The original conversion report remains historical evidence for the earlier menu/cursor adaptation.

Before-conversion source backup: `/private/tmp/Suzzme-before-clicky-conversion-2026-10-07.tar.gz`.
