import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct GmailConnectionView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selectionMode: GmailSelection.Mode = .recentInbox
    @State private var enablingSummariesAfterAuthorization = false
    @State private var modelCapability: IntelligenceCapability?

    private var account: GmailAccountController { environment.gmailAccount }

    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.medium) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.title3).foregroundStyle(SuzzmeTheme.textSecondary).frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                    Text("Gmail").font(.headline)
                    Text("Connect to include recent inbox information in your answers and Daily Summary. Header access reads sender, subject, and date. You can separately allow read-only message access for short on-device summaries. Suzzme does not download attachments or change mail.")
                        .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if account.isConnected, let email = account.emailAddress {
                Label("Connected as \(email)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(SuzzmeTheme.success)
                Picker("Selected mail", selection: $selectionMode) {
                    ForEach(GmailSelection.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Button(account.gmailSelection()?.includeBodies == true ? "Update selected inbox" : "Use selected headers") {
                    saveSelection(includeBodies: account.gmailSelection()?.includeBodies == true)
                }
                if account.hasBodyAccess {
                    if account.gmailSelection()?.includeBodies == true {
                        Label("On-device email summaries enabled", systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(SuzzmeTheme.success)
                        Button("Use headers only") { saveSelection(includeBodies: false) }
                    } else {
                        Button("Use on-device email summaries") { saveSelection(includeBodies: true) }
                            .buttonStyle(.borderedProminent)
                            .suzzmeProminentContrast()
                    }
                } else {
                    Button("Allow read-only message access") { requestBodyAccess() }
                        .disabled(account.isConnecting)
                }
                if let capability = modelCapability, !capability.usesFoundationModels,
                   account.gmailSelection()?.includeBodies == true {
                    Label(capability.displayDescription, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(SuzzmeTheme.warning)
                }
                Text("With message access, Suzzme summarizes up to 12 recent emails per refresh on this device, then keeps only short summaries locally. Headers can be browsed in Suzzme. Daily Summary includes only important messages identified from permitted bodies by Apple’s on-device model. When the model is unavailable, those messages cannot be included. Email bodies and attachments are not stored in Suzzme or Supabase. Google may require app verification before this permission works for all accounts.")
                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                InformationSourceControls(source: .gmail, canEnable: account.gmailSelection() != nil)
                Button("Disconnect Google account", role: .destructive) {
                    Task { await environment.disconnectGmail() }
                }
                .disabled(account.isConnecting)
            } else {
                Button("Connect Gmail with Google", action: connect)
                .buttonStyle(.borderedProminent)
                .suzzmeProminentContrast()
                .controlSize(.large)
                .disabled(!account.isConfigured || account.isConnecting)
                if account.isConnecting {
                    ProgressView("Connecting Gmail…")
                }

                if !account.isConfigured {
                    Text("Gmail isn’t available in this build. You can still use the sources connected on this device.")
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                } else {
                    InformationSourceControls(source: .gmail, canEnable: false)
                }
            }

            Label("Connected service · Uses Google’s network", systemImage: "network")
                .font(.caption)
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let message = account.errorMessage {
                Text(message).font(.caption).foregroundStyle(SuzzmeTheme.warning)
            }
        }
        .padding(.vertical, SuzzmeTheme.Spacing.xs)
        .task { @MainActor in
            if let selected = await account.gmailSelection() { selectionMode = selected.mode }
            modelCapability = await environment.intelligenceCapability()
        }
        .onChange(of: account.hasBodyAccess) { _, allowed in
            guard allowed, enablingSummariesAfterAuthorization else { return }
            enablingSummariesAfterAuthorization = false
            saveSelection(includeBodies: true)
        }
        .onChange(of: account.isConnecting) { _, connecting in
            if !connecting && !account.hasBodyAccess { enablingSummariesAfterAuthorization = false }
        }

    }

    private func connect() {
        #if os(iOS)
        guard let viewController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController else { return }
        account.connect(presenting: viewController)
        #elseif os(macOS)
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) else {
            account.reportPresentationUnavailable()
            return
        }
        account.connect(presenting: window)
        #endif
    }

    private func requestBodyAccess() {
        enablingSummariesAfterAuthorization = true
        #if os(iOS)
        guard let viewController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController else { return }
        account.requestBodyAccess(presenting: viewController)
        #elseif os(macOS)
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) else {
            account.reportPresentationUnavailable()
            return
        }
        account.requestBodyAccess(presenting: window)
        #endif
    }

    private func saveSelection(includeBodies: Bool) {
        guard let id = account.googleAccountIdentifier,
              !includeBodies || account.hasBodyAccess else { return }
        let retired = account.gmailSelection().map { GmailAccessGrant.namespace(for: id) + $0.prefix }
        do { try GmailSelectionStore.save(mode: selectionMode, includeBodies: includeBodies, accountID: id) }
        catch { return }
        Task { await environment.gmailSelectionChanged(retiredPrefix: retired) }
    }
}
