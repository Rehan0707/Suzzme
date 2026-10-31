#if os(macOS)
import AppKit
import ApplicationServices
import SwiftUI

/// Permission controls for the app-owned Mac adapter; no prompt occurs at launch.
struct MacGlobalInvocationSettings: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(MacGlobalInvocationController.self) private var globalInvocation
    @State private var screenAllowed = false
    @State private var accessibilityAllowed = false

    var body: some View {
        SuzzmeCard {
            Toggle("Global Voice Shortcut", isOn: Binding(
                get: { environment.invocation.globalPushToTalkEnabled },
                set: { environment.invocation.globalPushToTalkEnabled = $0 }
            ))
            Picker("Shortcut", selection: Binding(
                get: { environment.invocation.keyboardShortcut },
                set: { environment.invocation.keyboardShortcut = $0 }
            )) {
                ForEach(SuzzmeKeyboardShortcut.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Text(environment.invocation.keyboardShortcut == .controlOption
                ? "Press Control + Option to start listening. Pause after speaking to send your words, or press the shortcut again. The answer is read aloud. Escape cancels. Speech stays on this device."
                : "Hold your selected shortcut to talk to Suzzme. Release to send. Escape cancels. Your words are processed on this device.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("On a Mac with a notch, hover over it for Talk and Hold. Click Talk to start; press and hold Hold, then release to send. These mouse controls work even when the global shortcut is off.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Global shortcut", value: globalInvocation.shortcutStatus.title)
            Text(globalInvocation.shortcutStatus.detail).font(.caption).foregroundStyle(.secondary)
            if globalInvocation.shortcutStatus == .needsPermission || globalInvocation.shortcutStatus == .unavailable {
                Text("Input Monitoring lets Suzzme observe your shortcut while another app is focused. Suzzme doesn’t record normal typing or block keystrokes.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Allow Input Monitoring") { globalInvocation.requestInputMonitoringPermission() }
                Button("Open Input Monitoring settings") { openPrivacySettings("Privacy_ListenEvent") }
            }
            LabeledContent("Microphone", value: permissionLabel(environment.voice.microphonePermission))
            LabeledContent("Speech Recognition", value: permissionLabel(environment.voice.speechPermission))
            Text("Microphone and Speech Recognition are requested when you start talking, after Suzzme explains their purpose.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Talk to Suzzme") { Task { await environment.invokeTransientVoice() } }
            if environment.voice.microphonePermission == .denied {
                Button("Open Microphone settings") { openPrivacySettings("Privacy_Microphone") }
            }
            if environment.voice.speechPermission == .denied {
                Button("Open Speech Recognition settings") { openPrivacySettings("Privacy_SpeechRecognition") }
            }
        }

        SuzzmeCard {
            Picker("Screen Awareness", selection: Binding(
                get: { environment.screenPreferences.mode },
                set: { environment.screenPreferences.mode = $0 }
            )) {
                ForEach(ScreenAwarenessMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Text("Only screen-related questions may use one current-display image. Nothing is captured in the background or saved to Memory or your Daily Summary.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Visual guidance", isOn: Binding(
                get: { environment.screenPreferences.visualGuidance },
                set: { environment.screenPreferences.visualGuidance = $0 }
            ))
            Text("Suzzme can point to a visible element. It cannot click or change anything through screen guidance.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Screen Recording", value: screenAllowed ? "Allowed" : "Needs permission")
            Text("Screen Recording allows a single capture when you approve a screen question. It isn’t needed to talk or check your day.")
                .font(.caption).foregroundStyle(.secondary)
            if !screenAllowed {
                Button("Allow Screen Recording") {
                    _ = MacScreenContextSource.requestAuthorization()
                    refreshPermissions()
                }
                Button("Open Screen Recording settings") { openPrivacySettings("Privacy_ScreenCapture") }
            }
            LabeledContent("Focused UI labels", value: accessibilityAllowed ? "Allowed" : "Optional permission")
            Text("Optional Accessibility access supplies the focused element’s role and label for screen questions. Suzzme doesn’t read field values or continuously inspect other apps.")
                .font(.caption).foregroundStyle(.secondary)
            if !accessibilityAllowed {
                Button("Allow focused UI labels") {
                    // The public AX key is a C global variable in the SDK;
                    // using its verified immutable key avoids crossing that
                    // mutable global under Swift 6 concurrency checking.
                    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                    refreshPermissions()
                }
                Button("Open Accessibility settings") { openPrivacySettings("Privacy_Accessibility") }
            }
            Button("Ask about this screen") { Task { await environment.askAboutCurrentScreen() } }
        }
        .onAppear { refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshPermissions() }
    }

    private func refreshPermissions() {
        screenAllowed = MacScreenContextSource.isAuthorized
        accessibilityAllowed = AXIsProcessTrusted()
        globalInvocation.refreshInputMonitoringPermission()
    }
    private func openPrivacySettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
    private func permissionLabel(_ permission: VoiceSessionController.Permission) -> String {
        switch permission {
        case .authorized: "Allowed"
        case .notDetermined: "Needs permission"
        case .denied: "Off"
        case .restricted: "Restricted"
        case .unavailable: "Unavailable"
        }
    }
}
#endif
