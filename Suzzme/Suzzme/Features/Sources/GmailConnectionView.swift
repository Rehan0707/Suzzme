import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Native on-device Google & Gmail connection view.
/// Connects directly using Google Sign-In with OAuth 2.0 and Keychain token storage,
/// zero server proxies, and on-device privacy.
struct GmailConnectionView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var mode: GmailSelection.Mode = .recentInbox
    @State private var includeBodies = false
    @State private var isSyncing = false
    @State private var syncStatus: String?

    private var account: GmailAccountController { environment.gmailAccount }

    var body: some View {
        List {
            headerSection
            connectionSection

            if account.isConnected {
                inboxSettingsSection
                syncSection
            }

            privacySection
        }
        .suzzmeReadableList()
        .navigationTitle("Gmail")
        .task {
            await environment.restoreGmailSignIn()
            if let selection = await account.gmailSelection() {
                mode = selection.mode
                includeBodies = selection.includeBodies
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                HStack(spacing: SuzzmeTheme.Spacing.medium) {
                    Image("Integration-gmail")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.control, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gmail")
                            .font(.title2.weight(.bold))
                        Text("Direct on-device Google sync")
                            .font(.caption)
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                }

                Text("Connect your Google account directly from this Mac. Suzzme indexes recent or unread emails to summarize your day and highlight important updates.")
                    .font(.subheadline)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
            }
            .padding(.vertical, SuzzmeTheme.Spacing.xs)
        }
    }

    private var connectionSection: some View {
        Section("Google Account") {
            if account.isConnected {
                HStack {
                    Label(account.emailAddress ?? "Google Account", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(SuzzmeTheme.success)
                    Spacer()
                    Text("Connected")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SuzzmeTheme.success)
                }

                HStack {
                    Text("Header Access")
                    Spacer()
                    Text(account.hasMetadataAccess ? "Read-only" : "None")
                        .font(.caption)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                }

                HStack {
                    Text("Body Summaries")
                    Spacer()
                    Text(account.hasBodyAccess ? "Allowed" : "Off")
                        .font(.caption)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                }

                Button(role: .destructive) {
                    Task {
                        await environment.disconnectGmail()
                    }
                } label: {
                    Label("Disconnect Google Account", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                    Text("Sign in with Google to grant read-only access to your inbox metadata.")
                        .font(.subheadline)
                        .foregroundStyle(SuzzmeTheme.textSecondary)

                    if let error = account.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(SuzzmeTheme.warning)
                    }

                    Button {
                        connectGoogle()
                    } label: {
                        HStack {
                            if account.isConnecting {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                            } else {
                                Image(systemName: "person.badge.key.fill")
                            }
                            Text(account.isConnecting ? "Connecting to Google…" : "Connect with Google")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SuzzmeTheme.intelligencePrimary)
                    .disabled(account.isConnecting || !account.isConfigured)
                }
                .padding(.vertical, SuzzmeTheme.Spacing.xs)
            }
        }
    }

    private var inboxSettingsSection: some View {
        Section("Inbox Intake Settings") {
            Picker("Intake Mode", selection: $mode) {
                ForEach(GmailSelection.Mode.allCases, id: \.self) { m in
                    Text(m.title).tag(m)
                }
            }
            .onChange(of: mode) { _, newMode in
                saveSelection(mode: newMode, bodies: includeBodies)
            }

            Toggle("Summarize message bodies with on-device AI", isOn: $includeBodies)
                .onChange(of: includeBodies) { _, newBodies in
                    if newBodies && !account.hasBodyAccess {
                        requestBodyAccess()
                    } else {
                        saveSelection(mode: mode, bodies: newBodies)
                    }
                }
        }
    }

    private var syncSection: some View {
        Section("Sync") {
            Button {
                triggerSync()
            } label: {
                HStack {
                    if isSyncing {
                        ProgressView().controlSize(.small).padding(.trailing, 4)
                    }
                    Text(isSyncing ? "Checking Gmail…" : "Check Gmail Now")
                }
            }
            .disabled(isSyncing)

            if let syncStatus {
                Text(syncStatus)
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
            }
        }
    }

    private var privacySection: some View {
        Section("Privacy & Security") {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                Label("Zero Server Proxy", systemImage: "lock.shield.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                Text("Your Google OAuth tokens remain strictly inside your device's Keychain. All queries connect directly from this device to Google's servers. Raw emails are never forwarded or shared with third parties.")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Actions

    private func connectGoogle() {
        #if os(macOS)
        if let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? NSApplication.shared.windows.first {
            account.connect(presenting: window)
        }
        #elseif os(iOS)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            account.connect(presenting: root)
        }
        #endif
    }

    private func requestBodyAccess() {
        #if os(macOS)
        if let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? NSApplication.shared.windows.first {
            account.requestBodyAccess(presenting: window)
        }
        #elseif os(iOS)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            account.requestBodyAccess(presenting: root)
        }
        #endif
    }

    private func saveSelection(mode: GmailSelection.Mode, bodies: Bool) {
        guard let accountID = account.googleAccountIdentifier else { return }
        do {
            try GmailSelectionStore.save(mode: mode, includeBodies: bodies, accountID: accountID)
            Task {
                await environment.gmailSelectionChanged(retiredPrefix: nil)
            }
        } catch {
            syncStatus = "Failed to save selection."
        }
    }

    private func triggerSync() {
        guard !isSyncing else { return }
        isSyncing = true
        syncStatus = "Checking inbox messages…"
        Task {
            do {
                await environment.refreshInformation(force: true, source: .gmail)
                syncStatus = "Inbox checked successfully at \(Date.now.formatted(date: .omitted, time: .shortened))."
            }
            isSyncing = false
        }
    }
}
