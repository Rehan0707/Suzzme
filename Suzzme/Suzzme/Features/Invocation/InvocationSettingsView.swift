import SwiftUI

struct InvocationSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        SuzzmePage {
            SuzzmeScreenIntroduction(title: "Ready when you are", message: "Suzzme starts listening only when you invoke it. Your conversation stays on this device.")

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
            MacGlobalInvocationSettings()
            SuzzmeCard {
                Text("Move the pointer to the Mac notch to reveal Talk and Hold. Click Talk to start a voice conversation, or press and hold Hold while speaking, then release to send. The quiet surface hides after three seconds; active conversations and confirmations stay visible.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Start Suzzme now") {
                    Task { await environment.invokeTransientVoice() }
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
