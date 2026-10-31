# Sentient OS knowledge-source comparison

Reference inspected: the local `sentient-os-main` checkout and the Knowledge Sources screenshot supplied on 23 October 2026. This is an independent Suzzme implementation; no Sentient source file was copied into the app. The reference checkout declares AGPL-3.0 in its root `LICENSE`.

## What the reference actually does

| Behavior | Source evidence | Suzzme status |
| --- | --- | --- |
| The Knowledge Sources screen groups email/calendar, conversations, other apps, and local folders. | `sentient-os-main/Sentient OS macOS/Views/KnowledgeSourcesPicker.swift:73-78`, `:145-293` | The Mac Sources screen now uses grouped source cards with connection and summary status. |
| One persisted selection feeds the UI, Analyze Now, and overnight processing. Its four-source minimum is a Sentient onboarding rule. | `sentient-os-main/Sentient OS macOS/Sources/SourceSelection.swift:66-67`, `:105` | Suzzme keeps its own explicit per-source permissions and summary opt-ins. It does not invent a four-source requirement or count unavailable apps. |
| Local file roots and selected chats become connector inputs for an iterative read pass. | `sentient-os-main/Sentient OS macOS/Ingestion/RunSource.swift:1-49` | Suzzme supports selected text/Markdown, one-time bounded folder import, and a separate opt-in local WhatsApp source on Mac. It does not keep folder bookmarks/watchers or scan iMessage databases. |
| The read pass yields bounded summaries; the cycle files them into a knowledge base, prepares proactive output, and only clears temporary summaries after success. | `sentient-os-main/Sentient OS macOS/Proactive/ProactiveCycle.swift:5-18`, `:68-69`, `:231` | Suzzme uses its own bounded InformationStore and ProactiveIntelligenceEngine. It does not use Sentient's vault or model-executor chain. |
| Sentient schedules an overnight wake and can run its shared analysis owner around 3 AM. | `sentient-os-main/Sentient OS macOS/Scheduling/OvernightScheduler.swift:1`, `:134-140`, `:177-185` | Suzzme prepares at the user's preferred time while its app is running and the Mac is awake. It does not install a wake helper or claim to run while quit. |

## Suzzme's active path

`SourcesView` shows actual permission, account, and summary-opt-in state. `AppEnvironment.runScheduledBriefing` refreshes enabled `InformationSource` adapters, then calls `core.prepareProactiveBriefing` with live Calendar, Reminders, and saved activity items. `ProactiveIntelligenceEngine` combines these with bounded information events and memory evidence, ranks current candidates, and stores a Daily Summary. `BriefingView` now shows which source families contributed. `BackgroundTasksView` shows the owned run, next time, limitations, and recent result receipts.

The functional source set currently includes Apple Calendar and Reminders, Gmail, user-shared message text, opted-in Google Calendar/Drive/Docs/Sheets/Tasks resources, opted-in connected-app summary resources where implemented, explicitly selected local WhatsApp chats on Mac, and optional same-day Local Knowledge excerpts on Mac. Account connection alone does not enable automatic intake. Apple Mail and automatic iMessage reads remain unavailable. Local Knowledge folder imports are one-time, bounded, text/Markdown-only selections; the folder itself is not watched. Daily Summary use requires a separate explicit toggle, and old library notes are not replayed on later days.

The remaining gap to full Sentient parity is substantial: unsupported provider adapters (including Apple Mail and automatic iMessage), persistent folder roots, broader local-file formats, Sentient's cross-source vault and proactive research/execution stages, and its overnight wake helper are separate implementations with their own authorization, data-lifecycle, and validation work. The new UI does not claim those behaviors exist.
