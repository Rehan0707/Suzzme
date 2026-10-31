#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct WhatsAppLocalView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var confirmsDisconnect = false
    @State private var selection: Set<String> = []
    @State private var isSaving = false

    var body: some View {
        List {
            Section {
                Text("Choose WhatsApp's shared folder on this Mac. Suzzme then reads only chats you select, summarizes recent messages with Apple Intelligence on this device, and keeps short summaries for your Daily Summary.")
                    .fixedSize(horizontal: false, vertical: true)
                Button(environment.whatsAppFolderConnected ? "Choose folder again" : "Choose WhatsApp folder") {
                    chooseFolder()
                }
                .buttonStyle(.bordered)
                Text("First link WhatsApp for Mac to your phone and let your chats sync. WhatsApp Web sign-in does not connect the local chat source.")
                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                Button("Open WhatsApp for Mac") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "net.whatsapp.WhatsApp") {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    } else { NSWorkspace.shared.open(URL(string: "https://www.whatsapp.com/download")!) }
                }
                Button("Open Full Disk Access settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderless)
            } header: { Text("Local access") } footer: {
                Text("macOS may ask you to allow folder access. If it still cannot read the database, grant Suzzme Full Disk Access in System Settings, then reopen Suzzme.")
            }

            if environment.whatsAppFolderConnected {
                Section("Choose chats") {
                    if environment.whatsAppChats.isEmpty {
                        Text("No recent text chats were found, or WhatsApp has not synced them to this Mac.")
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                    ForEach(environment.whatsAppChats) { chat in
                        Toggle(isOn: Binding(
                            get: { selection.contains(chat.id) },
                            set: { enabled in
                                if enabled { selection.insert(chat.id) }
                                else { selection.remove(chat.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                                Text(chat.name).font(.body)
                                Text("\(chat.messageCount) messages · Last active \(chat.lastMessage.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                            }
                        }
                        .disabled(!selection.contains(chat.id) && selection.count >= 20)
                    }
                    Button(isSaving ? "Saving…" : "Save selected chats") {
                        isSaving = true
                        Task {
                            await environment.setWhatsAppChats(selection)
                            isSaving = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .suzzmeProminentContrast()
                    .disabled(isSaving || selection == environment.selectedWhatsAppChats)
                    Text("Up to 20 chats. Deselecting a chat removes its saved summaries. New summaries are prepared when enabled sources refresh or your scheduled Daily Summary runs.")
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }

            if let health = environment.informationHealth.first(where: { $0.source == .whatsapp }) {
                Section("Status") {
                    Label(health.enabled ? health.state.label : "Updates off", systemImage: health.enabled ? "checkmark.circle" : "pause.circle")
                    if let last = health.lastSuccess {
                        Text("Last checked \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                }
            }
            if let error = environment.whatsAppError {
                Section { Text(error).foregroundStyle(SuzzmeTheme.textSecondary) }
            }
            if environment.whatsAppFolderConnected {
                Section {
                    Button("Disconnect WhatsApp", role: .destructive) { confirmsDisconnect = true }
                } footer: {
                    Text("Disconnecting removes the folder grant, selected chats, and local WhatsApp summaries.")
                }
            }
        }
        .suzzmeReadableList()
        .navigationTitle("WhatsApp")
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
