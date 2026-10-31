import SwiftUI

struct ProactiveIntelligenceSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var dailyBriefingEnabled = true
    @State private var timeCriticalEnabled = false
    @State private var preparedAssistanceEnabled = true
    @State private var selectedTime = Date.now
    @State private var timeZoneIdentifier = TimeZone.current.identifier
    @State private var loaded = false
    @State private var confirmsClear = false
    @State private var confirmsReset = false
    @State private var pendingSave: Task<Void, Never>?

    var body: some View {
        List {
            Section("Daily Summary") {
                Toggle("Daily Summary", isOn: $dailyBriefingEnabled)
                DatePicker("Preferred Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    .disabled(!dailyBriefingEnabled)
                Text("A private daily notification reminds you to open your summary at this local time. Suzzme checks fresh context when you open it. Apple may delay or silence notifications.")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                if dailyBriefingEnabled && !environment.summaryNotificationsAuthorized {
                    Text("Notifications are off or unavailable. You can still open Daily Summary anytime.")
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    Button("Enable Summary Notifications") { Task { await environment.requestSummaryNotificationAuthorization() } }
                }
            }

            #if os(macOS)
            ScheduledBriefingSettingsSection()
            Section("Schedule on both devices") {
                if environment.companionDeliveryPreferences != nil {
                    Label("Schedule saved to your account", systemImage: "checkmark.circle")
                }
                if let error = environment.companionDeliveryError {
                    Text(error).foregroundStyle(SuzzmeTheme.destructive)
                }
                Button("Refresh shared schedule") {
                    Task { await environment.refreshCompanionSchedule(); load() }
                }
                Text("Changes made on iPhone reach this Mac while Suzzme is running. The selected time zone is shared between devices.")
                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            Section("iPhone Sharing") {
                if let email = environment.companionAccountEmail {
                    LabeledContent("Suzzme account", value: email)
                    Toggle("Share prepared Daily Summary with iPhone", isOn: Binding(
                        get: { environment.sharesSummaryWithIPhone },
                        set: { enabled in Task { await environment.setCompanionSharing(enabled) } }
                    ))
                    .disabled(!dailyBriefingEnabled && !timeCriticalEnabled)
                    if !dailyBriefingEnabled && !timeCriticalEnabled {
                        Text("Turn on Daily Summary or Time-Sensitive Help before sharing updates with iPhone.")
                            .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                    Text("Only the prepared summary, short day items, source names, and check times are shared. Raw emails, messages, source credentials, and Mac permissions stay on this Mac.")
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    if environment.sharesSummaryWithIPhone {
                        if let publishedAt = environment.lastCompanionPublishAt {
                            LabeledContent("Shared this session") {
                                Text(publishedAt, format: .dateTime.hour().minute())
                            }
                        }
                        Button("Prepare and share now") {
                            Task { await environment.prepareProactiveBriefing(showActivity: true) }
                        }
                        .disabled(environment.isPreparingBriefing)
                    }
                    if let snapshot = environment.proactiveSnapshot,
                       let shared = CompanionSummary(snapshot: snapshot) {
                        DisclosureGroup("Preview what iPhone receives") {
                            Text(shared.narration).font(.subheadline)
                            ForEach(shared.items) { item in
                                LabeledContent(item.title, value: item.source)
                            }
                            Text("Sources: \(shared.sources.joined(separator: ", "))")
                                .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                        }
                    }
                } else {
                    Text("Sign in to the same Suzzme account on Mac and iPhone to share a prepared Daily Summary.")
                        .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                    NavigationLink("Open Account") { ProfileSettingsView() }
                }
                if let error = environment.companionError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
            MacLaunchAtLoginSettingsSection()
            #endif

            Section("Helpful Moments") {
                Toggle("Time-Sensitive Help", isOn: $timeCriticalEnabled)
                Text("Allows rare, privacy-preserving alerts when waiting would make useful information less useful.")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)

                Toggle("Prepare Suggestions", isOn: $preparedAssistanceEnabled)
                Text("Suzzme may prepare a suggestion for you to review. It never authorizes or performs an action.")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
            }

            Section("Data") {
                Button("Clear Briefings and Suggestions", role: .destructive) {
                    confirmsClear = true
                }
                Text("This clears only Daily Summary, opportunity, and delivery history. Memory, Calendar, Reminders, and source information remain unchanged.")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
            }

            if let error = environment.proactiveError {
                Section {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                    Button("Reset Proactive Data and Preferences…", role: .destructive) { confirmsReset = true }
                }
            }
        }
        .suzzmeReadableList()
        .navigationTitle("Daily Summary & Suggestions")
        .confirmationDialog("Reset proactive data and preferences?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset Proactive Data", role: .destructive) { Task { await environment.resetProactiveData(); load() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This deletes Daily Summary, Today context, suggestions, and delivery history, and restores proactive preferences. Pending Suzzme alerts are cancelled. Personal Memory and source information are kept. This cannot be undone.")
        }
        .task {
            await environment.loadProactiveState()
            #if os(macOS)
            environment.loadCompanionSharingState()
            #endif
            load()
        }
        .onChange(of: environment.proactivePreferences.timeZoneIdentifier) { _, _ in load() }
        .onChange(of: dailyBriefingEnabled) { _, _ in saveIfLoaded() }
        .onChange(of: timeCriticalEnabled) { _, _ in saveIfLoaded() }
        .onChange(of: preparedAssistanceEnabled) { _, _ in saveIfLoaded() }
        .onChange(of: selectedTime) { _, _ in saveIfLoaded() }
        .onDisappear {
            pendingSave?.cancel()
            pendingSave = nil
            saveIfLoaded(debounce: false)
        }
        .confirmationDialog(
            "Clear proactive intelligence data?",
            isPresented: $confirmsClear,
            titleVisibility: .visible
        ) {
            Button("Clear Briefings and Suggestions", role: .destructive) {
                Task { await environment.clearProactiveContent() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Personal Memory and source information will not be deleted.")
        }
    }

    private func load() {
        let preferences = environment.proactivePreferences
        dailyBriefingEnabled = preferences.dailyBriefingEnabled
        timeCriticalEnabled = preferences.timeCriticalEnabled
        preparedAssistanceEnabled = preferences.preparedAssistanceEnabled
        timeZoneIdentifier = preferences.timeZoneIdentifier
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        selectedTime = calendar.date(bySettingHour: preferences.briefingHour, minute: preferences.briefingMinute, second: 0, of: .now) ?? .now
        loaded = true
    }

    private func saveIfLoaded(debounce: Bool = true) {
        guard loaded else { return }
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let components = calendar.dateComponents([.hour, .minute], from: selectedTime)
        let preferences = ProactivePreferences(
            dailyBriefingEnabled: dailyBriefingEnabled,
            briefingHour: components.hour ?? 8,
            briefingMinute: components.minute ?? 0,
            timeZoneIdentifier: timeZoneIdentifier,
            timeCriticalEnabled: timeCriticalEnabled,
            preparedAssistanceEnabled: preparedAssistanceEnabled
        )
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            if debounce {
                do { try await Task.sleep(for: .milliseconds(180)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            await environment.updateProactivePreferences(preferences)
            pendingSave = nil
        }
    }
}

#Preview {
    NavigationStack { ProactiveIntelligenceSettingsView() }
        .environment(AppEnvironment.preview)
        #if os(macOS)
        .environment(MacLaunchAtLoginController())
        #endif
}
