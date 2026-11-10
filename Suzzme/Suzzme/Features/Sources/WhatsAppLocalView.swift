#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct WhatsAppLocalView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var confirmsDisconnect = false
    @State private var selection: Set<String> = []
    @State private var isSaving = false
    @AppStorage("suzzme.whatsapp.web.enabled") private var webEnabled = false
    @State private var showingWebSyncSheet = false
    @State private var webContactName = ""
    @State private var webChatTranscript = ""
    @State private var isSyncingWeb = false
    @State private var webSyncFeedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            // MARK: - WhatsApp Web Section Card
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                HStack {
                    Image(systemName: "globe")
                        .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                    Text("WhatsApp Web")
                        .font(.headline)
                        .foregroundStyle(SuzzmeTheme.textPrimary)
                    Spacer()
                    Toggle("", isOn: $webEnabled)
                        .labelsHidden()
                        .onChange(of: webEnabled) { _, enabled in
                            Task {
                                await WhatsAppWebAccess.shared.setEnabled(enabled)
                                await environment.setInformationEnabled(.whatsapp, enabled: enabled)
                            }
                        }
                }

                Text("Pair the Suzzme browser extension, or use Direct Sync below. Visible chat messages are parsed locally on this Mac to extract actionable commitments and schedule times.")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        showingWebSyncSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down.on.square")
                            Text("Direct Web Sync / Paste Chat")
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(SuzzmeTheme.intelligencePrimary, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button("Open WhatsApp Web") {
                        if let url = URL(string: "https://web.whatsapp.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SuzzmeTheme.controlFill, in: RoundedRectangle(cornerRadius: 12))

            // MARK: - Local Mac Database Access Card
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                HStack {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                    Text("WhatsApp for Mac (Local Storage)")
                        .font(.headline)
                        .foregroundStyle(SuzzmeTheme.textPrimary)
                }

                Text("Choose WhatsApp's shared folder (`group.net.whatsapp.WhatsApp.shared`) on this Mac. Suzzme reads only chats you select, extracts commitments with on-device intelligence, and adds them to your Daily Summary.")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(environment.whatsAppFolderConnected ? "Change WhatsApp Folder" : "Connect WhatsApp Folder") {
                        chooseFolder()
                    }
                    .buttonStyle(.borderedProminent)
                    .suzzmeProminentContrast()

                    Button("Open WhatsApp for Mac") {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "net.whatsapp.WhatsApp") {
                            NSWorkspace.shared.openApplication(at: url, configuration: .init())
                        } else {
                            NSWorkspace.shared.open(URL(string: "https://www.whatsapp.com/download")!)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 2)

                Button("Open Full Disk Access Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SuzzmeTheme.controlFill, in: RoundedRectangle(cornerRadius: 12))

            // MARK: - Selected Chats Card
            if environment.whatsAppFolderConnected {
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                    Text("Selected Chats (\(selection.count)/20)")
                        .font(.headline)
                        .foregroundStyle(SuzzmeTheme.textPrimary)

                    if environment.whatsAppChats.isEmpty {
                        Text("No recent text chats were found, or WhatsApp has not synced them to this Mac.")
                            .font(.caption)
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                    } else {
                        ForEach(environment.whatsAppChats) { chat in
                            Toggle(isOn: Binding(
                                get: { selection.contains(chat.id) },
                                set: { enabled in
                                    if enabled { selection.insert(chat.id) }
                                    else { selection.remove(chat.id) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chat.name).font(.body.weight(.medium))
                                    Text("\(chat.messageCount) messages · Last active \(chat.lastMessage.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                                }
                            }
                            .disabled(!selection.contains(chat.id) && selection.count >= 20)
                        }

                        Button(isSaving ? "Saving…" : "Save Selected Chats") {
                            isSaving = true
                            Task {
                                await environment.setWhatsAppChats(selection)
                                isSaving = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving || selection == environment.selectedWhatsAppChats)
                        .padding(.top, 4)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SuzzmeTheme.controlFill, in: RoundedRectangle(cornerRadius: 12))
            }

            // MARK: - Status & Diagnostics Card
            if let health = environment.informationHealth.first(where: { $0.source == .whatsapp }) {
                HStack(spacing: 8) {
                    Image(systemName: health.enabled ? "checkmark.circle.fill" : "pause.circle.fill")
                        .foregroundStyle(health.enabled ? SuzzmeTheme.success : SuzzmeTheme.warning)
                    Text("Status: \(health.enabled ? health.state.label : "Updates Off")")
                        .font(.subheadline.weight(.medium))
                    if let last = health.lastSuccess {
                        Spacer()
                        Text("Last checked \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SuzzmeTheme.controlFill, in: RoundedRectangle(cornerRadius: 12))
            }

            if let error = environment.whatsAppError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SuzzmeTheme.warning)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(SuzzmeTheme.warning)
                }
                .padding(SuzzmeTheme.Spacing.small)
            }

            if environment.whatsAppFolderConnected {
                Button("Disconnect WhatsApp", role: .destructive) {
                    confirmsDisconnect = true
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showingWebSyncSheet) {
            webSyncSheetView
        }
        .task {
            await environment.loadWhatsAppChats()
            await environment.inspectInformation()
            selection = environment.selectedWhatsAppChats
        }
        .confirmationDialog("Disconnect WhatsApp and remove its local summaries?", isPresented: $confirmsDisconnect) {
            Button("Disconnect and remove summaries", role: .destructive) {
                Task {
                    await environment.disconnectWhatsApp()
                    selection = []
                }
            }
        }
    }

    private var webSyncSheetView: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
                Text("Sync WhatsApp Web Chat")
                    .font(.title2.weight(.semibold))

                Text("Paste or sync messages from WhatsApp Web. Suzzme extracts actionable commitments and scheduled meeting times on-device to include in your Daily Summary and Day Planner.")
                    .font(.subheadline)
                    .foregroundStyle(SuzzmeTheme.textSecondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Contact or Group Name")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                    TextField("e.g. Vaibhav, Marketing Team", text: $webContactName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Chat Messages (Format: Speaker: Message)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                        Spacer()
                        Button("Load Sample Chat") {
                            webContactName = "Vaibhav"
                            webChatTranscript = """
                            Vaibhav: Hey Rehan, can you please review the audio draft before 4 PM today?
                            You: Sure, I will check the audio and send my feedback.
                            Vaibhav: Perfect, let's also do a quick sync call at 3:30 PM.
                            """
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }

                    TextEditor(text: $webChatTranscript)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 140)
                        .padding(4)
                        .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SuzzmeTheme.separator, lineWidth: 1))
                }

                if let feedback = webSyncFeedback {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(SuzzmeTheme.success)
                        Text(feedback)
                            .font(.subheadline)
                            .foregroundStyle(SuzzmeTheme.success)
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    Button("Cancel") {
                        showingWebSyncSheet = false
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        isSyncingWeb = true
                        Task {
                            let name = webContactName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let text = webChatTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                            let success = await environment.syncWhatsAppWebChat(
                                name: name.isEmpty ? "WhatsApp Chat" : name,
                                text: text
                            )
                            isSyncingWeb = false
                            if success {
                                webSyncFeedback = "Synced into Daily Summary & Day Planner!"
                                try? await Task.sleep(for: .seconds(1))
                                showingWebSyncSheet = false
                                webSyncFeedback = nil
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isSyncingWeb { ProgressView().controlSize(.small) }
                            Text(isSyncingWeb ? "Analyzing & Syncing…" : "Sync to Daily Summary")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(SuzzmeTheme.intelligencePrimary, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSyncingWeb || webChatTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(SuzzmeTheme.Spacing.large)
            .frame(minWidth: 480, minHeight: 400)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared", isDirectory: true)
        panel.message = "Choose WhatsApp’s shared folder to select the chats Suzzme can read."
        panel.prompt = "Connect folder"
        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return }
            Task { @MainActor in
                await environment.connectWhatsApp(folder: folder)
                selection = environment.selectedWhatsAppChats
            }
        }
    }
}
#endif
