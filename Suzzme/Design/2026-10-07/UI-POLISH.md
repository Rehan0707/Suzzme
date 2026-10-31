# Native UI polish — 7 October 2026

27 SwiftUI and design-system files were refined against the Suzzme master specification and macos-design skill.

## Result

- Shared readable forms/lists use semantic Canvas, neutral navigation, native grouping and consistent minimum row sizes. This reaches primary and secondary settings, permissions, Memory, Sources, accounts and source detail screens.
- Home has a calmer introduction and lighter empty presentation. Conversation distinguishes the submitted question, renders answer content in primary text, and offers the actual system share sheet.
- Saved Activity shows actual saved structured information with search and detail navigation. It does not claim conversation persistence or show a demo completed item as real history.
- Source metadata and priority badges are neutral except meaningful warning states. Gmail explicitly discloses network use, and pasted-message controls reflow at accessibility sizes.
- Welcome and detail typography use a restrained hierarchy. Presence preview grows with content; error presence uses a restrained warning accent. Existing Face, themes, motion preferences, voice ownership and confirmation routing remain authoritative.
- Both native roots retain existing routes and platform navigation. Native Mac sidebar/Settings behavior is preserved; the compact-navigation design in the prototype is a future proposal.

## Review boundaries

`UI-POLISH.diff` compares the start-of-polish working files with this change, so it excludes the user’s earlier uncommitted edits. No commit, push or reset was performed. The design submodule remains as previously staged.

The local studio is a specification/prototype. It simulates accounts, permissions, voice and action results; production views retain real state owners. It is not a native Figma file and does not implement every proposed capability.

## Changed files

- `App/LaunchExperience.swift`
- `DesignSystem/Components/SuzzmeAssistantPresenceView.swift`
- `DesignSystem/Components/SuzzmeComponents.swift`
- `DesignSystem/Components/SuzzmeItemRow.swift`
- `DesignSystem/Layout/SuzzmePage.swift`
- `DesignSystem/Theme/SuzzmeTheme.swift`
- `Features/Briefing/BriefingView.swift`
- `Features/History/HistoryView.swift`
- `Features/Home/AskSuzzmeView.swift`
- `Features/Home/HomeView.swift`
- `Features/Home/ItemDetailView.swift`
- `Features/Invocation/InvocationSettingsView.swift`
- `Features/Invocation/PresenceMotionLabView.swift`
- `Features/Invocation/PresenceSettingsView.swift`
- `Features/Memory/MemoryView.swift`
- `Features/Settings/ProactiveIntelligenceSettingsView.swift`
- `Features/Settings/SettingsDetailViews.swift`
- `Features/Settings/SettingsView.swift`
- `Features/Settings/SuzzmeBrainLabView.swift`
- `Features/Settings/VoiceSettingsView.swift`
- `Features/Sources/GmailConnectionView.swift`
- `Features/Sources/InformationInspectionView.swift`
- `Features/Sources/SelectedMessageImportView.swift`
- `Features/Sources/SourcesView.swift`
- `Features/Sources/WatchedLinksView.swift`
- `Platform/iOS/MobileRootView.swift`
- `Platform/macOS/MacRootView.swift`

See `VALIDATION.md` for actual checks and platform limitations.
