import SwiftUI

struct ProfileSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage("suzzme.profile.name") private var profileName = "Rehan"
    @State private var draftName = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draftName)
                    .textContentType(.name)
                    .onSubmit(save)
                Button("Save Name", action: save).disabled(trimmedName.isEmpty)
            } header: { Text("Your profile") } footer: {
                Text("Your name is stored on this device and used for Suzzme’s greeting.")
            }
            if saved { Section { Label("Saved on this device", systemImage: "checkmark.circle.fill").foregroundStyle(SuzzmeTheme.success) } }
            Section {
                LabeledContent("Sign in with Apple", value: "Unavailable")
            } header: { Text("Account sync") } footer: {
                Text("This build does not create an account or sync personal information.")
            }
        }
        .navigationTitle("Profile")
        .onAppear { draftName = profileName }
    }

    private var trimmedName: String { draftName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func save() {
        guard !trimmedName.isEmpty else { return }
        profileName = trimmedName
        draftName = trimmedName
        environment.updateProfileName(trimmedName)
        saved = true
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("On-device intelligence") {
                Label("Suzzme processes locally when the device supports it.", systemImage: "iphone")
                Label("No external AI service is required.", systemImage: "network.slash")
            }
            Section {
                NavigationLink { MemoryView() } label: { Label("Personal Memory", systemImage: "square.stack.3d.up") }
                NavigationLink { SourcesView().navigationTitle("Sources") } label: { Label("Sources and Permissions", systemImage: "hand.raised") }
                NavigationLink { InformationInspectionView() } label: { Label("Recent Information", systemImage: "clock.arrow.circlepath") }
                Text("Clearing recent information does not delete source items or Personal Memory. Memory controls do not change Calendar, Contacts, or Reminders.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } header: { Text("Your controls") }
        }
        .navigationTitle("Privacy")
    }
}

struct AboutSuzzmeView: View {
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }

    var body: some View {
        List {
            Section {
                VStack(spacing: SuzzmeTheme.Spacing.medium) {
                    SuzzmeMark().frame(width: 80, height: 80)
                    Text("Suzzme").font(.title.weight(.semibold))
                    Text("A local-first companion for your Apple devices.")
                        .foregroundStyle(SuzzmeTheme.textSecondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SuzzmeTheme.Spacing.large)
            }
            Section("Version") {
                LabeledContent("Suzzme", value: version)
                LabeledContent("Build", value: build)
            }
            Section("Principles") {
                Label("Private by design", systemImage: "lock.shield")
                Label("On-device first", systemImage: "iphone")
                Label("Actions require your approval", systemImage: "checkmark.shield")
            }
        }
        .navigationTitle("About Suzzme")
    }
}
