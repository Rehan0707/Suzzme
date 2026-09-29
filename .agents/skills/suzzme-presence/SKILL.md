---
name: suzzme-presence
description: Preserve Suzzme's state-driven Face, Presence Themes, voice presentation, Mac notch surface, iPhone compliance, and accessible animation when modifying assistant-presence UI.
---

# Suzzme Presence

Reuse `SuzzmeFace`, `SuzzmeAssistantPresenceView`, `SuzzmeHalo`, `SuzzmePresenceTheme`, and the existing Assistant State. Do not create another presence state enum, voice pipeline, or state machine.

- Map visuals from Assistant State: idle is nearly still; active processing uses restrained motion; confirmation is explicit; success/error is brief and then calm.
- Theme colors apply to active intelligence only. Keep default violet luminous and restrained; never paint the whole app with the selected theme.
- Respect the chosen animation preference plus Reduce Motion, Reduce Transparency, Increased Contrast, scene activity, and platform geometry.
- The Face must remain recognizable in every state. State text or accessibility value must accompany visual expression.
- Mac uses the existing public-API app-owned top-center panel. Detect notch geometry and keep a deliberate non-notch fallback. Never claim or attempt physical-notch recoloring.
- iPhone must not fake or draw around Dynamic Island. Use only supported system mechanisms when a later qualified feature explicitly requires them.
- Avoid permanent animation, polling, giant assistant windows, Siri-like orbs, and Apple Intelligence imitation.
