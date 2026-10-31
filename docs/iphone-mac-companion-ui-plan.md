# iPhone companion UI plan

## Product model

The Mac is the primary source hub. A person signs into the same Suzzme account on Mac and iPhone; the Mac reads only sources they separately authorize, prepares a bounded Daily Summary, and makes that prepared result available on iPhone. Google sign-in identifies the Suzzme account. Gmail, Google Calendar, and other Google source permissions remain separate choices; sign-in alone does not grant access to them.

The iPhone is the place to **see and ask about the day**. It should not repeat the Mac's setup process or request Calendar, Reminders, Contacts, and app permissions merely to display a Mac-prepared summary. Microphone and notifications are optional, requested when their own features need them. iPhone-local sources can remain an explicit optional addition later.

The app now has an opt-in, versioned prepared-summary transport, Mac publish controls, and a signed-in iPhone Today screen. The database change in `supabase/migrations/20261025190000_companion_summaries.sql` was applied to the production Supabase project on 26 October 2026; a real same-account Mac-to-iPhone transfer remains to be acceptance-tested. This implementation exchanges one bounded summary per account; it does not provide live Mac presence, remote source reads, or a Mac wake/refresh command. The iPhone shows the last received time and treats an older or offline copy as stale.

The pictured foldable iPhone form factor is handled by one adaptive SwiftUI flow: a narrow outer display uses a single column and a wider unfolded display uses two columns where space allows. The layout has 360-point and 720-point previews. No specialized foldable hardware API, simulator, or physical device acceptance is claimed.

## Information architecture

### iPhone

Use a small native tab bar with **Today**, **Ask**, and **Settings**. Today replaces the current split between Home and Today on iPhone; a Daily Summary detail is one tap away. Sources, Memory, and account/device controls live in Settings and are reachable contextually from Today. The mascot remains the friendly entry point, with the user's selected color reflected in primary actions, presence, and restrained glass tint. Keep text and content surfaces readable in neutral semantic colors.

1. **Today** — first screen after sign-in and mascot selection. A short greeting and Suzzme mascot, current-day headline, the prepared summary, then only the next few useful items. Show “From your Mac · Updated 8:30 AM” and a plain-language coverage note next to the summary. One prominent “Ask Suzzme” action opens a conversation grounded in the synchronized summary.
2. **Daily Summary** — narrative first, then sections such as Up next, What matters, and Changes. Each item carries its source and relevant time. A compact “Sources in this summary” disclosure explains exactly what contributed, what was unavailable, and when Mac last checked. “Listen” is available when voice is supported. Avoid a large enclosing hero card; use whitespace, headings, separators, and glass only for controls or a compact floating composer.
3. **Ask** — typed or voice conversation with the same mascot and assistant-state behavior already used elsewhere. Questions about the day use only the synchronized summary and its approved evidence. If the question needs a source that is only on Mac, say so and offer to open it on Mac or try when Mac is available; never imply live iPhone access to Mac apps.
4. **Settings** — Account & Mac, Sources, notifications, voice, mascot/appearance, memory, privacy. “Sources” is a readable list of what the Mac contributes, not a row of iPhone permission prompts. Each source has a human status, last check, and “Manage on Mac” guidance. iPhone-local permissions appear only for opted-in iPhone features.

### Mac

Keep the Mac sidebar and source controls. Add a clearly named **iPhone sharing** section near Daily Summary settings: which prepared summary categories may appear on iPhone, latest publish time, device delivery status, pause, and remove. Manage raw source permissions on Mac. Google source selection stays separate from account sign-in. A Mac preview of “What iPhone will see” should use the exact bounded summary payload, with sensitive notification previews off by default.

## First-run flow on iPhone

