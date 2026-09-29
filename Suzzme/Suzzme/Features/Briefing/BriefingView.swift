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
                ProgressView("Checking what changed…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SuzzmeTheme.Spacing.hero)
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
            ? "Ask Suzzme to check your permitted sources when you are ready."
            : "Suzzme checked the information currently available on this device."
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
            SuzzmeStateLabel(title: "Your daily perspective", symbol: "text.alignleft")
            Text("What matters, without the noise.")
                .font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text("A few useful thoughts before the day gets loud.")
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
            SuzzmeCard(highlighted: true) {
                Text(briefing.createdAt, format: .dateTime.weekday(.wide).month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                Text(briefing.narration)
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await environment.speakCurrentBriefing() }
                } label: {
                    Label("Listen to Daily Summary", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderedProminent)
                    .suzzmeProminentContrast()
                .accessibilityHint("Rechecks current context before speaking")
                Button {
                    Task { _ = await environment.invokeSuzzme() }
                } label: {
                    Label("Ask about your day", systemImage: "mic")
                }
                .buttonStyle(.bordered)
                Text("You can interrupt the summary with a question.")
                    .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
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
                SuzzmeCard {
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
                SuzzmeCard {
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
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: symbol)
                    .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                    .accessibilityHidden(true)
                Text(item.summary).font(.headline)
                Spacer(minLength: SuzzmeTheme.Spacing.small)
                if let time = item.effectiveTime {
                    Text(time, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
            Text(item.whyRelevant)
                .font(.subheadline)
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
