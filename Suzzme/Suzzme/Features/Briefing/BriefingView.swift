import SwiftUI

struct BriefingView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        SuzzmePage {
            header

            if !environment.proactivePreferences.dailyBriefingEnabled {
                SuzzmeEmptyState(
                    symbol: "moon.zzz",
                    title: "Daily Summary is off",
                    message: "Turn it on when you want Suzzme to arrange the useful parts of your day."
                )
                NavigationLink("Open Daily Summary Settings") { ProactiveIntelligenceSettingsView() }
                    .buttonStyle(.borderedProminent)
                    .suzzmeProminentContrast()
            } else if environment.isPreparingBriefing {
                HStack(spacing: SuzzmeTheme.Spacing.medium) {
                    SuzzmeMascot(
                        state: environment.presenceState,
                        size: SuzzmeTheme.Layout.touchTarget,
                        animation: environment.invocation.presenceAnimation,
                        audioLevel: environment.voice.isListening ? environment.voice.audioLevel : 0,
                        speechProgress: environment.voice.isSpeaking ? environment.voice.speechProgress : 0
                    )
                    .accessibilityHidden(true)
                    Text("Checking what changed…")
                        .font(.subheadline.weight(.medium))
                }
                .padding(.vertical, SuzzmeTheme.Spacing.large)
                .accessibilityElement(children: .combine)
            } else if let briefing = environment.proactiveSnapshot?.briefing {
                briefingContent(briefing)
            } else if let error = environment.proactiveError {
                SuzzmeEmptyState(symbol: "exclamationmark.circle", title: "Your Daily Summary is unavailable", message: error)
                Button("Try Again") { Task { await environment.prepareProactiveBriefing(showActivity: true) } }
                    .buttonStyle(.borderedProminent)
                    .suzzmeProminentContrast()
            } else {
                SuzzmeEmptyState(
                    symbol: "checkmark.circle",
                    title: emptyTitle,
                    message: emptyMessage
                )
                Button("Check Again") { Task { await environment.prepareProactiveBriefing(showActivity: true) } }
                    .buttonStyle(.bordered)
            }

