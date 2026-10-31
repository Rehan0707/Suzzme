import AVFoundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct VoiceSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    private var voice: VoiceSessionController { environment.voice }
    @AppStorage(SuzzmeHaptics.preferenceKey) private var hapticsEnabled = true
    @Environment(\.openURL) private var openURL
    @State private var settingsCouldNotOpen = false

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    SuzzmeVoicePicker()
                } label: {
                    LabeledContent("Suzzme Voice", value: selectedName)
                }
                Button(voice.isPreviewing ? "Stop Preview" : "Preview Voice", systemImage: voice.isPreviewing ? "stop.circle" : "play.circle") {
                    if voice.isPreviewing { voice.stopPreview() }
                    else { voice.previewSelectedVoice() }
                }
                .disabled(!voice.canStartSpeech)
                .frame(minHeight: 44)
                Toggle("Speak Suzzme’s responses", isOn: Binding(
                    get: { voice.speaksResponses }, set: { voice.speaksResponses = $0 }
                ))
            } header: { Text("Suzzme Voice") } footer: {
                Text(voice.voiceSelectionDescription).fixedSize(horizontal: false, vertical: true)
            }
            Section {
                LabeledContent("Speaking pace", value: paceDescription)
                Slider(value: Binding(get: { voice.speechRate }, set: { voice.speechRate = $0 }), in: VoiceSessionController.speechRateRange, step: 0.01) {
                    Text("Speaking pace")
                } minimumValueLabel: { Text("Slow") } maximumValueLabel: { Text("Fast") }
                .accessibilityValue(paceDescription)
                if abs(voice.speechRate - AVSpeechUtteranceDefaultSpeechRate) > 0.005 {
                    Button("Use natural pace") { voice.speechRate = AVSpeechUtteranceDefaultSpeechRate }
                }
            } header: { Text("Pace") } footer: {
                Text("Natural uses Apple’s default pace and pitch. Previews and spoken answers use the same settings.").fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Toggle("Match the response language", isOn: Binding(
                    get: { voice.automaticallyMatchesLanguage }, set: { voice.automaticallyMatchesLanguage = $0 }
                ))
                .disabled(!voice.usesAutomaticVoice)
            } footer: {
                Text("Automatic keeps your regional voice for your language. Other languages use an appropriate installed Apple voice. An explicit voice choice stays selected.")
            }
            Section {
                LabeledContent("Microphone", value: voice.microphonePermission.displayName)
                LabeledContent("Speech Recognition", value: voice.speechPermission.displayName)
                if voice.microphonePermission == .denied || voice.speechPermission == .denied {
                    Button("Open Privacy Settings", action: openPrivacySettings)
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                    if settingsCouldNotOpen {
                        Text("Open system Privacy settings and allow Microphone and Speech Recognition for Suzzme.")
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                }
            } header: { Text("Permissions") } footer: {
                Text("Suzzme requests access when you start a conversation. Speech is processed on this device.")
            }
            #if os(iOS)
            Section {
                Toggle("Interaction feedback", isOn: $hapticsEnabled)
                    .disabled(!SuzzmeHaptics.isSupported)
            } header: { Text("Haptics") } footer: {
                Text(SuzzmeHaptics.isSupported
                    ? "Gentle feedback marks listening, confirmations and completion. Suzzme also shows every state on screen."
                    : "Haptic feedback is available on supported iPhones. Every state is also shown on screen.")
            }
            #endif
        }
        .suzzmeSettingsForm()
        .navigationTitle("Voice")
        .onDisappear { voice.stopPreview() }
    }

    private var selectedName: String {
        let name = voice.availableVoices.first { $0.identifier == voice.selectedVoiceIdentifier }?.name ?? "Unavailable"
        return voice.usesAutomaticVoice ? "Automatic · \(name)" : name
    }
    private func openPrivacySettings() {
        #if os(iOS)
        let address = UIApplication.openSettingsURLString
        #else
        let pane = voice.microphonePermission == .denied ? "Privacy_Microphone" : "Privacy_SpeechRecognition"
        let address = "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        #endif
        guard let url = URL(string: address) else { settingsCouldNotOpen = true; return }
        openURL(url) { accepted in settingsCouldNotOpen = !accepted }
    }
    private var paceDescription: String {
        if abs(voice.speechRate - AVSpeechUtteranceDefaultSpeechRate) < 0.005 { return "Natural" }
        return voice.speechRate < AVSpeechUtteranceDefaultSpeechRate ? "Slow" : "Fast"
    }
}

