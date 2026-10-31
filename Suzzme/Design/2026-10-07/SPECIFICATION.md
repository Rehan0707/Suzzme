# Suzzme — production UI/UX specification

Design edition 01 · 7 October 2026 · iPhone and macOS

**Present when needed. Invisible when not.** Suzzme gives a person a quiet place to ask, understand selected information and review an action. The established three-stroke Face is the signature; the surrounding interface remains familiar, neutral and spacious.

This document is the primary design specification. `index.html` is an editable, interactive design prototype; `studio.css` is the token and layout implementation; `studio.js` contains component templates, screen variants and eight review journeys; `tokens.json` supplies portable values. All sample text, permissions and account states in the prototype are explicitly simulated. It performs no inference, recording, screen capture, OAuth or calendar writes. Production integration and native device acceptance remain separate work.

## 01 — Foundations

### Product hierarchy

1. Ambient invocation: menu bar, supported session continuity, shortcut or in-app voice.
2. Compact assistance: one input, current state, a short answer and a contextual action.
3. Expanded assistance: readable conversation and optional selected-context detail.
4. Control: history, sources, personal context, settings and permissions.

Home is an entrance to assistance rather than an archive. History is a secondary destination. Preserve existing routes, intelligence engines, confirmation ownership and source-health behavior when implementing these designs. `home` and `today` currently share a label in `AppRouter`; do not expose both as duplicate top-level destinations. The proposed compact Mac toolbar can replace the permanent sidebar only in a validated implementation change; the prototype does not modify the app router.

### Native architecture mapping

| Design responsibility | Existing production owner | Requirement |
| --- | --- | --- |
| Semantic tokens | `SuzzmeTheme`, asset catalog | Add variants centrally, never literals in feature views |
| Established Face | `PresenceShared/SuzzmeFaceGlyph.swift`, `SuzzmeFace` | Preserve normalized three-stroke geometry |
| Presence composition | `SuzzmeAssistantPresenceView`, `SuzzmeHalo` | Motion and glow follow state and accessibility |
| Assistant status | `AssistantStateController`, `SuzzmeAssistantState` | One controller across surfaces |
| Voice | `VoiceSessionController` | Real permissions, cancellation, transcript finalization |
| Conversation | `AskSuzzmeView`, existing environment | No separate mock production conversation engine |
| Context | `ScreenContextPolicy`, source/context engines | Explicit invocation and session scope |
| Important actions | Existing Step 8 confirmation pipeline | Validate ownership and resolved target before execution |
| Sources/accounts | Source-health engine, `GmailAccountController` | Actual health, scope and authorization |
| Mac presence | `MacAssistantPresence`, invocation controller | App-owned public-API panels |
| iPhone continuity | `SuzzmeLiveActivityController`, widget extension | System-managed lifecycle; never inference or authorization owner |

### Navigation

**iPhone:** a compact native root, with Home as the primary entrance. History is a toolbar destination. Settings contains Personal Context, Sources/Connected Services and privacy. Do not add a second tab hierarchy alongside the existing root. Conversation pushes from Home; voice is a focused sheet/full-screen presentation with Return to Text. Preserve back navigation and the input draft.

**Mac:** menu bar and shortcut provide quick access. Expanded window has a restrained native toolbar: title, navigation menu, new conversation and context disclosure when context exists. A secondary context inspector appears only on request and at sufficient width. Settings uses a native Settings scene. Existing sidebar destinations remain reachable through the navigation menu or a user-invoked sidebar; no permanently open archive by default.

### Brand and logo

Use existing app-icon assets, never redraw them. The provided SVG Face is a vector translation of the existing normalized path: eye strokes `(14,43)→(29,28)→(44,43)` and `(56,43)→(71,28)→(86,43)`; smile `(34,62)→(50,77)→(66,62)`. Do not turn it into an orb, robot or sparkle.

| Placement | Treatment |
| --- | --- |
| App icon | Existing iOS and Mac asset-catalog images; platform masking is system-owned |
| Splash | Single centered mark, no caption; subtle static wash only |
| Welcome | Face above title, ample negative space |
| Light surface | Existing intelligence accent; neutral background |
| Dark surface | Existing pale accent or white brand mark where required by existing artwork |
| Menu bar | Monochrome template mark; accessible name “Suzzme” |
| Small panel | 24–32 pt Face beside state, no repeated large wordmark |
| About | One Face and name; actual version from the bundle |

## 02 — Colors

