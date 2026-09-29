---
name: suzzme-ui-foundation
description: Preserve Suzzme's Apple-native visual identity when creating or reviewing product UI, design-system tokens, reusable components, colors, typography, spacing, materials, and accessibility behavior.
---

# Suzzme UI Foundation

Use the existing `Suzzme/DesignSystem` before adding UI primitives. Search for an equivalent component or token first. Keep business logic in the validated engines and environment; SwiftUI consumes state.

## Identity

- Preserve `SuzzmeFace` and `SuzzmeMark`. The face is three minimal strokes; never replace it with a sparkle, orb, robot, brain, or waveform.
- Native app surfaces use semantic system structure. Purple identifies active intelligence and must not recolor ordinary navigation, forms, cards, or settings.
- Presence Themes affect only presence/intelligence surfaces.

## System

- Use semantic tokens from `SuzzmeTheme` for background, surfaces, text roles, separators, spacing, radii, and motion. Avoid new literal colors and arbitrary numeric constants in feature views.
- Use system typography and SF Symbols. Custom hero type is reserved for launch/onboarding brand moments.
- Prefer whitespace and native grouping over repeated cards. Materials require a hierarchy purpose and readable opaque fallback.
- Normal UI has minimal shadow. Glow belongs only to active intelligence presence.

## Accessibility and platforms

- Preserve Dynamic Type, VoiceOver labels, 44-point controls, color-independent status, Reduce Motion, Reduce Transparency, and Increased Contrast.
- iPhone uses compact native navigation. Mac uses sidebar/split-view, resizable content, keyboard behavior, and comfortable maximum widths.
- Light mode stays clean and mostly neutral. Dark mode uses semantic dark surfaces with controlled presence glow.

## Product principles

For every new surface, check Purpose, Agency, Responsibility, Familiarity, Flexibility, Simplicity, Craft, and Delight. Prefer useful work, clear control and recovery, privacy-safe behavior, familiar Apple conventions, adaptive accessibility, and restrained detail. Delight should come from excellent behavior rather than decoration.
