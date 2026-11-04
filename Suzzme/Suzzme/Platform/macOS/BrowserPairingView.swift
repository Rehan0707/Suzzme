#if os(macOS)
import SwiftUI

struct BrowserPairingView: View {
    @Environment(MacGlobalInvocationController.self) private var invocation
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedExtension = ""
    @State private var isBusy = false
    private var bridge: MacBrowserBridgeController { environment.browserBridge }
    var body: some View {
        Form {
            Section("Native browser detection") {
                Toggle("Suggest connections from active browser tabs", isOn: Binding(
                    get: { invocation.browserDiscovery.enabled },
                    set: { invocation.browserDiscovery.setEnabled($0) }))
                Text("Safari, Chrome, Brave, Edge and Arc. Requires Accessibility permission. Suzzme observes window and tab events and reads only the document URL, including in private windows if the browser exposes it. It discards the path after recognizing the app. Disable this switch to stop detection.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                Text(invocation.browserDiscovery.status).font(.footnote)
                Button("Check Access") { invocation.browserDiscovery.refresh() }
                Button("Open Accessibility Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
                }
                Button("Reset dismissed app suggestions") { environment.integrations.resetBrowserSuggestions() }
                    .help("Allows previously declined or snoozed apps to offer setup again.")
            }

            Section("Automatic connection suggestions") {
                Text("Open Gmail, Outlook, GitHub, Notion, Slack, LinkedIn or WhatsApp in Chrome. When paired, Suzzme can offer a connection from its notch panel using only the active tab’s app name.")
                Text("Setup: install the Suzzme App Connections extension, enable and pair the helper below, then turn on Automatic tab prompts in the extension. No declines an app for 30 days; Not now snoozes it for an hour, including after restarting Suzzme. Connect opens setup without granting account access.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            Section("Chrome on this Mac") {
                Text(bridge.status).foregroundStyle(SuzzmeTheme.textSecondary)
                Text("Pairing lets this Chrome extension send a supported app name or GitHub repository slug to Suzzme. Active-tab prompts are off until you enable them and grant the listed site permissions in the extension. It cannot read page content, provider accounts, or authorize connections. Safari is not supported by this extension.")
                if !bridge.allowedExtensions.isEmpty {
                    Picker("Installed extension", selection: $selectedExtension) {
                        Text("Choose extension").tag("")
                        ForEach(bridge.allowedExtensions, id: \.self) { Text($0).tag($0) }
                    }
                    Button("Enable browser helper") { run { await bridge.enable() } }
                        .disabled(isBusy || bridge.isReady)
                    Button("Approve pairing for two minutes") { run { await bridge.approve(extensionID: selectedExtension) } }
                        .disabled(isBusy || !bridge.isReady || selectedExtension.isEmpty)
                } else {
                    Text("A signed build needs the real Chrome extension ID and provisioned macOS App Group. No pairing or installation is active in this build.")
                        .font(.footnote)
                }
            }
            if let code = bridge.pairingCode {
                Section("Enter only in your extension’s pairing form") {
                    SecureField("One-use pairing code", text: .constant(code)).textFieldStyle(.roundedBorder)
                    Button("Copy pairing code") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string)
                    }
                    Text("Expires after two minutes. Do not share this code. Browser credentials stay in extension-private storage; the app stores pairings in Keychain.").font(.footnote)
                }
            }
            Section("Safari and the Share menu") {
                Text("The separate Suzme Share extension accepts one URL you explicitly share. It does not inspect Safari tabs or page contents. Return to Sources → Shared webpages to review it. A signed build and shared-container setup are required.")
                NavigationLink("Review shared webpages") { SharedWebPagesView() }
            }
            Section {
                Button("Revoke all browser pairings", role: .destructive) { run { await bridge.revoke() } }
                    .disabled(isBusy || bridge.allowedExtensions.isEmpty)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Browser suggestions")
        .task { bridge.prepare(integrations: environment.integrations) }
    }
    private func run(_ operation: @escaping @MainActor () async -> Void) {
        guard !isBusy else { return }
        isBusy = true
        Task { await operation(); isBusy = false }
    }
}
#endif
