import SwiftUI

/// A quiet entrance to the existing companion and the core's current day.
struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("suzzme.profile.name") private var profileName = ""
    @FocusState private var composerFocused: Bool
    @State private var draft = ""
    @State private var submittedDraft = ""
    @State private var showsAssistant = false
    @State private var startsVoice = false
    @State private var showsContext = false
    @State private var isNight = Self.nightHours(at: .now)
    @State private var isResting = false
    @State private var isWaking = false
    @State private var lastMascotActivity = Date.now
    #if os(macOS)
    @State private var lastPointerPosition: CGPoint?
    #endif

    private static let restDelay: TimeInterval = 45

    private static func nightHours(at date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 20 || hour < 5
    }

    private var greeting: String {
        let salutation = switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<20: "Good evening"
        default: "Good night"
        }
        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? salutation : "\(salutation), \(name)"
    }

    /// Presentation reads the existing snapshot; it never generates or stores context.
    private var currentDay: DailyContextSnapshot? {
        guard let day = environment.proactiveSnapshot?.dailyContext,
              contextCalendar.isDateInToday(day.localDay) else { return nil }
        return day
    }

    private var contextCalendar: Calendar {
        var calendar = Calendar.current
        if let identifier = environment.proactiveSnapshot?.dailyContext?.timeZoneIdentifier,
           let timeZone = TimeZone(identifier: identifier) { calendar.timeZone = timeZone }
        return calendar
    }

    private func currentSummary(at now: Date) -> ProactiveBriefing? {
        guard environment.proactivePreferences.dailyBriefingEnabled,
              let summary = environment.proactiveSnapshot?.briefing,
              summary.deliveryState != .stale,
              contextCalendar.isDate(summary.createdAt, inSameDayAs: now),
              now.timeIntervalSince(summary.createdAt) >= 0,
              now.timeIntervalSince(summary.createdAt) < ProactiveLimits.briefingFreshness,
              currentDay != nil else { return nil }
        return summary
    }

    /// Shows only sources represented in today's current, prepared context.
    private var daySourceNames: [String] {
        var names: [String] = []
        for entry in currentDay?.activeEntries ?? [] {
            let name = switch entry.source {
            case "calendar": "Calendar"
            case "reminders": "Reminders"
            case "gmail": "Gmail"
            case "whatsapp": "WhatsApp"
            case "messages": "Messages"
            case "information": "Recent information"
            case "connectedApps": "Connected apps"
            case "watchedWeb": "Watched Links"
            default: "Other sources"
            }
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SuzzmeTheme.Spacing.extraLarge) {
                homeLayout
                if dynamicTypeSize.isAccessibilitySize { composer }
            }
                .padding(.horizontal, SuzzmeTheme.Layout.pageInset)
                .padding(.vertical, SuzzmeTheme.Spacing.extraLarge)
                .frame(maxWidth: SuzzmeTheme.Layout.workspaceWidth)
                .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
              composer
                .padding(.horizontal, SuzzmeTheme.Layout.compactInset)
                .padding(.vertical, SuzzmeTheme.Spacing.small)
                .frame(maxWidth: SuzzmeTheme.Layout.readingWidth)
                .frame(maxWidth: .infinity)
                .background(SuzzmeTheme.pageBackground)
            }
        }
        .background(SuzzmeTheme.pageBackground)
        .navigationDestination(isPresented: $showsAssistant) {
            AskSuzzmeView(initialText: submittedDraft,
                          focusInput: !submittedDraft.isEmpty,
                          submitOnAppear: !submittedDraft.isEmpty,
                          startVoiceOnAppear: startsVoice,
                          showsDismissButton: false,
                          usesParentNavigationStack: true)
        }
        .sheet(isPresented: $showsContext) { ContextChooserView() }
        .onAppear {
            isNight = Self.nightHours(at: .now)
            isResting = isNight && environment.presenceState == .idle
            lastMascotActivity = .now
        }
        .onChange(of: environment.presenceState) { _, _ in
            isResting = false
            isWaking = false
            lastMascotActivity = .now
        }
        .task(id: lastMascotActivity) {
            guard isNight else { return }
            do { try await Task.sleep(for: .seconds(Self.restDelay)) } catch { return }
            guard !Task.isCancelled, environment.presenceState == .idle else { return }
            isResting = true
            isWaking = false
        }
        .task { await followDayNightBoundary() }
        #if os(macOS)
        .onContinuousHover { phase in
            switch phase {
            case .active(let position):
                defer { lastPointerPosition = position }
                guard let previous = lastPointerPosition,
                      hypot(position.x - previous.x, position.y - previous.y) >= 6 else { return }
                noteMascotActivity()
            case .ended:
                lastPointerPosition = nil
            }
        }
        #endif
    }

    private var restingMessage: String {
        #if os(macOS)
        "Resting · click or move here to wake"
        #else
        "Resting · tap to wake"
        #endif
    }

    private func noteMascotActivity() {
        let now = Date.now
        if isResting, environment.presenceState == .idle {
            isResting = false
            isWaking = true
            lastMascotActivity = now
            return
        }
        if now.timeIntervalSince(lastMascotActivity) >= 2 {
            lastMascotActivity = now
        }
    }

    private func mascotTapped() {
        if isResting {
            noteMascotActivity()
        } else {
            talk()
        }
    }

    private func followDayNightBoundary() async {
        while !Task.isCancelled {
            let nextHour = isNight ? 5 : 20
            guard let boundary = Calendar.current.nextDate(
                after: .now,
                matching: DateComponents(hour: nextHour, minute: 0, second: 0),
                matchingPolicy: .nextTime
            ) else { return }
            do { try await Task.sleep(for: .seconds(max(boundary.timeIntervalSinceNow, 1))) }
            catch { return }
            guard !Task.isCancelled else { return }
            isNight = Self.nightHours(at: .now)
            isResting = false
            isWaking = false
            lastMascotActivity = .now
        }
    }

    @ViewBuilder private var homeLayout: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: SuzzmeTheme.Spacing.extraLarge) { companion; dayLinks }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: SuzzmeTheme.Spacing.extraLarge) {
                    companion.frame(minWidth: SuzzmeTheme.Layout.primaryColumnMinimum)
                    dayLinks.frame(width: SuzzmeTheme.Layout.secondaryColumnMinimum)
                }
                VStack(spacing: SuzzmeTheme.Spacing.extraLarge) {
                    companion
                    dayLinks
                }
                .frame(maxWidth: SuzzmeTheme.Layout.companionWidth)
            }
        }
    }

    private var companion: some View {
        VStack(spacing: SuzzmeTheme.Spacing.medium) {
            SuzzmeMascot(
                state: environment.presenceState,
                size: SuzzmeTheme.Layout.companionFace,
                animation: environment.invocation.presenceAnimation,
                audioLevel: environment.voice.isListening ? environment.voice.audioLevel : 0,
                speechProgress: environment.voice.isSpeaking ? environment.voice.speechProgress : 0,
                isGreeting: isWaking,
                isSleeping: isResting,
                accessibilityLabel: isResting ? "Wake Suzzme" : "Talk to Suzzme",
                onTap: mascotTapped
            )
            VStack(spacing: SuzzmeTheme.Spacing.xs) {
                Text(greeting)
                    .font(.title.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("What’s on your mind?")
                    .font(.body).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            Text(isResting && environment.presenceState == .idle ? restingMessage :
                 environment.presenceState == .idle ? "Ready when you are" :
                 SuzzmeAssistantPresentation.make(for: environment.presenceState).systemStatus)
                .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(SuzzmeTheme.Motion.feedback(reduceMotion: reduceMotion), value: isResting)
            Button(action: talk) {
                Label("Talk to Suzzme", systemImage: "mic.fill")
                    .font(.headline)
                    .padding(.horizontal, SuzzmeTheme.Spacing.large)
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(SuzzmeTheme.intelligencePrimary)
            .suzzmeProminentContrast()
            .help("Talk to Suzzme (⇧⌘T)")
            .accessibilityIdentifier("suzzme-home-talk")
        }
        .padding(.vertical, SuzzmeTheme.Spacing.large)
        .frame(maxWidth: .infinity)
    }

    private var dayLinks: some View {
        // Recheck display freshness while Home stays open, using Core's existing limit.
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
          VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
            HStack {
                Text("Your day").font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(Date.now, format: .dateTime.month(.abbreviated).day())
                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            homeLink("What matters today", symbol: "sun.max", message: todayMessage, destination: .today)
            let summary = currentSummary(at: timeline.date)
            homeLink("Daily Summary", symbol: "text.alignleft",
                     message: summary?.narration ?? "A little perspective on your day, when you need it.",
                     destination: .briefing, note: summary?.isPartial == true ? "Some sources couldn’t be checked" : nil)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var todayMessage: String {
        guard let day = currentDay, !day.activeEntries.isEmpty else {
            return "Your schedule, tasks and useful updates, together."
        }
        let count = day.activeEntries.count
        return count == 1 ? "1 update from your sources." : "\(count) updates from your sources."
    }

    private func homeLink(_ title: String, symbol: String, message: String, destination: AppDestination, note: String? = nil) -> some View {
        Button { router.selection = destination } label: {
            SuzzmeCard {
                HStack(spacing: SuzzmeTheme.Spacing.xs) {
                    Image(systemName: symbol).symbolRenderingMode(.hierarchical)
                        .foregroundStyle(SuzzmeTheme.textSecondary).accessibilityHidden(true)
                    Text(title).font(.headline)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.medium))
                        .foregroundStyle(SuzzmeTheme.textSecondary).accessibilityHidden(true)
                }
                Text(message).font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Label(note, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("suzzme-home-\(destination.rawValue)")
    }

    private var composer: some View {
        VStack(spacing: SuzzmeTheme.Spacing.xs) {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                questionField
                    .padding(.horizontal, SuzzmeTheme.Spacing.small)
                ViewThatFits(in: .horizontal) {
                    composerControls(sourceLabel: true, summaryLabel: "Summarize my day")
                    composerControls(sourceLabel: false, summaryLabel: "Summarize day")
                    composerControls(sourceLabel: false, summaryLabel: nil)
                }
            }
            .padding(SuzzmeTheme.Spacing.xs)
            .suzzmeGlassSurface(cornerRadius: SuzzmeTheme.Radius.largeSurface,
                                tint: SuzzmeTheme.intelligencePrimary.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.largeSurface)
                    .strokeBorder(contrast == .increased || composerFocused ? SuzzmeTheme.textSecondary : SuzzmeTheme.separator, lineWidth: composerFocused || contrast == .increased ? 2 : SuzzmeTheme.hairline)
            }
            .dropDestination(for: String.self) { values, _ in
                let incoming = values.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !incoming.isEmpty else { return false }
                draft += (draft.isEmpty ? "" : "\n") + incoming
                composerFocused = true
                return true
            }
            Text("Uses only the context you choose.")
                .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var questionField: some View {
        TextField("Ask Suzzme anything…", text: $draft, axis: .vertical)
            .textFieldStyle(.plain).lineLimit(1...4)
            .padding(.vertical, SuzzmeTheme.Spacing.small)
            .focused($composerFocused)
            .onSubmit(send)
            .accessibilityLabel("Your question")
    }

    @ViewBuilder
    private func composerControls(sourceLabel: Bool, summaryLabel: String?) -> some View {
        HStack(alignment: .center, spacing: SuzzmeTheme.Spacing.xs) {
            contextButton
            if !daySourceNames.isEmpty {
                sourceContextButton(expanded: sourceLabel)
            }
            summarizeDayButton(title: summaryLabel)
            Spacer(minLength: 0)
            voiceButton
            sendButton
        }
    }

    private func sourceContextButton(expanded: Bool) -> some View {
        let names = daySourceNames
        let firstName = names.first ?? "Sources"
        let title = expanded
            ? firstName + (names.count > 1 ? " +\(names.count - 1)" : "")
            : "\(names.count) sources"
        return Button { showsContext = true } label: {
            Label(title, systemImage: sourceSymbol(for: firstName))
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, SuzzmeTheme.Spacing.small)
                .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(SuzzmeTheme.separator, lineWidth: SuzzmeTheme.hairline))
        }
        .buttonStyle(.plain)
        .foregroundStyle(SuzzmeTheme.textSecondary)
        .accessibilityLabel("Choose context sources: \(names.joined(separator: ", "))")
        .accessibilityHint("Opens the context source chooser")
    }

    private func sourceSymbol(for source: String) -> String {
        switch source {
        case "Calendar": "calendar"
        case "Reminders": "checklist"
        case "Gmail": "envelope"
        case "Messages": "message"
        case "Watched Links": "globe"
        default: "tray.2"
        }
    }

    private func summarizeDayButton(title: String?) -> some View {
        Button(action: summarizeMyDay) {
            Group {
                if environment.isPreparingBriefing {
                    ProgressView().controlSize(.small)
                        .frame(width: SuzzmeTheme.Layout.touchTarget, height: SuzzmeTheme.Layout.touchTarget)
                } else if let title {
                    Label(title, systemImage: "sun.horizon")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, SuzzmeTheme.Spacing.small)
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                } else {
                    Image(systemName: "sun.horizon")
                        .frame(width: SuzzmeTheme.Layout.touchTarget, height: SuzzmeTheme.Layout.touchTarget)
                }
            }
            .background {
                if !environment.isPreparingBriefing {
                    Capsule()
                        .fill(SuzzmeTheme.intelligenceSurface.opacity(0.45))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(SuzzmeTheme.intelligencePrimary)
        .disabled(environment.isPreparingBriefing)
        .accessibilityLabel(environment.isPreparingBriefing ? "Summarizing your day" : "Summarize my day")
        .accessibilityHint("Checks your allowed sources and opens your Daily Summary")
        .accessibilityIdentifier("suzzme-home-summarize-day")
        .help("Summarize my day")
    }

    private func summarizeMyDay() {
        guard !environment.isPreparingBriefing else { return }
        composerFocused = false
        Task {
            await environment.prepareProactiveBriefing(showActivity: true)
            guard router.selection == .home else { return }
            router.selection = .briefing
        }
    }

    private var contextButton: some View {
        Button { showsContext = true } label: {
            Image(systemName: "plus").frame(width: SuzzmeTheme.Layout.touchTarget, height: SuzzmeTheme.Layout.touchTarget)
        }
        .buttonStyle(.plain).foregroundStyle(SuzzmeTheme.textSecondary)
        .accessibilityLabel("Choose context")
        .help("Choose context")
    }

    private var voiceButton: some View {
        Button(action: talk) {
            Image(systemName: "mic.fill")
                .font(.body.weight(.medium))
                .frame(width: SuzzmeTheme.Layout.touchTarget, height: SuzzmeTheme.Layout.touchTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(SuzzmeTheme.intelligencePrimary)
        .accessibilityLabel("Ask by voice")
        .accessibilityHint("Opens voice capture. Tap Done to send your question.")
        .accessibilityIdentifier("suzzme-home-talk-inline")
        .help("Ask by voice")
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up").font(.body.weight(.semibold))
                .frame(width: SuzzmeTheme.Layout.touchTarget, height: SuzzmeTheme.Layout.touchTarget)
        }
        .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
        .tint(SuzzmeTheme.intelligencePrimary).suzzmeProminentContrast()
        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel("Send question")
        .keyboardShortcut(.return, modifiers: .command)
    }

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        composerFocused = false
        submittedDraft = question
        startsVoice = false
        draft = ""
        showsAssistant = true
    }

    private func talk() {
        composerFocused = false
        submittedDraft = ""
        startsVoice = true
        showsAssistant = true
    }
}

/// Context choices expose their actual retention and permissions before use.
struct ContextChooserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SuzzmeScreenIntroduction(title: "Choose what Suzzme knows", message: "Add only the information you want to use. Each source explains its permissions and how to remove its data.")
                }
                Section("On this device") {
                    NavigationLink { SourcesView() } label: {
                        Label("Calendar, Reminders & Contacts", systemImage: "tray.2")
                    }
                    NavigationLink {
                        Form { SelectedMessageImportView() }.suzzmeSettingsForm().navigationTitle("Selected text")
                    } label: { Label("Paste selected text", systemImage: "doc.on.clipboard") }
                    NavigationLink { MemoryView() } label: {
                        Label("Personal Memory", systemImage: "square.stack.3d.up")
                    }
                }
                #if os(macOS)
                Section {
                    Button {
                        dismiss()
                        Task { await environment.askAboutCurrentScreen() }
                    } label: { Label("Ask about this screen", systemImage: "rectangle.dashed") }
                } footer: {
                    Text("Suzzme asks for consent before capturing screen context for a question. You can cancel the request at any time.")
                }
                #endif
                Section {
                    NavigationLink { IntegrationsView() } label: { Label("Connect apps", systemImage: "puzzlepiece.extension") }
                    NavigationLink { SourcesView() } label: { Label("Manage information sources", systemImage: "tray.2") }
                } footer: {
                    Text("Pasted Messages text is stored locally for up to 7 days. Files and continuous screen sharing are not available in this version.")
                }
            }
            .suzzmeSettingsForm()
            .navigationTitle("Context")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 500)
        #endif
    }
}

#Preview("Home · Light") {
    NavigationStack { HomeView() }.environment(AppEnvironment.preview).environment(AppRouter()).preferredColorScheme(.light)
}
#Preview("Home · Dark") {
    NavigationStack { HomeView() }.environment(AppEnvironment.preview).environment(AppRouter()).preferredColorScheme(.dark)
}
#Preview("Home · Accessible type") {
    NavigationStack { HomeView() }.environment(AppEnvironment.preview).environment(AppRouter()).environment(\.dynamicTypeSize, .accessibility3)
}
#Preview("Home · Mac width") {
    NavigationStack { HomeView() }.environment(AppEnvironment.preview).environment(AppRouter()).frame(width: 900, height: 600)
}
