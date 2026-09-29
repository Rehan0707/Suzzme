---
name: suzzme-screen-patterns
description: Apply established Suzzme screen patterns when changing onboarding, Home, Ask Suzzme, Memory, Sources, Settings, confirmations, permissions, or empty/loading/error states.
---

# Suzzme Screen Patterns

Preserve existing routes and working controls. Do not create UI-only assistant state, fake source status, fake authentication, fake permissions, or Step 10 briefing/relevance behavior.

- **Launch/onboarding:** minimal splash; Face-led introduction; short trust and capability explanations; native controls; truthful account/permission availability; substantial whitespace.
- **Home:** calm entrance to personal intelligence, not chat history. Face/presence, short context, one primary `Talk to Suzzme` action, typed interaction second, only useful supporting information.
- **Ask Suzzme:** restrained transcript/result hierarchy without message avatars or heavy bubbles. Voice, send, cancel, Assistant State, and Step 8 confirmation use the existing pipelines.
- **Confirmations:** state the resolved action and target. Destructive actions use explicit labels. Never reduce Step 8 confirmation ownership or verification.
- **Memory:** explain what is known, provenance, and safe delete controls in human language. Never expose SwiftData terms.
- **Sources:** Apple Settings-like rows with purpose, permission, Step 9 health, last update, and recovery. Keep healthy-empty distinct from unavailable.
- **Recent information:** human summaries and source/date only. Hide UUIDs, fingerprints, checkpoints, and normalization details.
- **Settings:** group Voice, Presence, Memory, Sources, Privacy, account/profile, and About without duplicate destinations. Themes alter only intelligence presence.
- **States:** every major screen gets a short empty, loading, or actionable error state. Never show raw framework errors.
- **Navigation:** compact iPhone navigation stays small; secondary systems belong under Settings or contextual links. Mac keeps its native sidebar and Settings scene.
