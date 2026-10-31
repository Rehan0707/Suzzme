import SwiftUI

/// Presents the core's current day without creating another intelligence store.
struct DailyContextView: View {
    @Environment(AppEnvironment.self) private var environment
    #if os(iOS)
    @Environment(AppRouter.self) private var router
    #endif
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("suzzme.profile.name") private var profileName = ""
    @State private var showsCompanion = false
    @State private var startsVoiceFromHome = false
    @State private var question = ""
    @State private var checkedSources = false
    @State private var selectedDate = Date.now
    @State private var showsDatePicker = false
    @State private var savedBriefings: [ProactiveBriefing] = []

    private var contextCalendar: Calendar {
        var calendar = Calendar.current
        if let identifier = environment.proactiveSnapshot?.dailyContext?.timeZoneIdentifier,
           let timeZone = TimeZone(identifier: identifier) {
            calendar.timeZone = timeZone
        }
        return calendar
    }
    private var today: DailyContextSnapshot? {
        guard let day = environment.proactiveSnapshot?.dailyContext else { return nil }
        return contextCalendar.isDateInToday(day.localDay) ? day : nil
    }
    private var activeEntries: [DailyContextEntry] { today?.activeEntries ?? [] }
    private var assistantPresentation: SuzzmeAssistantPresentation { .make(for: environment.presenceState) }
    private var greeting: String {
        let partOfDay = switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? partOfDay : "\(partOfDay), \(name)"
    }
    private var hasSources: Bool {
        [.calendar, .reminders].contains { environment.sourcePermissions[$0] == .authorized }
            || environment.informationHealth.contains { $0.enabled && $0.state == .healthy }
    }
    private var hasDayContent: Bool { !activeEntries.isEmpty || !changes.isEmpty }
    private var showsSummary: Bool {
        guard environment.proactivePreferences.dailyBriefingEnabled,
              today != nil,
              let summary = environment.proactiveSnapshot?.briefing,
              summary.deliveryState != .stale,
              summary.createdAt <= .now,
              Date.now.timeIntervalSince(summary.createdAt) < ProactiveLimits.briefingFreshness,
              contextCalendar.isDateInToday(summary.createdAt) else { return false }
        return hasDayContent || !summary.isPartial
    }
    private var limitation: String? {
        today?.sourceLimitations.first ?? environment.proactiveError ?? environment.informationError
    }
    private var schedule: [DailyContextEntry] {
        activeEntries.filter {
            $0.kind == .schedule && ($0.isAllDay == true || ($0.effectiveUntil ?? $0.effectiveAt ?? .distantFuture) > .now)
        }.sorted { ($0.effectiveAt ?? .distantFuture) < ($1.effectiveAt ?? .distantFuture) }
    }
    private var nextEntry: DailyContextEntry? { schedule.first { $0.isAllDay != true } ?? schedule.first }
    private var matters: [DailyContextEntry] {
        Array(activeEntries.filter { [.deadline, .commitment].contains($0.kind) }.prefix(3))
    }
    private var unfinished: [DailyContextEntry] {
        let featured = Set(matters.map(\.id))
        return activeEntries.filter { [.reminder, .deadline, .commitment].contains($0.kind) && !featured.contains($0.id) }
    }
    private var changes: [DailyContextEntry] {
        // A cancelled appointment is a change to explain, never an upcoming event.
        (today?.entries ?? []).filter {
            ($0.kind == .scheduleChange && $0.state == .corrected)
                || ($0.kind == .cancellation && $0.state == .cancelled)
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            SuzzmePage(contentWidth: SuzzmeTheme.Layout.workspaceWidth) {
                companionEntrance
                daySelector
                Group {
                    if isTodaySelected { dayLayout.transition(.opacity.combined(with: .move(edge: .leading))) }
                    else { savedDayPage.transition(.opacity.combined(with: .move(edge: .trailing))) }
                }
                .gesture(DragGesture(minimumDistance: 45).onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    withAnimation(SuzzmeTheme.Motion.disclosure(reduceMotion: reduceMotion)) {
                        let change = value.translation.width < 0 ? -1 : 1
                        if let next = contextCalendar.date(byAdding: .day, value: change, to: selectedDate),
                           contextCalendar.startOfDay(for: next) <= contextCalendar.startOfDay(for: .now) {
                            selectedDate = next
                        }
                    }
                })
            }
        }
        .sheet(isPresented: $showsCompanion, onDismiss: { startsVoiceFromHome = false }) {
            AskSuzzmeView(initialText: question, startVoiceOnAppear: startsVoiceFromHome)
                .frame(minWidth: 300, minHeight: 420)
        }
        .task {
            await environment.refreshSourcePermissions()
            await environment.inspectInformation()
            await environment.loadProactiveState()
            await loadSavedBriefings()
            checkedSources = true
        }
        .onChange(of: environment.proactiveSnapshot?.briefing?.id) { _, _ in Task { await loadSavedBriefings() } }
        .refreshable { await environment.prepareProactiveBriefing(showActivity: true) }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.selection = .settings
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        #endif
    }

    private var daySelector: some View {
        Button { showsDatePicker = true } label: {
            HStack(spacing: SuzzmeTheme.Spacing.xs) {
                Text(selectedDayLabel).font(.headline)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .padding(.horizontal, SuzzmeTheme.Spacing.large)
            .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
            .contentShape(Capsule())
            .suzzmeGlassSurface(cornerRadius: SuzzmeTheme.Layout.touchTarget / 2)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Summary date: \(selectedDayLabel)")
        .accessibilityHint("Opens a calendar to choose a day. You can also swipe between days.")
        .popover(isPresented: $showsDatePicker) {
            VStack(spacing: SuzzmeTheme.Spacing.medium) {
                HStack {
                    Button("Today") { selectedDate = .now; showsDatePicker = false }
                    Spacer()
                    Text("Choose a day").font(.headline)
                    Spacer()
                    Button("Done") { showsDatePicker = false }
                }
                DatePicker("Summary date", selection: $selectedDate, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .environment(\.calendar, contextCalendar)
                    .environment(\.timeZone, contextCalendar.timeZone)
            }
            .padding(SuzzmeTheme.Spacing.large)
            .frame(minWidth: 300, idealWidth: 340)
        }
    }

    private var isTodaySelected: Bool { contextCalendar.isDate(selectedDate, inSameDayAs: .now) }

    private var selectedDayLabel: String {
        if isTodaySelected { return "Today" }
        if let yesterday = contextCalendar.date(byAdding: .day, value: -1, to: .now),
           contextCalendar.isDate(selectedDate, inSameDayAs: yesterday) { return "Yesterday" }
        return selectedDate.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var selectedSummary: ProactiveBriefing? {
        savedBriefings.first { contextCalendar.isDate($0.informationCutoff, inSameDayAs: selectedDate) }
    }

    @ViewBuilder private var savedDayPage: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.large) {
            SuzzmeSectionHeader(title: "\(selectedDayLabel) summary")
            if let summary = selectedSummary {
                SuzzmeCard {
                    Text(summary.informationCutoff, format: .dateTime.weekday(.wide).month().day())
                        .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                    Text(summary.narration).fixedSize(horizontal: false, vertical: true)
                    NavigationLink("View full summary") { SavedBriefingView(briefing: summary) }
                        .buttonStyle(.bordered)
                }
            } else {
                SuzzmeEmptyState(symbol: "calendar", title: "No summary available for this day",
                                 message: "A saved summary will appear here when one is available and its sources can still be accessed.")
            }
            supportingLinks
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadSavedBriefings() async {
        savedBriefings = (try? await environment.savedDailyBriefings()) ?? []
    }

    /// The same day and summary adapt to available space, including narrow Mac windows.
    @ViewBuilder private var dayLayout: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.extraLarge) {
                dayContent
                summaryColumn
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.extraLarge) {
                    dayContent
                        .frame(minWidth: SuzzmeTheme.Layout.primaryColumnMinimum, maxWidth: .infinity)
                    summaryColumn
                        .frame(width: SuzzmeTheme.Layout.secondaryColumnMinimum)
                }
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.extraLarge) {
                    dayContent
                    summaryColumn
                }
            }
        }
    }

    private var dayContent: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.large) {
            if let today {
                if hasDayContent, let limitation { sourceLimitation(limitation) }
                if activeEntries.isEmpty && changes.isEmpty { dayEmptyState }
                if let nextEntry {
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
                        SuzzmeSectionHeader(title: "Up next")
                        SuzzmeCard { dayEntry(nextEntry, leading: true) }
                        ForEach(schedule.filter { $0.id != nextEntry.id }.prefix(2)) { entry in
                            dayEntry(entry)
                        }
                    }
                }
                daySection("What matters", entries: matters)
                daySection("Unfinished", entries: unfinished)
                daySection("Changes", entries: changes)
                daySection("From your sources", entries: activeEntries.filter { $0.kind == .information })
                if hasSources {
                    Label("Checked \(today.generatedAt.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                }
            } else if let briefing = environment.briefing, briefing.attentionCount > 0 {
                legacyDay(briefing)
            } else if environment.isLoading || !checkedSources {
                Label("Checking your day…", systemImage: "clock")
                    .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
            } else {
                dayEmptyState
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryColumn: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.large) {
            compactSummary
            helpfulSuggestion
            supportingLinks
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var companionEntrance: some View {
        VStack(alignment: .center, spacing: SuzzmeTheme.Spacing.medium) {
            VStack(spacing: SuzzmeTheme.Spacing.xxs) {
                Text(greeting)
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("What’s on your mind?")
                    .font(.body)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                Text(environment.presenceState == .idle ? "Ready when you are" : assistantPresentation.systemStatus)
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .contentTransition(.opacity)
                    .animation(SuzzmeTheme.Motion.feedback(reduceMotion: reduceMotion), value: environment.presenceState)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            SuzzmeActionControls {
                Button {
                    question = ""
                    startsVoiceFromHome = true
                    showsCompanion = true
                } label: {
                    Label("Talk to Suzzme", systemImage: "mic.fill")
                        .frame(minHeight: 28)
                }
                .buttonStyle(.borderedProminent).tint(SuzzmeTheme.intelligencePrimary).suzzmeProminentContrast().controlSize(.large)
                Button { startsVoiceFromHome = false; question = ""; showsCompanion = true } label: {
                    Label("Type to Suzzme", systemImage: "keyboard").frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, SuzzmeTheme.Spacing.small)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var dayEmptyState: some View {
        if !hasSources {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
                Text("Let’s make this your day.").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text("Calendar brings your schedule. Reminders brings the things you still want to do.")
                    .foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                SuzzmeActionControls {
                    connectSource(.calendar)
                    connectSource(.reminders)
                }
                Text("You choose the access. Changes always need your confirmation.")
                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
            }
        } else {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                Text(limitation != nil ? "Let’s check your sources" : today == nil ? "Ready to check your day" : "Clear for now")
                    .font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text(limitation ?? (today == nil ? "Check the sources you’ve allowed for current commitments and changes." : "Nothing needs your attention in the information checked. Add a reminder, ask a question, or check again later."))
                    .foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                SuzzmeActionControls {
                    Button("Check again") { Task { await environment.prepareProactiveBriefing(showActivity: true) } }
                        .buttonStyle(.bordered).disabled(environment.isPreparingBriefing)
                    NavigationLink("Review Sources") { SourcesView() }
                }
            }
        }
    }

    @ViewBuilder private func connectSource(_ kind: SuzzmeContextSourceKind) -> some View {
        let status = environment.sourcePermissions[kind] ?? .notDetermined
        if status == .notDetermined || status == .writeOnly {
            Button("Connect \(kind.title)") { Task { await environment.requestSourcePermission(kind) } }
                .buttonStyle(.bordered)
        } else {
            NavigationLink("Review \(kind.title)") { SourcesView() }.buttonStyle(.bordered)
        }
    }

    private func sourceLimitation(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink("Review Sources") { SourcesView() }.font(.subheadline.weight(.medium))
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func daySection(_ title: String, entries: [DailyContextEntry]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                SuzzmeSectionHeader(title: title)
                ForEach(entries) { entry in
                    dayEntry(entry)
                    if entry.id != entries.last?.id { Divider() }
                }
            }
        }
    }

    private func dayEntry(_ entry: DailyContextEntry, leading: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                if let date = entry.effectiveAt {
                    Text(ProactiveDatePresentation.label(date, isAllDay: entry.isAllDay == true))
                        .font(.subheadline.weight(.medium))
                }
                Spacer(minLength: SuzzmeTheme.Spacing.xs)
                Text(sourceName(entry.source)).font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            Text(entry.title).font(leading ? .title2.weight(.semibold) : .headline)
                .fixedSize(horizontal: false, vertical: true)
            if !entry.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               entry.summary.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(entry.title.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame {
                Text(entry.summary).font(.body).foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if entry.state == .corrected {
                Label("Updated", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            Button("Ask about this") { question = "What should I know about \(entry.title)?"; showsCompanion = true }
                .font(.subheadline).buttonStyle(.plain).frame(minHeight: 44, alignment: .leading)
        }
        .padding(.vertical, leading ? 0 : SuzzmeTheme.Spacing.xs)
        .accessibilityElement(children: .contain)
    }

    private func sourceName(_ source: String) -> String {
        switch source.lowercased() {
        case "calendar": "Calendar"
        case "reminders": "Reminders"
        case "gmail", "mail": "Mail"
        case "messages": "Shared message"
        case "watchedweb", "watchedlinks", "watched links": "Watched link"
        case "manual", "suzzme", "saved items": "Saved with Suzzme"
        default: "Shared information"
        }
    }

    @ViewBuilder private var compactSummary: some View {
        if showsSummary, let summary = environment.proactiveSnapshot?.briefing {
            SuzzmeCard {
                NavigationLink { BriefingView() } label: {
                    HStack { SuzzmeSectionHeader(title: "Daily Summary"); Spacer(); Image(systemName: "arrow.right") }
                }.buttonStyle(.plain)
                Text(summary.narration).font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                Button { Task { await environment.speakCurrentBriefing() } } label: {
                    Label("Listen to your summary", systemImage: "speaker.wave.2")
                }.buttonStyle(.plain).frame(minHeight: 44)
            }
        }
    }

    @ViewBuilder private var helpfulSuggestion: some View {
        if let opportunity = environment.proactiveSnapshot?.opportunities.first {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                SuzzmeSectionHeader(title: "Suzzme can help")
                Text(opportunity.summary).font(.headline)
                Text(opportunity.reason).font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                if let proposal = opportunity.possibleAssistance {
                    Button("Review suggestion") { question = proposal.suggestedRequest; showsCompanion = true }
                        .buttonStyle(.bordered)
                }
                Button("Not useful") { Task { await environment.dismissOpportunity(opportunity) } }
                    .buttonStyle(.plain).font(.subheadline).frame(minHeight: 44)
            }
        }
    }

    private var supportingLinks: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            if !showsSummary {
                NavigationLink { BriefingView() } label: {
                    HStack { Label("Daily Summary", systemImage: "text.alignleft"); Spacer(); Image(systemName: "chevron.right").imageScale(.small) }
                        .frame(minHeight: 44)
                }
            }
            NavigationLink { HistoryView().navigationTitle("Activity") } label: {
                HStack { Label("Activity", systemImage: "clock.arrow.circlepath"); Spacer(); Image(systemName: "chevron.right").imageScale(.small) }
                    .frame(minHeight: 44)
            }
        }
        .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
    }

    private func legacyDay(_ briefing: DailyBriefing) -> some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.large) {
            legacySection("Next", items: Array(briefing.upcomingItems.prefix(3)), time: true)
            legacySection("What matters", items: Array(briefing.importantItems.prefix(3)))
            legacySection("Unfinished", items: briefing.carriedOverItems)
        }
    }

    @ViewBuilder private func legacySection(_ title: String, items: [SuzzmeItem], time: Bool = false) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                SuzzmeSectionHeader(title: title)
                ForEach(items) { item in
                    NavigationLink { ItemDetailView(item: item) } label: { SuzzmeItemRow(item: item, showTime: time) }.buttonStyle(.plain)
                }
            }
        }
    }
}