Native semantic colors take precedence over fixed hex values. Prototype values establish reviewable pairs; they do not replace `Color.primary`, `Color.secondary` or native tint behavior. Existing accent is muted purple, supported by violet/lavender glow. This preserves identity while meeting the brief’s violet presence direction.

| Role | Light | Dark | Production mapping |
| --- | --- | --- | --- |
| Canvas | `#FFFFFF` | `#121212` | `backgroundPrimary` / Canvas |
| Surface | `#F6F6F6` | `#212121` | `backgroundSecondary` / Surface |
| Elevated | `#FFFFFF` | `#292929` | Native elevated material or opaque fallback |
| Primary text | `#202024` | `#F3F3F5` | `textPrimary` / Color.primary |
| Secondary text | `#63636B` | `#AAAAB5` | `textSecondary` / Color.secondary |
| Intelligence accent | `#744575` | `#DAB1DA` | Existing AccentColor |
| Intelligence wash | `#F5EDF6` | `#302535` | Existing PurpleWash |
| Violet light | `#6842AC` | `#BC9BF2` | Presence-only lighting proposal |
| Lavender | `#CBC3E3` | `#CBC3E3` | Existing intelligenceSecondary; never small text on white |
| Normal link/focus | `#355CD7` | `#9CB9FF` | Native system tint; prototype fallback |
| Error text | `#A62A35` | `#FFAFB5` | Semantic destructive; paired with explanation |
| Warning text | `#805514` | `#E8BD76` | Semantic warning; local icon/text, never full red glow |
| Separator | `#D8D8DD` | `#46464E` | Native separator; Increased Contrast strengthens it |

Contrast is measured in `VALIDATION.md`. Essential outlines and focus indicators require 3:1 against adjacent surfaces; small text requires 4.5:1. Separators are supplemental grouping, never the only way to recognize a control. Purple is reserved for intelligence, not ordinary navigation or every primary button. Warmth comes from quiet materials, a restrained wash at launch and neutral surroundings; do not change the app’s established white Canvas merely for a decorative tint.

## 03 — Typography, spacing and geometry

| Role | iPhone default | Mac default | Native use |
| --- | --- | --- | --- |
| Large title | 34 pt regular/semibold | 28 pt semibold | Onboarding or root title only |
| Title | 28 pt semibold | 22 pt semibold | Screen heading |
| Section title | 20 pt semibold | 17 pt semibold | Short hierarchy |
| Body | 17 pt regular | 13 pt regular | Answers, normal labels |
| Secondary body | 15 pt regular | 12 pt regular | Explanations |
| Caption | 12 pt regular | 11 pt regular | Provenance, supporting status |
| Micro status | 11 pt medium | 10 pt medium | Brief nonessential metadata |

Use San Francisco via system styles. No custom font download. On Mac, longer answers may use 15 pt for comfortable reading while forms retain native density. Never put essential instructions in micro text. Match default system typography in production rather than hard-coded browser metrics. Avoid thin fonts and uppercase paragraph text.

**Spacing:** preserve 4, 8, 12, 16, 24, 32 and 48 pt. iPhone side inset is 20 pt at compact widths, 24 pt otherwise. Mac content inset is 24 pt. Reading width ≤680 pt; workspace ≤920 pt. Rows have at least 12–16 pt vertical breathing room, growing with content.

**Radii:** controls 12, grouped content 18, large panel 24, hero container 32 pt, matching `SuzzmeTheme`. Native buttons, menus and window frames retain their platform geometry. Use grouped lists and whitespace before adding cards. The 18 pt confirmation surface is content grouping; it is not a pattern to apply to every answer.

**Materials:** regular/ultra-thin material only for transient Mac panels and system-managed chrome where it separates the panel from the desktop. Answers and form content use solid surfaces. Reduce Transparency substitutes an opaque Canvas/Surface, not a weaker blur.

**Depth:** regular screens have no custom drop shadow. App-owned floating panels use a quiet platform shadow. The prototype frame shadow belongs to the review canvas, not the product. Glow is presence-only and does not reduce text contrast.

## 04 — Component contracts

All components support idle, focus, pressed, disabled and loading states where applicable. Disabled actions include a readable reason; never use opacity as the only explanation. iPhone actionable targets are at least 44×44 pt. Use at least 28 pt native Mac targets and 44 pt for prominent voice controls; the prototype uses 44 pt for shared controls.

