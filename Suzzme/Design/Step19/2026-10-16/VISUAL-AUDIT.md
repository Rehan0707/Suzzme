# Step 19 visual audit

Read all eight requested Step 18 reports/manifests and directly inspected the six requested before/after images. The Step 18 Assistant is wider and has a named Sources action; Voice has one pace control; Integrations moves search ahead of its disclosure and defaults to supported/limited entries. Those improvements remain.

Five priorities below distinguish product defects from unresolved acceptance gaps. The screenshots do **not** support inventing five additional confirmed visual defects.

| Priority | Evidence | Finding and disposition |
|---|---|---|
| P1 — iOS first screen | Owner's prior report; no accepted current iOS image | White-screen cause remains unverified. Build/install now pass; launch and simulator process query time out. Infrastructure/runtime acceptance gap, not a confirmed UI root defect. See IOS-STARTUP.md. |
| P2 — conversation position | Production Assistant scrolled to earlier turns; existing lifecycle callbacks retained a visible-bottom flag | No direct route to the latest turn. Added Latest message and native visibility tracking on iOS 18+/macOS 15+. First lifecycle-based attempt hid the button; coordinate-based attempt kept it visible at the bottom. Both unsuccessful iterations are retained. |
| P2 — Daily Summary density | New production before/daily-summary.jpg plus Step 18 daily-summary image | Narration forms a dense block and adjacent dated items have weak boundaries. Added line spacing, bounded narration measure and separators between existing items; no fact rewriting or speech changes. |
| P2 — native collection rhythm | Production before/privacy.jpg at initial scroll position, compared with page-based screens | First section starts close to the toolbar. Shared Mac collection top padding aligns readable forms/lists with page spacing. Initial content-margin attempt had no visible effect and was replaced. |
| P1 evidence — presence detail | Step 18 visual audit and supplied presence fixture contact sheets | Response/resolved-target text is absent in ImageRenderer fixture bodies although production source supplies it. This is not yet a confirmed native-panel defect. Hardware/native-panel text and confirmation acceptance remain pending; no speculative confirmation rewrite. |

Additional source-audit improvements: important Assistant states now request native accessibility announcements; selection haptics now require an active scene. Neither a source audit nor a screenshot establishes physical feedback or spoken VoiceOver acceptance.

Home, Today, Personal Memory and the existing Settings/Integration card hierarchy were retained. Calm negative space alone is not a defect. The original Face, provider marks and purple intelligence identity are unchanged.

The iteration folders contain actual production captures of intermediate changes, including rejected scroll/inset attempts. Only evidence/after is final evidence. iOS previews are not substituted for runtime screenshots.
