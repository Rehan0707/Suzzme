import AVFoundation
import SwiftUI

struct VoiceSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        List {
            Section {
                Toggle("Speak Suzzme’s responses", isOn: Binding(
                    get: { environment.voice.speaksResponses },
                    set: { environment.voice.speaksResponses = $0 }
                ))
            } header: { Text("Speech") } footer: {
                Text("Voice requests can receive spoken answers. Typed requests stay silent.")
            }

            Section("Voice") {
                if environment.voice.availableVoices.isEmpty {
                    SuzzmeEmptyState(symbol: "speaker.slash", title: "No voice is available", message: "Install a compatible system voice in Accessibility settings, then return here.")
                } else {
                    ForEach(environment.voice.availableVoices, id: \.identifier) { voice in
                        HStack(spacing: SuzzmeTheme.Spacing.medium) {
                            Button { environment.voice.selectVoice(voice) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(voice.name)
                                        Text(Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language)
                                            .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                                    }
                                    Spacer()
                                    if environment.voice.selectedVoiceIdentifier == voice.identifier {
                                        Image(systemName: "checkmark").foregroundStyle(SuzzmeTheme.intelligencePrimary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Use \(voice.name)")

                            Button { environment.voice.preview(voice) } label: { Image(systemName: "play.circle") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Preview \(voice.name)")
                        }
                        .frame(minHeight: 44)
                    }
                }
            }

            Section {
                LabeledContent("Microphone", value: environment.voice.microphonePermission.displayName)
                LabeledContent("Speech Recognition", value: environment.voice.speechPermission.displayName)
            } header: { Text("Permissions") } footer: {
                Text("Suzzme requests access only when you start a voice conversation.")
            }
        }
        .navigationTitle("Voice")
        .onDisappear { environment.voice.stopSpeech() }
    }
}

private extension VoiceSessionController.Permission {
    var displayName: String {
        switch self {
        case .notDetermined: "Not Requested"
        case .authorized: "Allowed"
        case .denied: "Off"
        case .restricted: "Restricted"
        case .unavailable: "Unavailable"
        }
    }
}
