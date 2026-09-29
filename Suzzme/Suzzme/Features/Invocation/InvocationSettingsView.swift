import SwiftUI

struct InvocationSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        SuzzmePage {
            SuzzmeCard {
                Label("Call Suzzme", systemImage: "mic.fill")
                    .font(.headline)
                Text("Suzzme starts listening only when you invoke it. Your conversation stays on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            #if os(iOS)
            SuzzmeSectionHeader(title: "iPhone")
            SuzzmeCard {
                Label("Talk to Suzzme", systemImage: "app.badge")
                    .font(.headline)
                Text("In iPhone Settings, open Action Button, choose Shortcut, then select Talk to Suzzme. Press and hold the Action button to start a conversation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Start Suzzme now") {
                    Task { _ = await environment.invokeSuzzme() }
                }
                .buttonStyle(.borderedProminent)
                    .suzzmeProminentContrast()
                .accessibilityHint("Starts a Suzzme voice conversation")
            }
            #else
            SuzzmeSectionHeader(title: "Mac")
            SuzzmeCard {
                Picker("Keyboard shortcut", selection: Binding(
                    get: { environment.invocation.keyboardShortcut },
                    set: { environment.invocation.keyboardShortcut = $0 }
                )) {
                    ForEach(SuzzmeKeyboardShortcut.allCases, id: \.self) { shortcut in
                        Text(shortcut.title).tag(shortcut)
                    }
                }
                Text("Talk to Suzzme from anywhere on your Mac. Listening begins only when you use the shortcut.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("The notch surface hides after eight quiet seconds. Move the pointer away and back to the notch to reveal it, or use your shortcut or Talk to Suzzme. Active conversations and confirmations stay visible.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Start Suzzme now") {
                    Task { _ = await environment.invokeSuzzme() }
                }
                .buttonStyle(.borderedProminent)
                    .suzzmeProminentContrast()
            }
            #endif

            NavigationLink { VoiceSettingsView() } label: {
                Label("Voice settings", systemImage: "speaker.wave.2")
            }
        }
        .navigationTitle("Talk to Suzzme")
    }
}
