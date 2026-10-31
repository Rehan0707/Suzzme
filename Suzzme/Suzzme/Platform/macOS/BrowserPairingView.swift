#if os(macOS)
import SwiftUI

struct BrowserPairingView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedExtension = ""
    @State private var isBusy = false
    private var bridge: MacBrowserBridgeController { environment.browserBridge }
    var body: some View {
        Form {
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
        .navigationTitle("Browser pairing")
        .task { bridge.prepare(integrations: environment.integrations) }
    }
    private func run(_ operation: @escaping @MainActor () async -> Void) {
        guard !isBusy else { return }
        isBusy = true
        Task { await operation(); isBusy = false }
    }
}
#endif
