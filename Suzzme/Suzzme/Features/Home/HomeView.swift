import SwiftUI

struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("suzzme.profile.name") private var profileName = "Rehan"
    @State private var showsCompanion = false

    private var assistantPresentation: SuzzmeAssistantPresentation { .make(for: environment.presenceState) }
    private var greeting: String {
        let partOfDay = switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "\(partOfDay)." : "\(partOfDay), \(name)."
    }

    var body: some View {
        SuzzmePage {
            assistantHero

            if let today = environment.proactiveSnapshot?.dailyContext {
                NavigationLink { DailyContextView() } label: {
                    SuzzmeCard {
                        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                            HStack { SuzzmeSectionHeader(title: "Today"); Spacer(); Image(systemName: "arrow.right") }
                            if let item = today.activeEntries.first {
                                Text(item.title).font(.headline)
                                Text(item.summary).foregroundStyle(SuzzmeTheme.textSecondary).lineLimit(2)
                            } else {
                                Text(today.sourceLimitations.isEmpty ? "Nothing new needs your attention." : "Some of your day couldn’t be checked.")
                                    .foregroundStyle(SuzzmeTheme.textSecondary)
                            }
                            Text("See your current day").font(.subheadline.weight(.medium))
                        }
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }

            if let proactive = environment.proactiveSnapshot?.briefing,
               proactive.deliveryState != .stale {
                NavigationLink { BriefingView() } label: {
                    SuzzmeCard(highlighted: !proactive.isPartial) {
                        SuzzmeStateLabel(
                            title: proactive.isPartial ? "Daily Summary ready with a limitation" : "Your Daily Summary is ready",
                            symbol: proactive.isPartial ? "exclamationmark.triangle" : "speaker.wave.2"
                        )
                        Text(proactive.narration)
                            .font(.body)
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                            .lineLimit(3)
                        Label("Open Daily Summary", systemImage: "arrow.right")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .buttonStyle(.plain)
            }

            if environment.proactiveSnapshot?.dailyContext != nil {
                EmptyView()
            } else if let briefing = environment.briefing {
                SuzzmeSectionHeader(title: "What matters today")

                if let important = briefing.importantItems.first {
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                        SuzzmeSectionHeader(title: "Most important")
                        NavigationLink { ItemDetailView(item: important) } label: {
                            SuzzmeCard {
                                HStack {
                                    SuzzmePriorityBadge(priority: important.priority)
                                    Spacer()
                                    Image(systemName: "arrow.up.right").accessibilityHidden(true)
                                }
                                Text(important.title).font(.title2.weight(.semibold))
                                Text(important.summary)
                                    .foregroundStyle(SuzzmeTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Label("Take a closer look", systemImage: "arrow.right")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                    SuzzmeSectionHeader(title: "On today’s horizon")
                    ForEach(briefing.upcomingItems.prefix(3)) { item in
                        NavigationLink { ItemDetailView(item: item) } label: {
                            SuzzmeItemRow(item: item, showTime: true)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let item = briefing.carriedOverItems.first {
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                        SuzzmeSectionHeader(title: "From yesterday")
                        NavigationLink { ItemDetailView(item: item) } label: {
                            SuzzmeCard { SuzzmeItemRow(item: item) }
                        }
                        .buttonStyle(.plain)
                    }
                }

                NavigationLink { HistoryView().navigationTitle("Activity") } label: {
                    Label("View activity", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.medium))
                }
            } else if let message = environment.errorMessage {
                SuzzmeEmptyState(symbol: "exclamationmark.circle", title: "Your day is unavailable", message: message)
                Button("Try Again") { Task { await environment.loadIfNeeded() } }
                    .buttonStyle(.borderedProminent)
                    .suzzmeProminentContrast()
            } else if let limitation = environment.proactiveSnapshot?.dailyContext?.sourceLimitations.first {
                SuzzmeEmptyState(symbol: "exclamationmark.circle", title: "Your day is partly available", message: limitation)
                NavigationLink("Review Sources") { SourcesView() }
            } else {
                SuzzmeEmptyState(
                    symbol: "checkmark.circle",
                    title: "Nothing to show yet",
                    message: "Suzzme will show grounded information here when something useful is available."
                )
            }
        }
        .sheet(isPresented: $showsCompanion) {
            AskSuzzmeView().frame(minWidth: 300, minHeight: 420)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
        }
    }

    private var assistantHero: some View {
        VStack(spacing: SuzzmeTheme.Spacing.medium) {
            Text(greeting)
                .font(.largeTitle.weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Text("Here’s what matters today.")
                .font(.title3)
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                if environment.presenceState != .idle { SuzzmeHalo(
                    state: environment.presenceState,
                    theme: environment.invocation.presenceTheme,
                    animation: environment.invocation.presenceAnimation
                ) }
                SuzzmeFace(
                    state: environment.presenceState,
                    color: environment.invocation.presenceTheme.colors(for: colorScheme).face,
                    lineWidth: 5,
                    animation: environment.invocation.presenceAnimation
                )
                .frame(width: 84, height: 84)
            }
            .frame(maxWidth: 320, minHeight: 108)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(assistantPresentation.systemStatus)

            VStack(spacing: SuzzmeTheme.Spacing.xs) {
                Text(environment.presenceState == .idle ? "Anything on your mind?" : assistantPresentation.title)
                    .font(.title2.weight(.semibold))
                Text(environment.presenceState == .idle ? "A little room to think, together." : assistantPresentation.systemStatus)
                    .font(.subheadline)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: SuzzmeTheme.Spacing.small) { assistantButtons }
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, SuzzmeTheme.Spacing.small)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var assistantButtons: some View {
        Button {
            Task {
                if environment.voice.isListening {
                    await environment.cancelVoiceSession()
                } else {
                    _ = await environment.invokeSuzzme()
                }
            }
        } label: {
            Label(
                environment.voice.isListening ? "Stop listening" : "Talk to Suzzme",
                systemImage: environment.voice.isListening ? "stop.fill" : "mic.fill"
            )
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .suzzmeProminentContrast()
        .controlSize(.large)
        .accessibilityHint(environment.voice.isListening ? "Ends the current voice conversation" : "Starts a voice conversation")

        Button { showsCompanion = true } label: {
            Label("Type to Suzzme", systemImage: "keyboard").frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .controlSize(.large)
        .frame(minHeight: 44)
        .accessibilityHint("Opens the text conversation")
    }
}

#Preview("Home · Light") {
    NavigationStack { HomeView() }.environment(AppEnvironment.preview).preferredColorScheme(.light)
}
#Preview("Home · Dark") {
    NavigationStack { HomeView() }.environment(AppEnvironment.preview).preferredColorScheme(.dark)
}
#Preview("Home · Accessible type") {
    NavigationStack { HomeView() }.environment(AppEnvironment.preview).environment(\.dynamicTypeSize, .accessibility3)
}
#Preview("Home · Small iPhone") {
    NavigationStack { HomeView() }.environment(AppEnvironment.preview).frame(width: 320, height: 568)
}
#Preview("Home · Pro Max") {
    NavigationStack { HomeView() }.environment(AppEnvironment.preview).frame(width: 440, height: 956)
}

/// An inspectable projection of the existing bounded Today snapshot.
/// This view never prepares, persists or reclassifies intelligence.
struct DailyContextView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        SuzzmePage {
            Text("Your day, as it stands.").font(.largeTitle.weight(.semibold))
            Text("Current commitments and meaningful changes, from the context you chose to share.")
                .foregroundStyle(SuzzmeTheme.textSecondary)
            if let today = environment.proactiveSnapshot?.dailyContext {
                ForEach(Array(Set(today.sourceLimitations)).sorted(), id: \.self) { limitation in
                    Label(limitation, systemImage: "exclamationmark.circle")
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                }
                if today.activeEntries.isEmpty {
                    SuzzmeEmptyState(symbol: "calendar", title: "Nothing new to show", message: today.sourceLimitations.isEmpty ? "No current commitments were found in the available context." : "This is not a complete view of your day. Review Sources to see what couldn’t be checked.")
                }
                ForEach(today.activeEntries) { entry in
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                        if entry.state == .corrected { Label("Updated", systemImage: "arrow.triangle.2.circlepath").font(.caption) }
                        Text(entry.title).font(.headline)
                        Text(entry.summary).foregroundStyle(SuzzmeTheme.textSecondary)
                        if let date = entry.effectiveAt { Text(date, format: .dateTime.weekday().hour().minute()).font(.subheadline) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Divider()
                }
            } else {
                SuzzmeEmptyState(symbol: "calendar", title: "Your day is not ready yet", message: "Suzzme will arrange it when current, permitted context is available.")
            }
            NavigationLink("Review Sources") { SourcesView() }
        }
        .navigationTitle("Today")
        .task { await environment.loadProactiveState() }
    }
}