            if let opportunities = environment.proactiveSnapshot?.opportunities, !opportunities.isEmpty {
                opportunitySection(opportunities)
            }
        }
        .task { await environment.loadProactiveState() }
        .refreshable { await environment.prepareProactiveBriefing(showActivity: true) }
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await environment.prepareProactiveBriefing(showActivity: true) }
                } label: {
                    Label("Refresh Daily Summary", systemImage: "arrow.clockwise")
                }
                .help("Refresh Daily Summary with latest messages and emails")
            }
            ToolbarItem(placement: .automatic) {
                NavigationLink { BackgroundTasksView() } label: {
                    Label("Background Tasks", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        #endif
    }

    private var emptyTitle: String {
        if environment.proactiveSnapshot?.dailyContext?.sourceLimitations.isEmpty == false { return "Daily Summary may be incomplete" }
        return environment.proactiveSnapshot?.dailyContext == nil ? "Your Daily Summary is not prepared yet" : "Nothing new needs your attention"
    }

    private var emptyMessage: String {
        if let limitation = environment.proactiveSnapshot?.dailyContext?.sourceLimitations.first { return limitation }
        return environment.proactiveSnapshot?.dailyContext == nil
            ? "Ask Suzzme to check the sources you’ve allowed when you’re ready."
            : "Suzzme checked the information currently available on this device."
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
            Text("Your Daily Summary")
                .font(.largeTitle.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("What matters today, from the information you share.")
                .font(.body)
                .foregroundStyle(SuzzmeTheme.textSecondary)
        }
    }

    @ViewBuilder
    private func briefingContent(_ briefing: ProactiveBriefing) -> some View {
        if briefing.deliveryState == .stale {
            SuzzmeCard {
                SuzzmeStateLabel(title: "This Daily Summary needs a refresh", symbol: "arrow.clockwise")
                Text("Some context may have changed since it was prepared.")
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                Button("Refresh Daily Summary") { Task { await environment.prepareProactiveBriefing(showActivity: true) } }
            }
        } else {
            SuzzmeCard {
                Text(briefing.createdAt, format: .dateTime.weekday(.wide).month().day().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                Text(briefing.narration)
                    .font(.body)
                    .lineSpacing(SuzzmeTheme.Spacing.xs)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: SuzzmeTheme.Layout.companionWidth, alignment: .leading)
                    .textSelection(.enabled)
                SuzzmeActionControls {
                    Button {
                        Task { await environment.speakCurrentBriefing() }
                    } label: {
                        if environment.voice.isPreparingSpeech {
                            Label("Preparing voice…", systemImage: "waveform")
                        } else if environment.voice.isSpeaking {
                            Label("Stop reading", systemImage: "stop.fill")
                        } else {
                            Label("Listen", systemImage: "speaker.wave.2.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(environment.voice.isSpeaking ? SuzzmeTheme.warning : SuzzmeTheme.intelligencePrimary)
                    .suzzmeProminentContrast()
                    .accessibilityLabel(environment.voice.isSpeaking ? "Stop reading Daily Summary" : "Listen to Daily Summary")
                    .accessibilityHint("Reads your daily briefing using your configured voice")
                    .disabled(!environment.voice.speaksResponses || (!environment.voice.canStartSpeech && !environment.voice.isSpeaking && !environment.voice.isPreparingSpeech))
                    Button {
                        Task { _ = await environment.invokeSuzzme() }
                    } label: {
                        Label("Ask about your day", systemImage: "mic")
                    }
                    .buttonStyle(.bordered)

                    NavigationLink {
                        AskSuzzmeView(
                            initialText: "Plan my day and suggest focus time for today",
                            focusInput: false,
                            submitOnAppear: true,
                            showsDismissButton: true
                        )
                    } label: {
                        Label("Plan My Day", systemImage: "calendar.badge.clock")
                    }
                    .buttonStyle(.bordered)
                }
                if !environment.voice.speaksResponses {
                    Text("Spoken responses are off. Turn them on in Voice Settings to listen.")
                        .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                    NavigationLink("Open Voice Settings") { VoiceSettingsView() }
                } else if environment.voice.isSpeaking {
                    HStack(spacing: SuzzmeTheme.Spacing.xs) {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                        Text("Reading in \(environment.voice.speechEngine.title) (\(environment.voice.deliveryStyle.title.lowercased()) delivery). Tap Stop to interrupt.")
                    }
                    .font(.subheadline).foregroundStyle(SuzzmeTheme.intelligencePrimary)
                } else if environment.voice.isPreparingSpeech {
                    HStack(spacing: SuzzmeTheme.Spacing.xs) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Preparing \(environment.voice.speechEngine.title) on this device…")
                    }
                    .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                } else if !environment.voice.canStartSpeech {
                    Text("Finish the current voice interaction before listening to your summary.")
                        .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                } else {
                    Text("Using \(environment.voice.speechEngine.title) (\(environment.voice.deliveryStyle.title.lowercased()) delivery). You can interrupt anytime.")
                        .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }

            let timeline = DayPlannerEngine.analyze(
                entries: environment.proactiveSnapshot?.dailyContext?.entries ?? [],
                now: .now,
                calendar: .current
            )
            DayPlanFocusView(timeline: timeline)

            if !briefing.sourceEvidence.isEmpty {
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                    SuzzmeSectionHeader(title: "Sources in this summary")
                    Text(briefing.sourceEvidence.map(sourceName).joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    NavigationLink("Manage Knowledge Sources") { SourcesView() }
                        .buttonStyle(.bordered)
                }
                .accessibilityElement(children: .contain)
            }

            ForEach(briefing.sections) { section in
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                    SuzzmeSectionHeader(title: section.kind.title)
                    ForEach(section.items) { item in
                        BriefingItemView(item: item)
                        if item.id != section.items.last?.id { Divider() }
                    }
                }
            }

            if let limitation = briefing.healthLimitations.first {
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                    SuzzmeStateLabel(title: "Daily Summary may be incomplete", symbol: "exclamationmark.triangle")
                    Text(limitation)
                        .font(.subheadline)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
        }
    }

    private func sourceName(_ source: String) -> String {
        switch source {
        case "calendar": "Calendar"
        case "reminders": "Reminders"
        case "gmail": "Gmail"
        case "mail": "Apple Mail"
        case "whatsapp": "WhatsApp"
        case "messages": "Shared messages"
        case "connectedApps": "Connected apps"
        case "watchedWeb": "Watched Links"
        default: "Other allowed source"
        }
    }

    private func opportunitySection(_ opportunities: [SuzzmeOpportunity]) -> some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
            SuzzmeSectionHeader(title: "Suzzme can help")
            ForEach(opportunities) { opportunity in
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                    SuzzmeStateLabel(title: "Suggested", symbol: "lightbulb")
                    Text(opportunity.summary).font(.headline)
                    Text(opportunity.reason)
                        .font(.subheadline)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SuzzmeActionControls {
                        if let proposal = opportunity.possibleAssistance {
                            NavigationLink("Review") {
                                AskSuzzmeView(initialText: proposal.suggestedRequest)
                            }
                            .buttonStyle(.borderedProminent)
                            .suzzmeProminentContrast()
                        }
                        Button("Not Useful") {
                            Task { await environment.dismissOpportunity(opportunity) }
                        }
                        .buttonStyle(.bordered)
                    }
                    Divider()
                }
                .accessibilityElement(children: .contain)
            }
        }
    }
}

private struct BriefingItemView: View {
    let item: ProactiveBriefingItem

    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
            HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.small) {
                Image(systemName: symbol)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                    if let time = item.effectiveTime {
                        Text(ProactiveDatePresentation.label(time, isAllDay: item.isAllDay == true))
                            .font(.subheadline.weight(.medium))
                    }
                    Text(ComposioGitHubDailyActivity.displayTitle(item.summary)).font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let sourceLink = ComposioGitHubDailyActivity.linkURL(in: item.summary) {
                        Link(destination: sourceLink) {
                            Label("Open on GitHub", systemImage: "arrow.up.right.square")
                                .font(.footnote)
                        }
                    }
                    Text(item.whyRelevant)
                        .font(.subheadline)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, SuzzmeTheme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch item.kind {
        case .schedule, .scheduleChange: "calendar"
        case .cancellation: "calendar.badge.minus"
        case .reminder, .deadline, .commitment: "checklist"
        case .information: "info.circle"
        }
    }
}

#Preview("Briefing") {
    NavigationStack { BriefingView() }
        .environment(AppEnvironment.preview)
}
