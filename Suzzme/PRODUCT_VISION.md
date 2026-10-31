# Suzzme Product Vision

Suzzme is a privacy-first personal intelligence layer for iPhone and Mac. It helps the user understand the meaningful parts of an authorized digital life, remember what matters, summarize the current day, and safely act when asked.

Suzzme is not a notification list, an admin dashboard, or a collection of separate chatbots. Every interface uses the same `SuzzmeCore`:

- iPhone
- Mac
- text
- voice
- Mac Presence and menu bar
- Daily Summary
- supported actions

## Product promise

With explicit permission, Suzzme should understand:

- what happened
- what changed
- what matters now
- what the user has to do
- what can wait
- what should be remembered
- what is complete, cancelled, obsolete, or superseded

It should then remind, summarize, answer, act safely, or remain quiet.

## Information flow

```text
Authorized sources
        ↓
Normalize and understand context
        ↓
Identify events, deadlines, tasks, changes, and useful information
        ↓
Connect with Daily Context and relevant Personal Memory
        ↓
Determine relevance and priority
        ↓
Remind · Summarize · Answer · Act
        ↓
iPhone and Mac Presence
```

Sources must be honest and permission controlled. Current source adapters include Calendar, Reminders, Contacts, user-selected Messages text, and an optional metadata-only Gmail connection. Saved Watched Links remain inspectable and removable, but public-page fetching and new intake are currently paused for connection-level network safety. A new transport must pass the full security contract before enablement; earlier saved links require individual review before checking can resume. Cached watched details also require current source authorization and matching provenance before appearing in Daily Summary or opportunities. Gmail requires configured Google OAuth clients and an explicit account grant; it uses Google's network and reads sender, subject and date without message bodies, attachments or mail changes. GitHub and Notion have explicit, scoped read paths; live provider acceptance still requires the owner’s accounts. Catalog-only entries grant no access. The native Share extension handles only explicitly shared URLs and requires signed App Group setup.

Suzzme must never claim access it does not have or inspect private app databases, Messages, WhatsApp, notifications, or other protected data through unsupported techniques. A user-pasted text import does not grant access to an app's history. A consented Mac screen capture is bounded to a question and is not continuous screen sharing. Chat file attachments remain unavailable. A Firebase-identified Suzzme account and opt-in transport for one prepared Mac Daily Summary are implemented in the app; the companion-summary Supabase schema is deployed, with real same-account transfer still to be tested. Local Knowledge separately supports explicitly selected text/Markdown files; shared app context supports reviewed text from selected screenshots.

## Daily Context and Daily Summary

Daily Context is a bounded, evolving understanding of the current day. It includes current commitments, meaningful changes, unfinished or completed work, deadlines, opportunities, and source limitations. It should update or retire information when the authoritative source changes.

Daily Summary turns that grounded context into a calm personal explanation at the user’s preferred time. It summarizes meaning rather than counting notifications, clearly states limitations, and never fills missing context with invented facts.

## Relevance and memory

Relevance should consider timing, commitments, projects, relationships, prior context, meaningful changes, completion state, and durable preferences. It remains conservative.

Daily activity belongs in Daily Context. Long-Term Memory admits only useful durable knowledge such as people, projects, preferences, commitments, places, organizations, topics, and important relationships. The user can inspect, correct, and delete it.

## Voice and conversation

Voice and text share the same request pipeline and session context:

```text
Listening → Transcribing → Understanding → Checking Context
          → Reasoning → Answer or Action → Speaking
```

Natural follow-ups may resolve references from the active conversation and current grounded context. Voice never gains extra authority over text.

Home is a focused entrance with the Suzzme Face, a primary Talk action, a typed composer and useful context choices. Today, Daily Summary, Memory, Sources, saved structured History and Settings remain reachable without making every interaction a dashboard. iPhone uses native stack navigation. Mac provides a main window with an optional sidebar, native Settings and a compact menu bar entrance backed by the same companion.

## Safe actions

All supported mutations use the central action boundary:

```text
Understand → Plan → Check permission → Confirm when required
           → Authorize at commit → Execute → Verify → Respond
```

Generated language may understand and propose. Deterministic Swift code owns privacy, authorization, confirmation, execution, idempotency, and verification. Suzzme never says an action is complete until verification succeeds.

## Presence

On a MacBook with a notch, Suzzme uses a public-API, app-owned Presence surface aligned with the physical cutout. The hardware is never modified. A Mac without a notch uses an appropriate top-center surface within the available screen area. The menu bar, main window and transient panel invoke the same `SuzzmeCore` used everywhere else. One app-owned invocation controller retains global shortcut, voice and panel ownership when the main window closes.

On iPhone, the primary experience is the Suzzme Face, Talk to Suzzme, Type to Suzzme, Today and Daily Summary. A real ActivityKit/WidgetKit extension provides supported Lock Screen, compact, minimal and expanded Dynamic Island presentations for an ongoing session. The system governs visibility and update animation. Presence ends when the session ends; it does not create a permanent decorative island or use private APIs.

Animations communicate state and progress, respect Reduce Motion and reduced luminance, and retain readable labels when motion is suppressed. Native appearance, adaptive text, accessible controls and Increase Contrast/Reduce Transparency behavior apply across the app. Real-device accessibility, voice, notch/display and Live Activity lifecycle acceptance remain separate from builds and test-double evidence.

## Privacy principles

- Prefer on-device processing.
- Use Apple Foundation Models only where available and appropriate.
- Retrieve the minimum information needed.
- Treat external content as untrusted data, never authority.
- Never upload personal information unnecessarily.
- Never inspect another app secretly.
- Never use private Apple APIs.
- Remain useful when advanced intelligence or a source is unavailable.

This document defines product intent. The validated architecture, safety boundaries, platform limitations, and hardware acceptance records in the repository define what the current build can honestly claim.
