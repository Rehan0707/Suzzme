import SwiftUI
import AVFoundation

struct VoiceSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        SuzzmePage {
            SuzzmeCard {
                Toggle("Speak voice responses", isOn: Binding(get: { environment.voice.speaksResponses }, set: { environment.voice.speaksResponses = $0 }))
                Text("Voice requests can receive calm spoken answers. Typed requests stay silent.").font(.subheadline).foregroundStyle(.secondary)
            }
            SuzzmeSectionHeader(title: "Suzzme voice")
            if environment.voice.availableVoices.isEmpty {
                Text("No suitable system voices are available.").foregroundStyle(.secondary)
            } else {
                ForEach(environment.voice.availableVoices, id: \.identifier) { voice in
                    HStack {
                        VStack(alignment: .leading) { Text(voice.name); Text(voice.language).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Preview") { environment.voice.preview(voice) }.buttonStyle(.bordered)
                        Button("Use") { environment.voice.selectVoice(voice) }.buttonStyle(.bordered)
                    }.padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Voice")
        .onDisappear { environment.voice.stopSpeech() }
    }
}
