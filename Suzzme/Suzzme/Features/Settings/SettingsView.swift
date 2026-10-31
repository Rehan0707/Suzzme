import AVFoundation
import SwiftUI

struct SettingsView: View {
    /// The main Mac window already owns a sidebar. Its Settings route keeps the
    /// shared overview; the dedicated Settings scene gets desktop navigation.
    var usesDesktopSidebar = true
    @Environment(AppEnvironment.self) private var environment
    @AppStorage("suzzme.appearance") private var appearancePreference = SuzzmeAppearance.system.rawValue

    private var voiceName: String {
        if environment.voice.speechEngine == .cloud { return "Suzzme Voice" }
        if environment.voice.speechEngine == .natural, environment.voice.naturalVoiceIsReady { return "Natural Voice" }
        return environment.voice.availableVoices.first { $0.identifier == environment.voice.selectedVoiceIdentifier }?.name ?? "System voice"
    }
    private var summarySchedule: String {
        guard environment.proactivePreferences.dailyBriefingEnabled else { return "Off" }
        let components = DateComponents(hour: environment.proactivePreferences.briefingHour, minute: environment.proactivePreferences.briefingMinute)
        return Calendar.current.date(from: components)?.formatted(date: .omitted, time: .shortened) ?? "On"
    }

    var body: some View {
        Group {
            #if os(macOS)
            if usesDesktopSidebar {
                MacSettingsView()
            } else {
                settingsOverview
            }
            #else
            settingsOverview
            #endif
        }
        .task {
            #if os(macOS)
            await environment.loadProactiveState()
            #else
            await environment.loadCompanionSummary()
            #endif
        }
    }

    private var settingsOverview: some View {
        Form {
            Section("Companion") {
                NavigationLink { VoiceSettingsView() } label: {
                    SettingsRow(symbol: "speaker.wave.2", title: "Voice", detail: environment.voice.speaksResponses ? voiceName : "Spoken responses off")
                }
                NavigationLink { PresenceSettingsView() } label: {
                    SettingsRow(symbol: "face.smiling", title: "Presence", detail: "\(SuzzmeMascotAppearance.shared.color.title) companion")
                }
                #if os(macOS)
                NavigationLink { InvocationSettingsView() } label: {
                    SettingsRow(symbol: "mic", title: "Talk to Suzzme", detail: "Shortcuts and controls")
                }
                #endif
            }
            Section("Your day") {
                #if os(iOS)
                NavigationLink { MobileCompanionSummaryView() } label: {
                    SettingsRow(symbol: "sun.horizon", title: "Daily Summary", detail: "Prepared on your Mac")
                }
                #else
                NavigationLink { ProactiveIntelligenceSettingsView() } label: {
                    SettingsRow(symbol: "sun.horizon", title: "Summary schedule", detail: "Daily Summary · \(summarySchedule)")
                }
                #endif
            }
            Section("Your information") {
                #if os(iOS)
                NavigationLink { MobileMacSetupView() } label: {
                    SettingsRow(symbol: "desktopcomputer", title: "Account & Mac", detail: "Connect and check your Mac summary")
                }
                NavigationLink { MobileMacSourcesView() } label: {
                    SettingsRow(symbol: "tray.2", title: "Mac Sources", detail: "Sources in your latest shared summary")
                }
                #endif
                NavigationLink { PrivacyView() } label: {
                    SettingsRow(symbol: "lock.shield", title: "Privacy", detail: "On-device processing and controls")
                }
                #if os(iOS)
                NavigationLink { MobileCompanionDeliverySettingsView() } label: {
                    SettingsRow(symbol: "bell", title: "Summary & urgent updates", detail: "Readouts and Mac summary time")
                }
                #else
                NavigationLink { SummaryNotificationsView() } label: {
                    SettingsRow(symbol: "bell", title: "Notifications", detail: environment.summaryNotificationsAuthorized ? "Daily reminders allowed" : "Daily reminders off")
                }
                #endif
            }
            Section("Appearance and accessibility") {
                Picker("Appearance", selection: $appearancePreference) {
                    ForEach(SuzzmeAppearance.allCases) { appearance in Text(appearance.title).tag(appearance.rawValue) }
                }.accessibilityIdentifier("suzzme-appearance-picker")
                NavigationLink { CompanionAccessibilityView() } label: {
                    SettingsRow(symbol: "accessibility", title: "Accessibility", detail: "Motion, transparency, and reading")
                }
            }
            Section {
                NavigationLink { ProfileSettingsView() } label: { SettingsRow(symbol: "person.crop.circle", title: "Profile", detail: "Your name, stored on this device") }
                NavigationLink { AboutSuzzmeView() } label: { SettingsRow(symbol: "info.circle", title: "About Suzzme", detail: "Version and principles") }
            }
        }
        .suzzmeSettingsForm().navigationTitle("Settings")
    }
}

private struct SettingsRow: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        } icon: { Image(systemName: symbol).foregroundStyle(SuzzmeTheme.textSecondary) }
    }
}

/// Shows the actual summary-delivery grant; it does not pretend to change system permission.
struct SummaryNotificationsView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        List {
            Section {
                LabeledContent("Daily reminders", value: environment.summaryNotificationsAuthorized ? "Allowed" : "Off or unavailable")
                if !environment.summaryNotificationsAuthorized {
                    Button("Allow Summary Notifications") { Task { await environment.requestSummaryNotificationAuthorization() } }
                }
                NavigationLink("Daily Summary delivery") { ProactiveIntelligenceSettingsView() }
            } footer: {
                Text("A reminder opens your summary at the time you choose. System settings and Focus can delay or silence it.")
            }
            Section {
                Toggle("Time-sensitive help", isOn: Binding(get: { environment.proactivePreferences.timeCriticalEnabled }, set: { enabled in
                    var preferences = environment.proactivePreferences
                    preferences.timeCriticalEnabled = enabled
                    Task { await environment.updateProactivePreferences(preferences) }
                }))
            } header: { Text("Helpful moments") } footer: {
                Text("Rare alerts for useful information that should not wait. Suzzme never performs an action from a notification.")
            }
        }
        .suzzmeReadableList()
        .navigationTitle("Notifications")
        .task { await environment.loadProactiveState() }
    }
}

struct CompanionAccessibilityView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        List {
            Section {
                LabeledContent("Reduce Motion", value: reduceMotion ? "On" : "Off")
                LabeledContent("Reduce Transparency", value: reduceTransparency ? "On" : "Off")
            } header: { Text("System settings") } footer: {
                Text("Suzzme follows your device’s accessibility settings. Change these in system Accessibility settings.")
            }
            Section {
                NavigationLink("Voice and spoken responses") { VoiceSettingsView() }
                NavigationLink("Presence appearance") { PresenceSettingsView() }
            } header: { Text("Reading and presence") } footer: {
                Text("Text follows your preferred size. Suzzme’s state is described in words as well as motion and color.")
            }
        }.suzzmeReadableList()
        .navigationTitle("Accessibility")
    }
}
