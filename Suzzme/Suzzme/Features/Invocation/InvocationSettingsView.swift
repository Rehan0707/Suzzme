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
                Text("Available in Shortcuts, Siri, and Spotlight. On an iPhone with an Action Button, you can assign this shortcut in the system Action Button settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Start Suzzme now") {
                    Task { _ = await environment.invokeSuzzme() }
                }
                .buttonStyle(.borderedProminent)
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
                Text("The shortcut works while Suzzme is active. It does not use Accessibility or Input Monitoring permission.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Start Suzzme now") {
                    Task { _ = await environment.invokeSuzzme() }
                }
                .buttonStyle(.borderedProminent)
            }
            #endif

            NavigationLink { VoiceSettingsView() } label: {
                Label("Voice settings", systemImage: "speaker.wave.2")
            }
        }
        .navigationTitle("Invocation")
    }
}
