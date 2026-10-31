#if os(iOS)
import SwiftUI
import UIKit
import FirebaseAuth

/// The same content reflows when a foldable phone changes from its narrow
/// outer display to its wider inner display. No screen-shape assumption owns
/// the summary or navigation state.
struct MobileCompanionTodayView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedDate = Date.now
    @State private var showsCalendar = false

    private var dayLabel: String {
        if Calendar.current.isDateInToday(selectedDate) { return "Today" }
        if Calendar.current.isDateInYesterday(selectedDate) { return "Yesterday" }
        return selectedDate.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var selectedSummary: CompanionSummary? {
        guard let uid = CompanionSummaryStore.currentUser?.uid else { return nil }
        let values = [environment.companionSummary].compactMap { $0 } + CompanionSummaryStore.cachedDays(for: uid)
        return values.first { summary in
            var calendar = Calendar.current
            calendar.timeZone = TimeZone(identifier: summary.timeZoneIdentifier) ?? .current
            return calendar.isDate(summary.localDay, inSameDayAs: selectedDate)
        }
    }

    var body: some View {
        Group {
            if CompanionSummaryStore.currentUser == nil {
                VStack(spacing: 0) {
                    NavigationLink {
                        ProfileSettingsView()
                    } label: {
                        Label("Sign in to see your Mac summary", systemImage: "person.crop.circle")
                            .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                    }
                    .padding(.horizontal, SuzzmeTheme.Layout.compactInset)
                    .accessibilityIdentifier("suzzme-companion-sign-in")
                    ContentUnavailableView("Your day comes from your Mac", systemImage: "desktopcomputer",
                        description: Text("Sign in with the same account to receive and listen to your prepared Daily Summary."))
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.extraLarge) {
                        if let summary = selectedSummary, Calendar.current.isDateInToday(selectedDate) {
                            MobileCompanionDayContent(summary: summary)
                        } else if let summary = selectedSummary {
                            MobileSavedSummaryContent(summary: summary, accountUID: CompanionSummaryStore.currentUser?.uid ?? "")
                        } else {
                            waitingContent
                        }
                    }
                    .padding(.horizontal, SuzzmeTheme.Layout.compactInset)
                    .padding(.vertical, SuzzmeTheme.Spacing.large)
                    .frame(maxWidth: SuzzmeTheme.Layout.workspaceWidth)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .refreshable { await environment.loadCompanionSummary() }
                .background(SuzzmeTheme.pageBackground)
                .simultaneousGesture(DragGesture(minimumDistance: 60).onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height),
                          let next = Calendar.current.date(byAdding: .day, value: value.translation.width < 0 ? -1 : 1, to: selectedDate),
                          Calendar.current.startOfDay(for: next) <= Calendar.current.startOfDay(for: .now) else { return }
                    selectedDate = next
                })
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showsCalendar = true } label: {
                    HStack(spacing: SuzzmeTheme.Spacing.xs) { Text(dayLabel).font(.headline); Image(systemName: "chevron.down").font(.caption) }
                        .padding(.horizontal, SuzzmeTheme.Spacing.medium)
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                        .suzzmeGlassSurface(cornerRadius: SuzzmeTheme.Layout.touchTarget / 2)
                }.buttonStyle(.plain).accessibilityLabel("Summary date: \(dayLabel)")
            }
        }
        .sheet(isPresented: $showsCalendar) {
            NavigationStack {
                DatePicker("Summary date", selection: $selectedDate, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical).padding()
                    .navigationTitle("Choose a day")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Today") { selectedDate = .now; showsCalendar = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showsCalendar = false } }
                    }
            }.presentationDetents([.medium, .large])
        }
        .task { await environment.loadCompanionSummary() }
    }

    private var waitingContent: some View {
        VStack(spacing: SuzzmeTheme.Spacing.large) {
            SuzzmeMascot(state: .idle, size: SuzzmeTheme.Layout.companionFace)
                .accessibilityHidden(true)
            Text("Your day, from your Mac")
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(environment.isLoadingCompanionSummary ? "Checking for your Mac summary…" :
                    environment.companionError != nil ? "Your summary couldn’t be checked right now." :
                    Calendar.current.isDateInToday(selectedDate) ? "Your Mac has not shared a Daily Summary yet." :
                    "No summary for this day was saved on this iPhone.")
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .multilineTextAlignment(.center)
            if environment.isLoadingCompanionSummary { ProgressView() }
            if let error = environment.companionError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            NavigationLink {
                MobileMacSetupView()
            } label: {
                Text("Set up your Mac").frame(minHeight: SuzzmeTheme.Layout.touchTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(SuzzmeTheme.intelligencePrimary)
            Text("Signed in as \(environment.companionAccountEmail ?? "your Suzzme account")")
                .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
        .padding(.top, SuzzmeTheme.Spacing.hero)
    }
}

private struct MobileSavedSummaryContent: View {
    let summary: CompanionSummary
    let accountUID: String
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.large) {
            SuzzmeMascot(state: .idle, size: SuzzmeTheme.Layout.companionFace).accessibilityHidden(true)
                .frame(maxWidth: .infinity)
            Text("Your day, from your Mac").font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center).frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
            Text(summary.localDay, format: .dateTime.weekday(.wide).month().day())
                .foregroundStyle(SuzzmeTheme.textSecondary).frame(maxWidth: .infinity)
            Text(summary.narration).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Button {
                guard CompanionSummaryStore.currentUser?.uid == accountUID,
                      CompanionSummaryStore.cachedDays(for: accountUID).contains(summary) else { return }
                environment.voice.speak(summary.narration, preserveFullText: true)
            } label: { Label("Listen to summary", systemImage: "speaker.wave.2") }
            .disabled(!environment.voice.speaksResponses || !environment.voice.canStartSpeech)
            ForEach(summary.items) { item in
                Divider()
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                    Text(item.title).font(.headline)
                    Text(item.detail)
                    Text(item.source).font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
            ForEach(summary.limitations, id: \.self) { limitation in
                Label(limitation, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MobileCompanionDayContent: View {
    let summary: CompanionSummary
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isToday: Bool {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: summary.timeZoneIdentifier) ?? .current
        return calendar.isDateInToday(summary.localDay)
    }
    private var isFresh: Bool {
        isToday && Date.now.timeIntervalSince(summary.generatedAt) < ProactiveLimits.briefingFreshness
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                singleColumn
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.extraLarge) {
                        introduction.frame(minWidth: 300, maxWidth: .infinity)
                        summaryColumn.frame(minWidth: 300, maxWidth: .infinity)
                    }
                    singleColumn
                }
            }
        }
    }

    private var singleColumn: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.extraLarge) {
            introduction
            summaryColumn
        }
    }

    private var introduction: some View {
        VStack(alignment: .center, spacing: SuzzmeTheme.Spacing.medium) {
            SuzzmeMascot(state: environment.presenceState, size: SuzzmeTheme.Layout.companionFace,
                animation: environment.invocation.presenceAnimation)
                .accessibilityHidden(true)
            Text("Your day, from your Mac")
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(summary.generatedAt, format: .dateTime.weekday(.wide).month().day())
                .font(.title3).foregroundStyle(SuzzmeTheme.textSecondary)
            if let email = environment.companionAccountEmail {
                Label("Suzzme account: \(email)", systemImage: "person.crop.circle")
                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    .textSelection(.enabled)
            }
            Button { environment.readCompanionSummaryAloud() } label: {
                Label(environment.voice.isSpeaking ? "Stop reading" : "Read my day", systemImage: environment.voice.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(SuzzmeTheme.intelligencePrimary)
            .suzzmeProminentContrast()
            .accessibilityIdentifier("suzzme-mobile-ask-day")
            .disabled(!environment.voice.speaksResponses || environment.voice.isPreparingSpeech)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var summaryColumn: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            Label("From your Mac", systemImage: "desktopcomputer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SuzzmeTheme.intelligencePrimary)
            Text(isFresh ? "Updated \(summary.generatedAt.formatted(date: .omitted, time: .shortened))" :
                    "Last shared \(summary.generatedAt.formatted(date: .abbreviated, time: .shortened)) · May be out of date")
                .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
            if let error = environment.companionError {
                Label("Could not check for a newer summary. Showing the last one saved on this iPhone.",
                      systemImage: "wifi.exclamationmark")
                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    .accessibilityHint(error)
            }
            Text(summary.narration)
                .font(.body)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
            if summary.isPartial {
                Label("Some sources could not be checked", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            NavigationLink(value: AppDestination.briefing) {
                Label("Read Daily Summary", systemImage: "arrow.right")
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
            }
            .font(.subheadline.weight(.semibold))
            if let first = summary.items.first {
                Divider()
                Text("Up next").font(.headline).accessibilityAddTraits(.isHeader)
                Text(first.title).font(.body.weight(.medium))
                if let date = first.effectiveAt {
                    Text(date, format: .dateTime.hour().minute())
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
            if !summary.sources.isEmpty {
                Text("From \(summary.sources.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MobileCompanionSummaryView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Group {
            if CompanionSummaryStore.currentUser == nil {
                ContentUnavailableView("Sign in to receive your summary", systemImage: "person.crop.circle",
                    description: Text("Your Mac prepares it and shares it with the same account on this iPhone."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.large) {
                        if let summary = environment.companionSummary {
                            Text("Your Daily Summary")
                                .font(.largeTitle.weight(.semibold)).accessibilityAddTraits(.isHeader)
                            Label("From your Mac · \(summary.generatedAt.formatted(date: .abbreviated, time: .shortened))",
                                  systemImage: "desktopcomputer")
                                .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                            Text(summary.narration).font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                            Button { environment.readCompanionSummaryAloud() } label: {
                                Label(environment.voice.isSpeaking ? "Stop reading" : "Read Daily Summary",
                                      systemImage: environment.voice.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                            }
                            .disabled(!environment.voice.speaksResponses || environment.voice.isPreparingSpeech)
                            ForEach(summary.items) { item in
                                Divider()
                                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                                    Text(item.title).font(.headline)
                                    Text(item.detail).font(.body)
                                    HStack {
                                        Text(item.source)
                                        if let date = item.effectiveAt {
                                            Text("·")
                                            Text(date, format: .dateTime.month().day().hour().minute())
                                        }
                                    }
                                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                                }
                            }
                            if !summary.limitations.isEmpty {
                                Divider()
                                Label("Some sources could not be checked", systemImage: "exclamationmark.triangle")
                                    .font(.headline)
                                ForEach(summary.limitations, id: \.self) { limitation in
                                    Text(limitation).font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                                }
                            }
                            NavigationLink { MobileMacSourcesView() } label: {
                                Label("Sources in this summary", systemImage: "tray.2")
                                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                            }
                        } else {
                            ContentUnavailableView("No Mac summary yet", systemImage: "desktopcomputer",
                                description: Text("Set up sharing in Suzzme on your Mac, then check again."))
                            if let error = environment.companionError {
                                Label(error, systemImage: "wifi.exclamationmark")
                                    .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                            }
                            NavigationLink("Set up your Mac") { MobileMacSetupView() }
                        }
                    }
                    .padding(SuzzmeTheme.Layout.compactInset)
                    .frame(maxWidth: SuzzmeTheme.Layout.readingWidth)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await environment.loadCompanionSummary() }
            }
        }
        .navigationTitle("Daily Summary")
        .task {
            if !environment.hasCheckedCompanionSummary { await environment.loadCompanionSummary() }
        }
    }
}

struct MobileMacSourcesView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        List {
            if let summary = environment.companionSummary {
                Section("Included in latest summary") {
                    ForEach(summary.sources, id: \.self) { source in
                        Label(source, systemImage: "checkmark.circle")
                    }
                    if summary.sources.isEmpty { Text("No source contributed to the latest summary.") }
                }
                if !summary.limitations.isEmpty {
                    Section("Could not be checked") {
                        ForEach(summary.limitations, id: \.self) { limitation in Text(limitation) }
                    }
                }
                Section {
                    Text("Your Mac checked these sources at \(summary.generatedAt.formatted(date: .abbreviated, time: .shortened)). Change source access and iPhone sharing in Suzzme on your Mac.")
                }
            } else {
                Section { Text("Your Mac has not shared a summary yet.") }
            }
        }
        .suzzmeReadableList()
        .navigationTitle("Mac Sources")
        .task {
            if !environment.hasCheckedCompanionSummary { await environment.loadCompanionSummary() }
        }
    }
}

struct MobileMacSetupView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        List {
            Section {
                Text("Use the same Suzzme account on your Mac and this iPhone.")
                    .font(.headline)
                if let email = environment.companionAccountEmail {
                    LabeledContent("This iPhone", value: email)
                } else {
                    NavigationLink("Sign in to your Suzzme account") { ProfileSettingsView() }
                }
            }
            Section("On your Mac") {
                Label("Open Suzzme and sign in with this account", systemImage: "1.circle")
                Label("Choose the sources Suzzme may read", systemImage: "2.circle")
                Label("In Daily Summary settings, turn on Share with iPhone", systemImage: "3.circle")
                Label("Prepare a Daily Summary", systemImage: "4.circle")
            }
            Section {
                Text("Google account sign-in does not give Suzzme access to Gmail or Google Calendar. Choose those sources separately on your Mac.")
            }
            Section {
                Button("Check for summary") { Task { await environment.loadCompanionSummary() } }
                    .disabled(environment.isLoadingCompanionSummary)
                if let error = environment.companionError {
                    Text(error).foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
        }
        .suzzmeReadableList()
        .navigationTitle("Connect your Mac")
    }
}

struct MobileCompanionDeliverySettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var routine = true
    @State private var urgent = true
    @State private var dailyEnabled = true
    @State private var urgentEnabled = false
    @State private var time = Date.now
    @State private var timeZoneIdentifier = TimeZone.current.identifier
    @State private var saved = false

    private var uid: String? { CompanionSummaryStore.currentUser?.uid }
    private var zone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    var body: some View {
        Form {
            Section("Shared summary schedule") {
                Toggle("Daily summary", isOn: $dailyEnabled)
                DatePicker("Summary time", selection: $time, displayedComponents: .hourAndMinute)
                    .environment(\.timeZone, zone)
                    .disabled(!dailyEnabled)
                LabeledContent("Time zone", value: timeZoneIdentifier)
                Toggle("Important updates at any time", isOn: $urgentEnabled)
                Button("Save schedule for both devices") {
                    Task {
                        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
                        var value = ProactivePreferences()
                        value.dailyBriefingEnabled = dailyEnabled; value.timeCriticalEnabled = urgentEnabled
                        value.briefingHour = calendar.component(.hour, from: time)
                        value.briefingMinute = calendar.component(.minute, from: time)
                        value.timeZoneIdentifier = timeZoneIdentifier
                        await environment.saveCompanionSchedule(from: value)
                        saved = environment.companionDeliveryError == nil
                    }
                }
                .disabled(environment.isSavingCompanionSchedule || uid == nil)
                if environment.isSavingCompanionSchedule { ProgressView("Saving schedule…") }
                if saved { Label("Schedule shared with your Mac", systemImage: "checkmark.circle") }
                if let error = environment.companionDeliveryError { Text(error).foregroundStyle(SuzzmeTheme.destructive) }
                Text("Your Mac picks up this schedule while Suzzme is running. It prepares the summary using your allowed sources and shares it with this account. Your Mac must be awake; missed summaries catch up when it returns.")
                    .foregroundStyle(SuzzmeTheme.textSecondary)
            }
            .disabled(uid == nil)
            Section("Notifications & Dynamic Island") {
                Button("Enable notifications") { Task { await CompanionPushRegistration.shared.enable() } }
                    .disabled(uid == nil)
                Text(CompanionPushRegistration.shared.status).foregroundStyle(SuzzmeTheme.textSecondary)
                if let settings = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open iPhone notification settings", destination: settings)
                }
                Text("New summaries appear in the Dynamic Island on supported iPhones, with a Lock Screen fallback. Tap to open the summary. Apple push delivery requires the configured server and a push-enabled signed build.")
                    .foregroundStyle(SuzzmeTheme.textSecondary)
            }
            Section {
                Toggle("Read routine summaries aloud", isOn: $routine)
                Toggle("Speak urgent updates", isOn: $urgent)
            } header: { Text("Readouts on this iPhone") } footer: {
                Text("Automatic speech plays while Suzzme is open. When it is closed, iOS can deliver an alert or Live Activity; open Suzzme to hear the full update.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(uid == nil)
            Section {
                NavigationLink("Voice and speaking pace") { VoiceSettingsView() }
                Button("Check for updates") {
                    Task { await environment.refreshCompanionSchedule(); await environment.loadCompanionSummary(); loadSchedule() }
                }
                .disabled(environment.isLoadingCompanionSummary || uid == nil)
                if uid == nil { Text("Sign in with the same account as your Mac to receive summaries.") }
            }
        }
        .suzzmeSettingsForm()
        .navigationTitle("Summary & urgent updates")
        .task {
            guard let uid else { return }
            routine = CompanionPlaybackPreferences.routineEnabled(for: uid)
            urgent = CompanionPlaybackPreferences.urgentEnabled(for: uid)
            await environment.refreshCompanionSchedule()
            loadSchedule()
        }
        .onChange(of: routine) { _, value in
            if let uid {
                CompanionPlaybackPreferences.setRoutine(value, for: uid)
                Task { await CompanionPushRegistration.shared.synchronize() }
            }
        }
        .onChange(of: urgent) { _, value in
            if let uid {
                CompanionPlaybackPreferences.setUrgent(value, for: uid)
                Task { await CompanionPushRegistration.shared.synchronize() }
            }
        }
    }

    private func loadSchedule() {
        let preferences = environment.companionDeliveryPreferences
        let schedule = environment.companionSummary?.delivery?.schedule
        dailyEnabled = preferences?.daily_enabled ?? schedule?.enabled ?? true
        urgentEnabled = preferences?.urgent_enabled ?? false
        timeZoneIdentifier = preferences?.time_zone ?? schedule?.timeZoneIdentifier ?? TimeZone.current.identifier
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        time = calendar.date(bySettingHour: preferences?.hour ?? schedule?.hour ?? 8,
            minute: preferences?.minute ?? schedule?.minute ?? 0, second: 0, of: .now) ?? .now
        saved = false
    }
}

#if DEBUG
private extension CompanionSummary {
    static let foldablePreview = CompanionSummary(
        version: 1, generatedAt: .now, localDay: .now,
        timeZoneIdentifier: TimeZone.current.identifier,
        narration: "You have a calm start. Your design review is at 11, and your project notes are ready when you need them.",
        items: [CompanionSummaryItem(id: 0, title: "Design review", detail: "At 11:00 AM with your team",
            source: "Calendar", kind: .schedule, effectiveAt: .now.addingTimeInterval(3600))],
        sources: ["Calendar", "Gmail"], limitations: [])
}

#Preview("Duo · outer screen") {
    NavigationStack { MobileCompanionDayContent(summary: .foldablePreview) }
        .environment(AppEnvironment.preview)
        .frame(width: 360, height: 760)
}
#Preview("Duo · narrow outer screen") {
    NavigationStack { MobileCompanionDayContent(summary: .foldablePreview) }
        .environment(AppEnvironment.preview)
        .frame(width: 320, height: 700)
}
#Preview("Duo · inner screen") {
    NavigationStack { MobileCompanionDayContent(summary: .foldablePreview) }
        .environment(AppEnvironment.preview)
        .frame(width: 720, height: 760)
}
#Preview("Duo · inner screen · large text") {
    NavigationStack { MobileCompanionDayContent(summary: .foldablePreview) }
        .environment(AppEnvironment.preview)
        .environment(\.dynamicTypeSize, .accessibility3)
        .frame(width: 720, height: 760)
}
#endif
#endif
