---
name: suzzme-ui-validation
description: Validate Suzzme UI changes across iPhone and Mac for visual consistency, reachability, accessibility, adaptive layout, presence behavior, and locked functional regressions before acceptance.
---

# Suzzme Ui Validation

Build success alone is insufficient. Inspect real rendered states using previews or simulator screenshots when available, then run repository validation.

Check:

- every production screen is reachable and no root navigation is duplicated;
- primary controls work, are intentionally disabled with explanation, or are clearly previews;
- no raw UUIDs, framework errors, debug labels, or internal policy/state names appear in production UI;
- `SuzzmeTheme`, system typography, native controls, semantic colors, and Presence Theme boundaries are followed;
- Suzzme Face remains recognizable and assistant state has semantic text/accessibility value;
- VoiceOver, Dynamic Type accessibility sizes, 44-point targets, focus order, Reduce Motion, Increased Contrast, and Reduce Transparency;
- light/dark mode; small, standard, and large iPhone widths; keyboard presentation; compact/regular size classes;
- minimum, normal, and large Mac windows; sidebar behavior, Tab/Return/Escape behavior where supported; notch and non-notch presentation;
- Step 8 confirmation displays the resolved action and cannot bypass ownership;
- Step 9 source health distinguishes healthy-empty from unavailable and Recent Information hides technical identifiers;
- no fake Dynamic Island, source data, account behavior, permission state, or Step 10 feature.

Run iOS and macOS Swift 6 builds plus all existing validation scripts. Preserve at least Step 6 `53/53`, Step 7 `90/90`, Step 8 `198/198`, and the accepted Step 9 count. Simulator checks never count as hardware acceptance.