| Component | Anatomy and variants | Behavior and accessibility | SwiftUI mapping |
| --- | --- | --- | --- |
| Primary button | Action label; neutral or intelligence variant | One dominant action; status during work; preserve width | Button, `.buttonStyle(.borderedProminent)` |
| Secondary button | Label, optional symbol | Bordered or plain by hierarchy; no competing purple fill | Button, `.bordered` / native toolbar action |
| Icon button | One SF Symbol | 44 pt hit area, label, Mac tooltip; visible focus | Button + Label with icon-only style |
| Permission row | Symbol, name, benefit, status, action | Not Asked / Allowed / Denied / Restricted / Unsupported | List row, system permission APIs |
| Setting row | Label, summary, trailing value/disclosure | Whole row navigates; value from actual setting | NavigationLink / Form |
| Toggle | Short label, optional explanation | Changes reversible preference; does not grant a permission | Toggle |
| Search field | Query, clear, result state | Live filtering; preserve query/focus; no-match copy | `.searchable` |
| Conversation input | Attachment, field, mic, Send/Stop | Return sends; Shift–Return adds line; growing field capped at ~6 lines then scrolls | TextField/TextEditor, safe-area inset |
| Assistant response | Face byline, readable answer, provenance, actions | Selectable text, semantic headings/lists; no heavy bubble | Text, Markdown/structured views |
| User message | Small neutral grouping | Align trailing; wraps; edit via explicit affordance | Text in compact neutral surface |
| Context chip | Source name, session scope, disclosure | Expands source/processing detail; removable when active | Label + Button; not color-only |
| Source indicator | Name, time, health | Healthy-empty is distinct from unavailable; no raw IDs | Existing source-health presentation |
| Confirmation panel | Action, resolved target, date/scope, cancel, confirm | Only explicit confirm executes; submitting disables double activation | Existing SuzzmeConfirmationSummary |
| Floating panel | Face/status, input, answer, context, expand | Escape policy, resize and focus restore | NSPanel + SwiftUI |
| Presence indicator | Stable Face, state, bounded light/motion | Accessible state value; idle still | Existing presence composition |
| Voice controls | Stop, End Listening, Return to Text, Cancel | Does not secretly resume recording; visible capture state | Existing VoiceSessionController |
| Device card | Device/capabilities, availability explanation | No marketing-based promises; no account device list without implementation | Runtime capability view |
| Empty state | Concise explanation, optional useful action | Only one dominant recovery; no fake illustrative content | Existing SuzzmeEmptyState |
| Error state | What happened, retained work, next step | Human copy, retry/cancel; no framework error dump | Mapped engine error presentation |
| Loading state | State text, optional progress, Cancel | Determinate progress only when measurable; no invented percentages | ProgressView + state label |

**Reusable variant axes:** platform, appearance, size class, text size, state, enabled, context scope and processing route. Presence has additional motion preference and theme axes. Components use content-driven heights and named slots, never flattened screenshots.

## 05 — Presence system

Public design labels map to the existing enum; do not introduce another production state machine.

| Design state | Existing state | Visual and copy | Exit |
| --- | --- | --- | --- |
| Idle | idle | Still Face; tiny indication or absent ambient panel; “Ready when you are” in app | Invocation |
| Listening | listening | Bounded glow; restrained input-level response; “Listening…” | Explicit stop, end or cancellation |
| Transcribing | transcribing | Slight settle; “Transcribing…” | Final transcript or recovery |
| Understanding | understanding | Gentle single transition; “Understanding…” | Context or reasoning |
| Thinking | reasoning | Slow boundary illumination; “Thinking it through…” | Result or cancel |
| Working | gatheringContext / planning / acting | “Checking your context…”, “Preparing that…” or “Working on that…” | Verified result, confirmation or error |
| Confirmation | awaitingConfirmation | Almost still; “Waiting for your confirmation” | User confirms or cancels |
| Speaking | speaking | Small utterance-progress response; “Speaking…” | Finish, interruption, text |
| Success | success | Brief 1.5-second settle then idle | Controller completion |
| Error | error | Stable Face, localized warning, recovery copy | Status settles; actionable error remains in content |

No private source names in passive progress. No animated internal reasoning. Face scales only a few percent and remains legible at 24 pt. Listening energy comes from actual input; speaking motion comes from utterance progress, not pretend audio amplitude. The browser prototype uses illustrative breathing; native production uses the existing bounded state-entry motion.

