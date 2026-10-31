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
                    SuzzmeFace(
                        state: environment.presenceState,
                        color: SuzzmeTheme.intelligencePrimary,
                        lineWidth: 3,
                        animation: environment.invocation.presenceAnimation
                    )
                    .frame(width: SuzzmeTheme.Spacing.extraLarge, height: SuzzmeTheme.Spacing.extraLarge)
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
                    .lineSpacing(SuzzmeTheme.Spacing.xxs)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                SuzzmeActionControls {
                    Button {
                        Task { await environment.speakCurrentBriefing() }
                    } label: {
                        Label("Listen", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SuzzmeTheme.intelligencePrimary)
                    .suzzmeProminentContrast()
                    .accessibilityLabel("Listen to Daily Summary")
                    .accessibilityHint("Rechecks current context before speaking")
                    .disabled(!environment.voice.speaksResponses || !environment.voice.canStartSpeech)
                    Button {
                        Task { _ = await environment.invokeSuzzme() }
                    } label: {
                        Label("Ask about your day", systemImage: "mic")
                    }
                    .buttonStyle(.bordered)
                }
                if !environment.voice.speaksResponses {
                    Text("Spoken responses are off. Turn them on in Voice Settings to listen.")
                        .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                    NavigationLink("Open Voice Settings") { VoiceSettingsView() }
                } else if !environment.voice.canStartSpeech {
                    Text("Finish the current voice interaction before listening to your summary.")
                        .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                } else {
                    Text("You can interrupt the summary with a question.")
                        .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }

            ForEach(briefing.sections) { section in
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                    SuzzmeSectionHeader(title: section.kind.title)
                    ForEach(section.items) { item in
                        BriefingItemView(item: item)
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
                    Text(item.summary).font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
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
