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
                Text("This is your preferred time. Apple’s scheduling and power rules may delay preparation or delivery.")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
            }

            Section("Helpful Moments") {
                Toggle("Time-Critical Intelligence", isOn: $timeCriticalEnabled)
                Text("Allows rare, privacy-preserving alerts when waiting would make useful information less useful.")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)

                Toggle("Prepared Assistance", isOn: $preparedAssistanceEnabled)
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
        .navigationTitle("Proactive Intelligence")
        .confirmationDialog("Reset proactive data and preferences?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset Proactive Data", role: .destructive) { Task { await environment.resetProactiveData(); load() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This deletes Daily Summary, Today context, suggestions, and delivery history, and restores proactive preferences. Pending Suzzme alerts are cancelled. Personal Memory and source information are kept. This cannot be undone.")
        }
        .task { load() }
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
}