1. Show a short sign-in explanation: “Sign in to the same Suzzme account as your Mac to see your day here.” Keep the existing local/guest path, but label it clearly as **Use this iPhone only** with no Mac summary.
2. Let the person choose mascot color, then offer a two-step setup: **Connect to your Mac** and **Choose notifications**. Do not start with a long source-permission carousel.
3. If no signed-in Mac has published yet, show a genuine waiting state: “Your Mac has not shared a Daily Summary yet.” Primary action: **Open setup steps**. Include the exact account email and a short Mac checklist: sign in with the same account, choose sources, enable iPhone sharing, prepare a summary. Do not show a simulated paired Mac.
4. Once the first summary arrives, transition to Today. The mascot can acknowledge arrival once, with Reduce Motion respected; the data remains the focus.

## Today state model and copy

| State | Visible message | Primary action |
| --- | --- | --- |
| Current summary | “From your Mac · Updated 8:30 AM” | Ask about your day |
| Mac preparing | “Your Mac is putting today together” | View last summary, if one exists |
| Mac offline or asleep | “Your Mac is unavailable. Showing the last summary from 8:30 AM.” | Open last summary |
| Outdated summary | “This summary may be out of date” with its exact timestamp | Request a refresh on Mac, if supported |
| Some sources unavailable | “Some sources could not be checked” with affected source names | Review source status |
| No sources selected | “Choose what Suzzme can use on your Mac” | View Mac setup steps |
| Account mismatch | “This iPhone and Mac are signed into different Suzzme accounts” | Review account |
| Sync failed | “Your latest summary could not reach this iPhone” | Retry and view last available summary |
| Guest/local mode | “Mac summaries need the same Suzzme account on both devices” | Sign in |

Never equate “nothing new” with “not checked.” Do not show a success state unless an actual summary has arrived. Pull-to-refresh checks delivery status; it must not imply the iPhone can wake or read an offline Mac. Any Mac refresh request needs an acknowledged or failed state.

## Trust, control, and data boundaries

- The proposed cross-device payload contains the prepared Daily Summary, bounded structured day items, human source labels, source limitations, generation time, time zone, and freshness status. It excludes raw email bodies, chats, app databases, attachments, source credentials, and Mac permissions.
- Account sign-in and source authorization are separate. Source choices and iPhone sharing are opt-in, revocable, and reflected in both apps. Removing access retires affected summary content and any synchronized copy; stale cached content must not be presented as current.
- The transport needs account-scoped authentication, protected storage, explicit retention/deletion, and a privacy review before release. The current identity-only account table is insufficient. The UI must be backed by actual device and sync state, never a local “connected” preference.
- Notification content is discreet by default. The user can opt into a brief summary notification after the first real summary exists. A lock-screen preview must not reveal private source details by default.
- “Ask about your day” is limited to synchronized evidence. Mac-only actions and source reads require the Mac to be reachable and a separate supported handoff; the iPhone should not silently act through a Mac permission.

## Implementation order and acceptance

1. Define a versioned, minimal cross-device summary contract and the consent, revocation, retention, and account/device-status model. Reuse the existing proactive snapshot as the source of truth; do not create a second intelligence engine.
2. Implement authenticated Mac publish and iPhone receive/cache, including logout, account switch, partial source coverage, stale data, and deletion. Confirm that Google source scopes remain separate from Google account sign-in.
3. Build iPhone Today, Summary, Ask grounding, and Settings states from that real model. Preserve the existing mascot/presence and SwiftUI design tokens; replace the iPhone hamburger-first navigation with the compact tab structure.
4. Add the Mac sharing controls and exact iPhone preview. Verify no raw source content or credentials are in the cross-device payload.
5. Validate signed-in and guest flows, two accounts, first sync, Mac offline, expired source grant, revoked sharing, time-zone change, Dynamic Type, VoiceOver, Reduce Motion/Transparency, light/dark mode, and narrow iPhone widths. Use actual Mac and iPhone devices for final connection and notification acceptance.

**Release gate:** until the real transport and consent model exist, show truthful local-mode UI. Do not label the current device-local Daily Summary as “From your Mac.”