Timing: quick 180 ms, normal 280 ms, calm 450 ms; expansion 280 ms, response 420 ms and damping 0.9 from the existing tokens. Success/error illumination is brief. No idle loop. Stop animation when the scene is inactive. Reduce Motion removes scale, travel and rotation; keep static light and text. Reduce Transparency removes blur; Increased Contrast strengthens text and relevant edges. Every status has a color-independent label and VoiceOver value. Announce semantic changes once, not every animation frame.

## 06 — iPhone onboarding

The full content library includes eight steps, but the default path groups related content into a short journey. Optional steps can be skipped; no sign-in requirement to explore.

| Screen | Structure and exact copy direction | Actions / state |
| --- | --- | --- |
| Splash | Off-white/system Canvas; established centered mark; no text, artificial timer or loading bar | Exit when ready; no minimum dwell |
| Meet Suzzme | “Meet Suzzme”; “Your private personal companion, designed to help across your Apple devices.” | Get Started; Learn About Privacy |
| Built for your devices | iPhone and Mac descriptions; supported features depend on capability | Continue; Set Up Later |
| Private by design | Local processing where supported; network accounts clearly distinguished | Continue; privacy detail |
| Talk naturally | Voice and typing both first-class; explain request timing | Continue; no system prompt |
| Understand your context | Selected text/files; Mac snapshots require explicit choice | Continue; no passive capture |
| Connect what matters | Optional sources, no forced account authentication | Choose Sources; Continue Without Connecting |
| Permissions | Optional purpose-led rows, one access at a time | Feature-specific request; skip |
| You’re ready | Face briefly settles; “Suzzme is here when you need a little help.” | Open Suzzme |

Default review flow A is Splash → Meet → Privacy → Voice → optional Permissions → Ready → Home. Devices/context explanations can be disclosed from those pages rather than lengthening the required path. Persist progress; back and skip preserve completed choices. On Mac use a compact welcome window and teach invocation through a real action, never force a shortcut as the only exit.

## 07 — iPhone Home

Top: small wordmark or local greeting, History and Settings toolbar actions. Main: short heading, Face with still idle presence, one **Talk to Suzzme** action. Supporting suggestions: schedule, understand selected context, summarize something. Bottom: compact typed input with attachment and voice. With no permission, schedule leads to a benefit explanation, never invented events. Context suggestions lead to an explicit selection surface.

No mandatory greeting personalization, no fake briefing, no permanent transcript. Suggestions come from supported capabilities; remove or explain unavailable suggestions. Show “Nothing is being shared with Suzzme” until context is actually selected. Keyboard pushes the composer through native safe-area handling, scrolls content and keeps Send reachable. Greeting/Face reduce in height when keyboard or large type consumes space.

## 08 — Conversation and confirmations

Expanded conversation is a readable vertical document. User messages occupy compact trailing neutral blocks; assistant text sits directly on Canvas with a small Face byline. Response anatomy: answer heading when useful, paragraphs, lists, citations/provenance if used, Copy/Read Aloud/Share, and up to three purposeful follow-ups.

**Source rules:** distinguish general guidance from personal-source answers. A source disclosure shows readable name, selected item, retrieval/update time and permission scope. Never fabricate citations, imply fresh data from stale content, or expose UUIDs/checkpoints. A healthy source with zero items says “No matching items”; an unavailable source explains how to reconnect or allow access.

**Long answers:** 680 pt maximum measure, text selection, comfortable paragraph spacing; no horizontal scrolling for body. Stream when supported, but keep reading position if the person scrolls. Do not jump them to the bottom. Structured cards are reserved for actual events, files or action previews. Attachment chips are removable before submission. During work, Send becomes Stop and typed draft remains intact.

**Action preview:** “Ready to create this event”; event title, absolute resolved date, start/end, time zone, destination calendar, attendees and invitation consequences. Primary **Create Event**, secondary **Edit Request**, **Cancel**. “Tomorrow” in an illustrative design must become an absolute date alongside relative language in production. Change of resolved target invalidates the earlier approval. Double activation cannot produce two writes. If permission is absent, check it before presenting the actionable final confirmation. Cancellation never writes. Success is displayed only after the persisted result is verified. On failure, preserve the preview and offer a fresh review; do not auto-retry an ambiguous write. Deletion and external sending receive equally explicit labels and targets.

## 09 — Voice

Focused surface: large Face, accessible state label, optional finalized transcript, Stop, End Listening, Return to Text, Cancel. Listening must say when capture is active. Stop capture allows existing audio to finish transcribing; End Listening ends voice interaction; Cancel discards the active turn without side effects. Return to Text retains the draft/final transcript and halts capture.

