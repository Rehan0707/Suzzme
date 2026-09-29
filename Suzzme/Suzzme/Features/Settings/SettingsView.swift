import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        List {
            Section {
                HStack(spacing: SuzzmeTheme.Spacing.medium) {
                    SuzzmeMark().frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                        Text("Suzzme").font(.title2.weight(.semibold))
                        Text("A quieter kind of intelligence.")
                            .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                }
                .padding(.vertical, SuzzmeTheme.Spacing.xs)
            }

            Section("Suzzme") {
                NavigationLink { VoiceSettingsView() } label: {
                    SettingsRow(symbol: "speaker.wave.2", title: "Voice", detail: environment.voice.speaksResponses ? "Responses on" : "Responses off")
                }
                NavigationLink { PresenceSettingsView() } label: {
                    SettingsRow(symbol: "face.smiling", title: "Presence", detail: environment.invocation.presenceTheme.title)
                }
                NavigationLink { InvocationSettingsView() } label: {
                    SettingsRow(symbol: "mic", title: "Talk to Suzzme", detail: "Shortcuts and controls")
                }
                NavigationLink { MemoryView() } label: {
                    SettingsRow(symbol: "square.stack.3d.up", title: "Memory", detail: "What Suzzme remembers")
                }
            }

            Section("Intelligence") {
                NavigationLink { ProactiveIntelligenceSettingsView() } label: {
                    SettingsRow(symbol: "sun.horizon", title: "Daily Summary", detail: environment.proactivePreferences.dailyBriefingEnabled ? "On" : "Off")
                }
                NavigationLink { SourcesView().navigationTitle("Sources") } label: {
                    SettingsRow(symbol: "tray.2", title: "Sources", detail: "Access and recent information")
                }
                NavigationLink { PrivacyView() } label: {
                    SettingsRow(symbol: "lock.shield", title: "Privacy", detail: "On-device controls")
                }
            }

            Section("Personal") {
                NavigationLink { ProfileSettingsView() } label: {
                    SettingsRow(symbol: "person.crop.circle", title: "Profile", detail: "Stored on this device")
                }
            }

            Section("About") {
                NavigationLink { AboutSuzzmeView() } label: {
                    SettingsRow(symbol: "info.circle", title: "About Suzzme", detail: "Version and principles")
                }
                LabeledContent("Appearance", value: "Follows System")
            }

            #if DEBUG
            Section("Developer") {
                NavigationLink { SuzzmeBrainLabView() } label: {
                    Label("Suzzme Brain Lab", systemImage: "brain")
                }
                NavigationLink { PresenceMotionLabView() } label: {
                    Label("Presence Motion Lab", systemImage: "waveform.path")
                }
            }
            #endif
        }
        .navigationTitle("Settings")
    }
}

private struct SettingsRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(SuzzmeTheme.textSecondary)
        }
    }
}
