import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        SuzzmePage {
            HStack(spacing: 16) {
                SuzzmeMark().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suzzme").font(.title.weight(.semibold))
                    Text("A quieter kind of intelligence.").foregroundStyle(.secondary)
                }
            }
            SuzzmeCard {
                Label("Local first, from the start", systemImage: "lock.shield").font(.headline)
                Text("This version runs entirely on your device with sample information. No account, server, or internet connection is needed.").foregroundStyle(.secondary)
            }
            SuzzmeCard {
                LabeledContent("Appearance", value: "Follows system")
                Text("Suzzme follows your text size, motion, and transparency accessibility settings.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            NavigationLink { VoiceSettingsView() } label: {
                SuzzmeCard {
                    LabeledContent("Voice", value: environment.voice.speaksResponses ? "Responses on" : "Responses off")
                    Text("Choose a system voice and control spoken responses.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain)
            NavigationLink { InvocationSettingsView() } label: {
                SuzzmeCard {
                    LabeledContent("Invocation", value: "Ready")
                    Text("Call Suzzme from the app, a system shortcut, or your configured Mac keyboard shortcut.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain)
            SuzzmeCard {
                LabeledContent("Privacy", value: "On device")
                Text("Suzzme uses local storage and Apple’s on-device model when it is available.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            NavigationLink { SourcesView().navigationTitle("Sources") } label: {
                Label("Explore sources", systemImage: "tray.2")
            }
            NavigationLink { HistoryView().navigationTitle("History") } label: {
                Label("View sample history", systemImage: "clock.arrow.circlepath")
            }
            #if DEBUG
            NavigationLink { SuzzmeBrainLabView() } label: {
                Label("Suzzme Brain Lab", systemImage: "brain")
            }
            #endif
            Text("Suzzme · Foundation build\nA local-first companion for your Apple devices.")
                .font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("Settings")
    }
}