Entering voice checks microphone and speech availability. Explain benefit, then request only necessary access. Denied/restricted access offers typing. An interruption/background transition follows the actual voice controller’s lifecycle and communicates stopped capture; animation cannot imply capture continues. Speaking is interruptible. Read Aloud does not start recording. No aggressive equalizer, fabricated waveform or automatic restart without an explicit controller-owned behavior the user enabled.

## 10 — Dynamic Island and non-Island iPhone

ActivityKit and WidgetKit own the surface. Use compact leading/trailing, minimal, expanded and Lock Screen presentations for a real eligible activity. The HTML design board illustrates **content regions**, not an overlay to render inside the iPhone app.

| Presentation | Contents | Privacy and lifecycle |
| --- | --- | --- |
| Compact | Tiny Face + meaningful phase symbol | No personal text; accessibility state |
| Minimal | Face / stable state indication | Still interpretable with competing activities |
| Expanded | Face, short state, Open Suzzme; essential supported session control only if implemented | No miniature conversation or free text entry |
| Lock Screen | App name, short public state, relevant deep link | Sensitive details hidden by default |
| Finished | Brief public completion when appropriate, then end | No permanent idle Presence activity |
| Stale / dismissed | Stop displaying fresh-progress claims; respect system dismissal | Never recreate the same dismissed session merely to keep presence alive |

Existing controller owns foreground sessions and uses transient style on supported versions. Preserve that lifetime policy. Broader background continuity requires an independently validated lifecycle change. A Live Activity is presentation; it does not grant recording access, authorize an action, or keep inference alive. Do not assume the app can force expansion, position, arbitrary glow around the hardware or a permanently active listening state. The current widget’s controls must match actually implemented deep links/App Intents.

**Without Dynamic Island:** identical in-app voice/context features; eligible Lock Screen Live Activities where supported; permissioned notifications for useful completed updates. No arbitrary overlays above other iOS apps. If Live Activities are disabled, hide setup-dependent actions and retain ordinary in-app status. Island failure never blocks the core interaction.