private struct SuzzmeVoicePicker: View {
    @Environment(AppEnvironment.self) private var environment
    private var voice: VoiceSessionController { environment.voice }
    private var recommended: [AVSpeechSynthesisVoice] { Array(voice.availableVoices.prefix(3)) }
    private var others: [AVSpeechSynthesisVoice] { Array(voice.availableVoices.dropFirst(3)) }
    private var hasDownloadedQuality: Bool { voice.availableVoices.contains { $0.quality != .default } }
    #if DEBUG
    @State private var usesComparisonPhrase = false
    #endif

    var body: some View {
        Form {
            Section {
                Button { voice.selectAutomaticVoice() } label: {
                    HStack {
                        Text("Automatic")
                        Spacer()
                        if voice.usesAutomaticVoice { Image(systemName: "checkmark").foregroundStyle(SuzzmeTheme.intelligencePrimary) }
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(voice.usesAutomaticVoice ? "Selected" : "")
            } footer: {
                Text("Prefers installed Premium, then Enhanced, then Standard voices for your language. Preview before choosing the voice you like.").fixedSize(horizontal: false, vertical: true)
            }
            Section {
                if recommended.isEmpty {
                    Text("No compatible Apple voice is installed.")
                } else {
                    ForEach(recommended, id: \.identifier) { voiceRow($0) }
                }
                if voice.isPreviewing {
                    Button("Stop Preview", systemImage: "stop.circle") { voice.stopPreview() }.frame(minHeight: 44)
                }
            } header: { Text("Try these voices") }
            if !others.isEmpty {
                Section {
                    DisclosureGroup("More installed voices") {
                        ForEach(others, id: \.identifier) { voiceRow($0) }
                    }
                }
            }
            #if DEBUG
            Section {
                Toggle("Use the same comparison phrase", isOn: $usesComparisonPhrase)
                if usesComparisonPhrase { Text(VoiceSessionController.auditionText).font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary) }
            } header: { Text("Voice audition") } footer: {
                Text("Play each of the three voices above, then tap the name of your favorite. Playback does not change your selection.").fixedSize(horizontal: false, vertical: true)
            }
            #endif
            Section {
                if !hasDownloadedQuality {
                    Text("Only Standard voices are installed for your language. Enhanced and Premium options require an Apple voice download.")
                }
                Text(downloadGuidance).font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            } header: { Text("More voice options") }
        }
        .suzzmeSettingsForm()
        .navigationTitle("Suzzme Voice")
        .onDisappear { voice.stopPreview() }
    }

    private func voiceRow(_ installed: AVSpeechSynthesisVoice) -> some View {
        HStack(spacing: SuzzmeTheme.Spacing.medium) {
            Button { voice.selectVoice(installed) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(installed.name)
                        Text("\(installed.quality.displayTitle) · \(Locale.current.localizedString(forIdentifier: installed.language) ?? installed.language)")
                            .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                    Spacer()
                    if voice.explicitVoiceIdentifier == installed.identifier { Image(systemName: "checkmark").foregroundStyle(SuzzmeTheme.intelligencePrimary) }
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use \(installed.name), \(installed.quality.displayTitle)")
            .accessibilityValue(voice.explicitVoiceIdentifier == installed.identifier ? "Selected" : "")
            Button {
                #if DEBUG
                if usesComparisonPhrase { voice.audition(installed) }
                else { voice.preview(installed) }
                #else
                voice.preview(installed)
                #endif
            } label: { Image(systemName: "play.circle") }
            .buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
            .disabled(!voice.canStartSpeech)
            .accessibilityLabel("Preview \(installed.name)")
        }.frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }

    private var downloadGuidance: String {
        #if os(macOS)
        "In System Settings, open Accessibility → Read & Speak → System Voice → Manage Voices. On older macOS versions, look for Spoken Content. Suzzme refreshes when a voice becomes available."
        #else
        "In Settings, open Accessibility → Read & Speak → Voices. On older iOS versions, look for Spoken Content. Suzzme refreshes when a voice becomes available."
        #endif
    }
}

private extension AVSpeechSynthesisVoiceQuality {
    var displayTitle: String {
        switch self { case .premium: "Premium"; case .enhanced: "Enhanced"; default: "Standard" }
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