private struct SavedBriefingView: View {
    @Environment(AppEnvironment.self) private var environment
    let briefing: ProactiveBriefing
    @State private var verified: ProactiveBriefing?
    @State private var loaded = false

    var body: some View {
        SuzzmePage {
            Text("Saved summary").font(.largeTitle.weight(.semibold)).accessibilityAddTraits(.isHeader)
            if let verified {
                Text(verified.informationCutoff, format: .dateTime.weekday(.wide).month().day().hour().minute())
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                SuzzmeCard {
                    Text(verified.narration).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task {
                            guard let current = try? await environment.savedDailyBriefings().first(where: { $0.id == briefing.id }) else {
                                self.verified = nil
                                return
                            }
                            environment.voice.speak(current.narration, preserveFullText: true)
                        }
                    } label: { Label("Listen to your summary", systemImage: "speaker.wave.2") }
                    .disabled(!environment.voice.speaksResponses || !environment.voice.canStartSpeech)
                }
                ForEach(verified.sections) { section in
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                        SuzzmeSectionHeader(title: section.kind.title)
                        ForEach(section.items) { item in
                            Text(item.summary).fixedSize(horizontal: false, vertical: true)
                            if !item.whyRelevant.isEmpty { Text(item.whyRelevant).font(.caption).foregroundStyle(SuzzmeTheme.textSecondary) }
                        }
                    }
                }
                if !verified.sourceEvidence.isEmpty {
                    NavigationLink("Manage Knowledge Sources") { SourcesView() }
                }
                if let limitation = verified.healthLimitations.first {
                    Label(limitation, systemImage: "exclamationmark.circle").foregroundStyle(SuzzmeTheme.textSecondary)
                }
            } else if loaded {
                SuzzmeEmptyState(symbol: "lock", title: "Summary unavailable", message: "Check that its sources are still available and allowed.")
            } else { ProgressView("Checking summary…") }
        }
        .task {
            verified = try? await environment.savedDailyBriefings().first { $0.id == briefing.id }
            loaded = true
        }
    }
}


#Preview("Today · Light") {
    NavigationStack { DailyContextView() }.environment(AppEnvironment.preview).environment(AppRouter()).preferredColorScheme(.light)
}
#Preview("Today · Dark") {
    NavigationStack { DailyContextView() }.environment(AppEnvironment.preview).environment(AppRouter()).preferredColorScheme(.dark)
}
#Preview("Today · Accessible type") {
    NavigationStack { DailyContextView() }.environment(AppEnvironment.preview).environment(AppRouter()).environment(\.dynamicTypeSize, .accessibility3)
}
#Preview("Today · Small iPhone") {
    NavigationStack { DailyContextView() }.environment(AppEnvironment.preview).environment(AppRouter()).frame(width: 320, height: 568)
}
#Preview("Today · Pro Max") {
    NavigationStack { DailyContextView() }.environment(AppEnvironment.preview).environment(AppRouter()).frame(width: 440, height: 956)
}