Primary references: [Apple Live Activities design guidance](https://developer.apple.com/design/human-interface-guidelines/live-activities), [ActivityKit](https://developer.apple.com/documentation/activitykit), [DynamicIsland](https://developer.apple.com/documentation/widgetkit/dynamicisland). The production team must verify target-OS behavior and device rendering at implementation time.

## 11 — Context and screen understanding

Before sharing: **Choose what to share**; “Nothing is being shared with Suzzme.” Choices are Selected Text, Selected File, Selected Photo, and Current Screen on Mac where supported. Use system pickers for files/photos. Camera is a proposed capability, not an assumed existing feature.

Active sharing: scope chip, readable source name, **This Session**, processing route and **Stop Sharing**. Explain/extract/summarize/ask actions operate on the chosen item. On Mac, capture a snapshot only after explicit invocation/selection and required screen permission. Clarify which app/window/display is selected before using it. Screen permission alone is not consent to continuous monitoring.

**Stop Sharing:** cancels outstanding context work, removes the item from active retrieval and clears transient captures under the context policy. It does not misleadingly promise deletion of previously saved conversation excerpts; offer the separate history deletion control. Production follows a defined retention policy, including temporary-file cleanup. Context changes invalidate draft action assumptions and earlier approvals where relevant.

iPhone cannot claim to read whatever app is on screen. Offer selected text, system share/import and user-selected media. Missing/expired context offers Choose Again; a refused permission leaves typed general questions available. The processing disclosure is specific: “Using selected text on this device” only when the selected route is local; any authorized network route names the service before submission.

## 12 — History

Search plus recent date groups, descriptive conversation titles and lightweight previews. Tap opens the actual conversation. Empty: **No conversations yet.** “Your recent conversations will appear here when you choose to keep history.” No-match state preserves the search query and offers clearing it. Search is still available to clear a no-match result.

Delete one conversation through a clearly labeled menu/swipe action with Undo while recoverable. Delete all uses a confirmation with explicit scope and a Cancel. If deletion is immediate and irreversible, omit Undo and require confirmation. Private content is not exposed in passive Mac panels or notification previews without opting in. History is local unless explicitly implemented sync is enabled and explained.

## 13 — Integrations and personal context

Two groups: **On Your Device** and **Connected Accounts · Network**. Device rows show category, purpose, permission, health, last update when meaningful and recovery. Connected account rows show service, account, authorized scope, health/update, Manage and Disconnect. No fake connected status, fabricated authentication or blanket “offline” claim.

Gmail currently has a controller and source: render exact granted scope rather than promising full mailbox access. This design’s sample connection shows metadata only and is not a verified API grant. OAuth remains a real external authorization journey. On failure, retain a disconnected state, explain retry or cancellation, and never infer success from closing a browser. Disconnect clears active account access and follows actual cached-data policy; describe whether cached content remains and offer deletion separately.

Personal Context contains allowed categories, selected session content, and approved saved preferences. Saved items show provenance, creation/update time, Edit where supported, and Delete. Empty: **No preferences saved yet.** Permission and preference controls are distinct. A “remember” switch cannot retroactively authorize an unrelated source. Do not show technical storage models.

## 14 — Settings

| Group | Destination and controls | Availability rules |
| --- | --- | --- |
| Suzzme | General, language, voice, appearance | Supported languages/voices only; clear current choices |
| Intelligence | Response length/preferences, contextual assistance, on-device capability | Read actual runtime state; no automatic cloud fallback |
| Personal Context | Source categories and saved preferences | Existing Memory and Sources destinations remain authoritative |
| Connected Services | Accounts and scopes | Separate network authorization from local permissions |
| Notifications | Opt-in proactive categories, preview privacy | Preference changes do not grant system permission |
| Privacy & Permissions | Permission status, current sharing, history/data deletion | Destructive labels state exact scope |
| Devices | Current-device capabilities; sync only when implemented | No fabricated paired-device list or inactive sync switch |
| About | Bundle version, privacy, acknowledgements, help | Actual release information; no debug labels |

Appearance: **System / Light / Dark**, matching the app’s existing preference. System follows changes immediately; override is reversible. Presence theme choices affect intelligence only. Device capability explains availability with a useful alternative; local saved-content browsing and supported deterministic actions remain available when the model is unavailable.

## 15 — macOS menu bar

Monochrome Face is the menu bar item. Popover width ~360 pt, expands vertically with text to a bounded scroll area. Contents: small Face + status, quick input, voice, latest safe interaction if any, useful supported suggestion, Open Suzzme, Settings. No full sidebar or history archive. Opening focuses input; dismissing returns focus to the invoking surface. Show shortcut hints in relevant menu commands.

Empty recent state remains honest. A private conversation title is excluded from passive presentation unless preview preference allows it. Menu bar hosting must behave correctly if the main window is closed; Quit stops capture, ends activities and removes panels.

## 16 — macOS notch and non-notch Mac

The notch is a hardware anchor. An app-owned top-center panel is positioned in the safe visible region **below or adjacent to** it, never drawn over the camera/sensor area. Idle panel disappears or shows only a nearly still minimal app indication according to the user’s presence preference. Listening and thinking use bounded light in the app-owned surface. Speaking uses a short state line and restrained motion.

Temporary useful information can expand the panel with a short public summary and View action, only with the relevant proactive preference enabled. No unsolicited private schedule title on the desktop. Window/display geometry and safe-area changes relocate or dismiss the panel. Full-screen apps, multiple monitors and screen-recording transitions require native acceptance. Macs without a notch use the menu bar and floating panel with equal functionality. Never make notch hardware a prerequisite for voice or context.

## 17 — macOS floating assistant

Compact NSPanel, ~420 pt wide, min ~320 pt where geometry allows; height follows content. Input, mic, current authorized context, compact answer, Expand/Continue in Full Window. Longer answers expand to the regular window rather than becoming an excessively tall utility panel. Plain text and supported documents can be dragged in through native transfer APIs with preview before use; generated text can be dragged/copied/shared out. Unsupported drops explain accepted types and do not discard the draft.

Invocation shortcut is user configurable; proposed default **Control–Option–Space** must be checked for conflict. Never use Spotlight’s shortcut by default. Escape dismisses a passive panel; during work it cancels/halts under the controller’s policy, with draft retained. Outside click behavior must not silently discard active voice or confirmation. Hover reveals affordances without hiding essential actions.

## 18 — macOS expanded window

Minimum existing window 640×500 pt; reading column ≤680; workspace ≤920. Native title bar and traffic lights, meaningful drag region, native menu bar. Main content leads. An optional context inspector of at least 280 pt appears only when the main column remains at least 420 pt; otherwise use a sheet/disclosure. Do not squeeze both at 640 pt. Resizing preserves draft and scroll position.

Commands: New Conversation ⌘N; Search History ⌘F within History; Settings ⌘,; Close Window ⌘W; Copy ⌘C on selection; Return to send; Shift–Return newline; Escape cancel/dismiss by context. Use native File/Edit/View/Window/Help and app menus as appropriate. Production keyboard shortcuts are not browser-global prototype shortcuts. Confirmation requires explicit activation of its labeled button, never accidental Return while editing another field.

## 19 — Permissions and privacy

| Permission/source | Benefit | Request timing | Refusal / scope |
| --- | --- | --- | --- |
| Microphone | “Lets you speak naturally with Suzzme.” | First voice request | Type instead; Settings recovery after denial |
| Speech recognition | “Turns your speech into text.” | Voice pipeline needs it | Supported language/service checks; type instead |
| Notifications | “Sends the reminders and updates you enable.” | Person opts into a category | In-app updates remain available |
| Calendar | “Uses your schedule when you ask.” | First schedule/context action | Read/write authorization differs; confirm writes |
| Contacts | “Finds people you ask about.” | Person asks for a contact-supported feature | Support limited access appropriately |
| Photos | “Uses only the photos you select.” | Selected-photo action | Prefer system picker; no blanket library access |
| Camera | “Captures an image when you choose.” | Explicit capture; only if implemented | Selected-photo/text alternatives |
| Files | “Uses a file you explicitly choose.” | Open/share/import action | System picker and selected scope; no all-files claim |
| Screen-related Mac access | “Uses the snapshot you choose.” | Explicit screen context action | Mac-only; system recovery; text/file alternative |
| Accounts | Exact service and granted scope | Explicit Connect | Cancel leaves local experience available |

Every row has icon, name, benefit, actual status and action. Status vocabulary: Not Asked, Allowed, Limited when applicable, Denied, Restricted, Unsupported. Denied leads to relevant Settings; restricted explains constraints without futile requests; selected picker access is not labeled global permission. Do not invoke all APIs on onboarding.

A sensitive-data disclosure answers: what is used, why, local versus named network route, session/retention scope, and how to stop. Personal data does not leave the device under a vague “smart” switch. Optional iCloud/device sync must describe categories and require explicit opt in once actually implemented. Cloud account access never receives an “entirely on-device” label.

## 20 — Errors, empty and loading states

| State | Copy | Next step |
| --- | --- | --- |
| Offline | “You’re offline. Connected accounts can’t update right now. Your draft is safe.” | Use Local Features; retry service when restored |
| Unsupported | “Not available on this device. You can still type, browse saved information and use supported actions.” | See Device Capabilities |
| Permission denied | “Microphone access is off.” | Review access in Settings; Type Instead |
| Model unavailable | “On-device intelligence isn’t ready.” | Check capability; preserve private route |
| Speech unavailable | “Speech recognition is unavailable.” | Return to Text; retain draft |
| Connection failure | “Gmail couldn’t connect. Your account wasn’t authorized.” | Review Connection / retry |
| Context unavailable | “The shared item is no longer available.” | Choose Context |
| Action failure | “The event wasn’t saved.” | Review details and access; verified retry only |
| Empty history | “No conversations yet.” | Ask Suzzme |
| Empty services | “Connect services when you want Suzzme to help with more of your day.” | Optional View Services |
| No context | “Nothing is being shared with Suzzme.” | Choose context when useful |
| Healthy-empty source | “No matching items.” | Adjust question; no reconnect warning |
| Loading | “Checking your context…” / “Preparing a response…” | Cancel; preserve draft |

Errors remain in content after the Face returns to idle. Never use a raw framework error, bright red full-screen treatment, spinning decoration or fabricated percentage. State transitions are controller events, not arbitrary UI timers.

## 21 / 22 — Light and dark variants

Every screen uses the same semantic structure in both appearances. Light Canvas is clean and predominantly white; Surface provides subtle grouping. Dark Canvas is near-black, with separate elevated surfaces and softened white text. Presence glow is controlled in both. Do not invert colors, blur all surfaces, or tint forms purple. Test selected, focused, disabled, loading and error content independently; readability cannot depend on a glow being visible.

## 23 — Prototype journeys

The review canvas provides Next/Back/Exit controls outside the product; the production app does not contain a “Preview Next State” button. Sample voice progression is manual, and permission outcomes are labeled simulations. Follow-up content is authored, not generated.

| Flow | Happy path | Required alternate path |
| --- | --- | --- |
| A — First launch | Splash → Meet → Privacy → Voice → optional Permissions → Ready → Home | Skip setup; denial does not block Home |
| B — Quick question | Home → Ask → Thinking → Response → follow-up | Cancel retains draft; no source fabricated |
| C — Voice | Activate → Listening → Understanding → Thinking → Speaking → Idle | Denied → typing; interrupt speaking; End Listening |
| D — Context | Invoke → choose/share → visible scope → ask → answer → Stop Sharing | No selection, expired item, refused screen access |
| E — Action | Request → understand → resolved preview → explicit confirm → verified success | Edit invalidates approval; Cancel has no side effect; write fails |
| F — Dynamic Island | Eligible invocation → system continuity → listening/thinking → short public state → app response → activity ends | Disabled/dismissed/non-Island → in-app continuity |
| G — Mac notch | Invoke → app-owned expansion → input → thinking → short answer → expanded window | No notch, display change, dismissal |
| H — Permissions | Feature → benefit → system request → allowed or denied → graceful continuation | Restricted/unsupported; no repeated system prompt |

Prototype Flow E cannot advance past the review without acknowledging Create Event · Preview. That button creates no real event. Native confirmation security remains the responsibility of the existing action pipeline, not this review scaffold.

## Editable design-file structure and Figma handoff

The studio catalog uses the exact requested 23 section names and order. HTML text, vector Face and symbols, component functions and CSS variables remain editable. This is a local web design file, **not a native Figma document**. No Figma file, Auto Layout objects or Figma prototype links have been created.

For a native Figma transfer:

- Create pages 01 Foundations through 23 Prototype Flows using the studio section names.
- Import `tokens.json` into variables with Light/Dark modes; bind semantic roles to components.
- Build component sets `Button`, `PermissionRow`, `SettingRow`, `Composer`, `Response`, `ContextChip`, `SourceIndicator`, `Confirmation`, `Presence`, `VoiceControls`, `DeviceCard`, `StateView`.
- Use variant properties `Platform`, `Appearance`, `State`, `SizeClass`, `Enabled`, `HasContext`, `ProcessingRoute`; Face stays a vector component.
- Vertical Auto Layout for pages and answers; horizontal Auto Layout for rows/toolbar/composer; wrapping Auto Layout for context chips; fill-container body, hug-content labels/buttons. Use minimum hit areas as component padding, never empty invisible overlap.
- Frames: iPhone 320/393/430 pt widths; Mac 640/920 pt widths; content-driven height, safe-area guides and accessibility-text variants. Add system-owned activity content-region studies separately from in-app screens.
- Layer names use `Screen/Home/Header`, `Screen/Home/Presence`, `Composer/Input`, `Context/Scope`, `Permission/Status`, `Confirmation/Target`.
- Connect eight flows, including cancel/deny/error branches, as described above. No flattened UI images.

## Implementation and acceptance

Sequence: semantic tokens and reusable components → presence mapping → onboarding/Home/conversation → privacy/context/sources → settings/history → Mac surfaces and native continuity → platform acceptance. Changes to production should use the established route and state owners; this design package does not claim production code integration.

Acceptance requires:

1. Every destination reachable, with no duplicate root navigation; old destinations remain accessible.
2. Every displayed primary action works or has a capability reason; no fake auth, source data or granted permission.
3. Exact target/scope on action confirmation; ownership checked; successful writes verified; cancellation side-effect free.
4. Voice input lifecycle stops correctly on cancellation/interruption; Return to Text preserves intended draft.
5. Context disclosure is truthful and Stop Sharing affects active retrieval and temporary capture lifecycle.
6. VoiceOver reading/focus order, named controls, meaningful state announcements, keyboard-only operation, Switch Control reachability.
7. Small/standard/large iPhone, accessibility Dynamic Type through the largest native category, landscape where relevant, keyboard visible, safe areas respected.
8. Minimum/normal/large Mac windows, optional inspector reflow, multiple displays, full-screen behavior, notch and non-notch geometry.
9. Light/dark, Increase Contrast, Reduce Motion, Reduce Transparency; text contrast and essential boundaries verified.
10. Live Activity hardware, stale/dismissed/end behavior, competing activities and lock-screen privacy. Simulator rendering does not count as hardware acceptance.
11. Native iOS/macOS Swift 6 builds and repository validation for production edits. Preserve accepted Step 6 53/53, Step 7 90/90, Step 8 198/198 and accepted Step 9 source-health count, plus later existing checks.

This artifact can be reviewed now; shipping the native changes requires implementation and the native checks above. See `VALIDATION.md` for checks actually performed on this package and remaining limits.
