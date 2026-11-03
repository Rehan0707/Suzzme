# Suzzme landing page — next iteration

Prepared 3 November 2026. Planning only; site implementation is unchanged by this document.

## Basis and scope

Read the GitHub default-branch root README and technical README, alongside local PRODUCT_VISION.md and LAUNCH_READINESS.md. GitHub's open-issue search returned no issues to incorporate. The scope is the next landing-page iteration, with native release dependencies recorded separately.

Sources:
- https://github.com/Rehan0707/Suzzme/blob/main/README.md
- https://github.com/Rehan0707/Suzzme/blob/main/Suzzme/README.md
- ../Suzzme/PRODUCT_VISION.md
- ../Suzzme/LAUNCH_READINESS.md

The root README establishes the product story; the technical README supplies narrower capability boundaries. Some documents contain older contradictory statements. Verify disputed details against current implementation and acceptance evidence before publishing claims.

## P0 — Reconcile the product story and claims

Lead with “Your day, summarized. Your next steps, clearer.” Retain the blue companion and warm editorial styling. The first viewport should explicitly explain that the Mac prepares a contextual Daily Summary and suggested plan, with an optional signed-in iPhone companion.

Create one content/claims checklist covering:
- Preferred summary time, not guaranteed delivery at an exact minute. Automatic preparation requires separate opt-in, an awake Mac, and a running app; wake/relaunch can catch up.
- iPhone receives and reads a prepared result; do not imply iPhone source scanning, independent AI generation, or Mac remote control.
- Optional account transport means “all data never leaves hardware” is too broad. Describe local private reasoning separately from source retrieval and opt-in summary sharing.
- Remove absolute “zero battery drain” and “never hallucinates” claims from future website copy and propose corresponding README corrections.
- Foundation Models depend on supported hardware, OS, locale, and model readiness. App minimum OS support is not a promise of model availability.
- Gmail header access and separately consented message analysis differ. Header-only Gmail is not a Daily Summary source in the current technical README.
- WhatsApp is selected local Mac chats, not a WhatsApp API connection or iPhone chat reader.
- Live Activities represent bounded sessions; system timing, placement, and transitions are not guaranteed by a browser demo.
- Provider code availability and historical tests do not establish live-provider or distribution readiness.

Done when every prominent capability claim has a specific source and unresolved claims are omitted or qualified.

## P1 — Build one coherent morning story

Extend the existing context → summary → plan demo rather than adding disconnected feature cards.

1. Choose a preferred morning time and explicitly enable the sample automatic-preparation scenario.
2. Select illustrative Calendar, Reminders, and opted-in source summaries. Changing a selection updates both the summary and plan.
3. Animate gathering → reasoning → Daily Summary ready with a clear progress label.
4. Show the grounded explanation: a meeting, a priority, an open focus window, and why each suggested step fits.
5. Demonstrate a changed commitment: moving the sample meeting changes the available focus window and suggested plan.
6. Provide reset and replay; keep sample labels and avoid calendar/mail mutations.

Distinguish existing calendar commitments from proposed focus time. Any preview of creating an event must show explicit confirmation and a clearly simulated result.

Done when sample inputs consistently drive the explanation and schedule, including an empty-source state and a conflict state.

## P1 — Make Mac and iPhone the central visual story

Add a paired device section: Mac prepares → opt-in account sharing → iPhone reads. Reuse the README's real app screenshots after checking them against current UI:
- docs/Previews/home-summarize-day-composer-mac.png
- docs/Previews/sidebar-mascot-glass-mac.png
- docs/Previews/mac-notch-listening.png
- docs/Previews/iphone-companion-current.png
- docs/Previews/iphone-today-guest.png

Build a Mac top-center presence preview with a non-notch fallback. Show preparation, completion, and opening the summary. Add a short Mac Ask Suzzme voice/text example; describe iPhone speech as playback of the prepared summary.

Expand the current iPhone demo to selectable compact, minimal, and expanded island presentations plus Lock Screen activity. Keep private summary details inside the app preview. Add a session-ended state and Always-On/reduced-luminance still state.

Use finite, state-triggered motion: preserve the existing 180/280/450 ms tokens for controls and transitions; longer timing is reserved for narrated explanatory sequences. Pause when offscreen or hidden, cancel cues on pause/reset, support keyboard navigation, and respect reduced motion. Do not create perpetual decorative Live Activities.

Done when all surfaces tell the same session story and end calmly, with static readable alternatives.

## P2 — Explain sources, agency, and privacy

Replace the generic source strip with an expandable, accessible source guide:
- Calendar and Reminders: optional permissions; confirmed, verified writes.
- Gmail: distinct metadata and message-analysis permissions.
- WhatsApp: Mac-only selected local chats and required OS access.
- Notes/Local Knowledge: selected content; separate same-day Daily Summary opt-in.
- GitHub, Notion, Slack: scoped read paths; mark live validation requirements accurately.

Add a concrete action-confirmation preview and concise FAQs: Does my Mac need to be awake? What reaches my phone? Can I choose sources? What happens without the model? Is Suzzme available to download?

Clarify local reasoning, provider networking, optional prepared-summary transport, and inspectable/deletable local information. Keep unavailable watched-page fetching out of active integration claims.

Done when visitors can understand each permission and platform boundary without reading technical documentation.

## P2 — Establish an honest next step

Keep “Try the demo” as the primary action while release acceptance is incomplete. Add a GitHub/source link if appropriate for the intended audience. Add a verified download or TestFlight destination only when an actual release exists. Do not invent download links, pricing, testimonials, or a waitlist backend.

Keep development on localhost as requested. Publishing is a separate task.

## P3 — Validation and delivery

- Verify all demo transitions, input-dependent output, replay/pause/reset, empty context, conflict handling, and session completion.
- Check 390 px phone, tablet, and 1440 px desktop layouts; long text and 200% zoom.
- Verify keyboard access, focus visibility, readable contrast, reduced motion, and static reduced-luminance states.
- Check that hidden/offscreen demos stop work and that browser previews never request real source permissions.
- Check images, navigation, console errors, layout shifts, and asset weight; optimize reused images without changing their identity.
- Capture desktop and mobile evidence, then update the landing-page README with the implemented controls and remaining limits.

## Separate native release dependencies

These gate public availability claims; they are not tasks to silently execute as part of a website change:
1. Validate same-account prepared-summary transfer on real Mac/iPhone devices, including stale/offline/error states.
2. Complete Google consent/revocation testing and outstanding verification; reconcile older OAuth documentation.
3. Verify real provider reads, disconnect/revocation, and selected local WhatsApp permissions/schema.
4. Complete signed app/widget/share-extension provisioning and the chosen Mac/iPhone distribution route.
5. Perform physical-device accessibility, notification, Live Activity, voice, background scheduling, and energy acceptance.
6. Reconcile historical release/vision documentation with current code before using it as launch evidence.

Recommended execution order: claim checklist → contextual morning demo → Mac/iPhone handoff and presence → sources/privacy/FAQ → responsive and accessibility verification → real release CTA when available.
