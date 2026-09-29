# Suzzme Product Vision

Suzzme is a privacy-first personal intelligence layer for iPhone and Mac. It helps the user understand the meaningful parts of an authorized digital life, remember what matters, summarize the current day, and safely act when asked.

Suzzme is not a notification list, an admin dashboard, or a collection of separate chatbots. Every interface uses the same `SuzzmeCore`:

- iPhone
- Mac
- text
- voice
- Mac Presence
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

Sources must be honest and permission controlled. Supported sources may include Calendar, Reminders, Contacts, explicitly watched public webpages, and future public integrations. Suzzme must never claim access it does not have or inspect private app databases, Messages, WhatsApp, notifications, or other protected data through unsupported techniques.

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

## Safe actions

All supported mutations use the central action boundary:

```text
Understand → Plan → Check permission → Confirm when required
           → Authorize at commit → Execute → Verify → Respond
```

Generated language may understand and propose. Deterministic Swift code owns privacy, authorization, confirmation, execution, idempotency, and verification. Suzzme never says an action is complete until verification succeeds.

## Presence

On a MacBook with a notch, Suzzme uses a public-API, app-owned Presence surface directly below the physical notch. The hardware is never modified. A Mac without a notch uses an appropriate top-center surface. Both invoke the same `SuzzmeCore` used everywhere else.

On iPhone, the primary experience is the Suzzme Face, Talk to Suzzme, Type to Suzzme, What Matters Today, and Daily Summary. Suzzme respects Dynamic Island limitations and never draws a fake island or uses private APIs.

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
