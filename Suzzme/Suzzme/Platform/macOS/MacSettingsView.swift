#if os(macOS)
import SwiftUI

/// Desktop navigation for the existing settings screens. Preferences remain
/// owned by their original controllers and persistence stores.
struct MacSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selection: MacSettingsSection = .general

    var body: some View {
        NavigationSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.large) {
                    VStack(spacing: SuzzmeTheme.Spacing.xxs) {
                        row(.profile)
                        row(.general)
                    }
                    sidebarSection("Companion") {
                        row(.voice)
                        row(.presence)
                        row(.shortcuts)
                    }
                    sidebarSection("Intelligence") {
                        row(.integrations)
                        row(.sources)
                        row(.summary)
                        row(.memory)
                    }
                    sidebarSection("Your controls") {
                        row(.privacy)
                        row(.notifications)
                        row(.accessibility)
                    }
                    row(.about)
                    #if DEBUG
                    sidebarSection("Developer") {
                        row(.brainLab)
                        row(.motionLab)
                    }
                    #endif
                }
                .padding(.horizontal, SuzzmeTheme.Spacing.xs)
                .padding(.vertical, SuzzmeTheme.Spacing.medium)
            }
            .background(.regularMaterial)
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(
                min: SuzzmeTheme.Layout.sidebarMin,
                ideal: SuzzmeTheme.Layout.sidebarIdeal,
                max: SuzzmeTheme.Layout.sidebarMax
            )
        } detail: {
            NavigationStack {
                selectedContent
                    .navigationTitle(selection.title)
            }
            // Changing categories also resets a subpage, such as the voice
            // picker, rather than leaving it above a newly selected category.
            .id(selection)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(SuzzmeTheme.controlAccent)
        .background(SuzzmeTheme.pageBackground)
        .onChange(of: environment.integrations.browserHandoff.request?.id, initial: true) { _, _ in
            if environment.integrations.browserHandoff.phase == .setup { selection = .integrations }
        }
        .onChange(of: environment.integrations.browserHandoff.phase) { _, phase in
            if phase == .setup { selection = .integrations }
        }
    }

    private func row(_ section: MacSettingsSection) -> some View {
        MacGlassSidebarRow(
            title: section.title,
            symbol: section.symbol,
            isSelected: selection == section,
            identifier: "suzzme-settings-\(section.rawValue)"
        ) { selection = section }
    }

    private func sidebarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .padding(.horizontal, SuzzmeTheme.Spacing.small)
                .padding(.bottom, SuzzmeTheme.Spacing.xxs)
            content()
        }
    }

    @ViewBuilder private var selectedContent: some View {
        switch selection {
        case .profile: ProfileSettingsView()
        case .general: MacGeneralSettingsView()
        case .voice: VoiceSettingsView()
        case .presence: PresenceSettingsView()
        case .shortcuts: InvocationSettingsView()
        case .integrations: IntegrationsView(receivesBrowserSetup: true)
        case .sources: SourcesView()
        case .summary: ProactiveIntelligenceSettingsView()
        case .memory: MemoryView()
        case .privacy: PrivacyView()
        case .notifications: SummaryNotificationsView()
        case .accessibility: CompanionAccessibilityView()
        case .about: AboutSuzzmeView()
        #if DEBUG
        case .brainLab: SuzzmeBrainLabView()
        case .motionLab: PresenceMotionLabView()
        #endif
        }
    }
}

private struct MacGeneralSettingsView: View {
    @AppStorage("suzzme.appearance") private var appearancePreference = SuzzmeAppearance.system.rawValue

    var body: some View {
        Form {
            Section {
                HStack(spacing: SuzzmeTheme.Spacing.medium) {
                    SuzzmeFace(color: SuzzmeTheme.textPrimary, lineWidth: 2.8)
                        .frame(width: SuzzmeTheme.Spacing.extraLarge, height: SuzzmeTheme.Spacing.extraLarge)
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                        Text("Make Suzzme yours").font(.headline)
                        Text("A quieter companion, ready when you need it.")
                            .font(.subheadline)
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                }
                .padding(.vertical, SuzzmeTheme.Spacing.xs)
            }
            Section {
                Picker("Appearance", selection: $appearancePreference) {
                    ForEach(SuzzmeAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
                .accessibilityIdentifier("suzzme-appearance-picker")
            } header: {
                Text("App appearance")
            } footer: {
                Text("System follows your Mac’s Light or Dark appearance. Suzzme’s color follows your companion choice in Presence appearance.")
            }
            Section {
                NavigationLink("Voice and spoken responses") { VoiceSettingsView() }
                NavigationLink("Presence appearance") { PresenceSettingsView() }
                NavigationLink("Shortcuts and controls") { InvocationSettingsView() }
            } header: {
                Text("Make it comfortable")
            }
        }
        .suzzmeSettingsForm()
    }
}

private enum MacSettingsSection: String, Identifiable {
    case profile, general, voice, presence, shortcuts, integrations, sources
    case summary, memory, privacy, notifications, accessibility, about
    #if DEBUG
    case brainLab, motionLab
    #endif

    var id: Self { self }

    var title: String {
        switch self {
        case .profile: "Profile"
        case .general: "General"
        case .voice: "Voice"
        case .presence: "Presence"
        case .shortcuts: "Shortcuts"
        case .integrations: "Integrations"
        case .sources: "Sources"
        case .summary: "Daily Summary"
        case .memory: "Personal Memory"
        case .privacy: "Privacy"
        case .notifications: "Notifications"
        case .accessibility: "Accessibility"
        case .about: "About Suzzme"
        #if DEBUG
        case .brainLab: "Brain Lab"
        case .motionLab: "Motion Lab"
        #endif
        }
    }

    var symbol: String {
        switch self {
        case .profile: "person.crop.circle"
        case .general: "gearshape"
        case .voice: "speaker.wave.2"
        case .presence: "face.smiling"
        case .shortcuts: "command"
        case .integrations: "puzzlepiece.extension"
        case .sources: "tray.2"
        case .summary: "sun.horizon"
        case .memory: "square.stack.3d.up"
        case .privacy: "lock.shield"
        case .notifications: "bell"
        case .accessibility: "accessibility"
        case .about: "info.circle"
        #if DEBUG
        case .brainLab: "brain"
        case .motionLab: "waveform.path"
        #endif
        }
    }
}

#Preview("Mac Settings") {
    MacSettingsView()
        .environment(AppEnvironment.preview)
        .frame(width: 920, height: 720)
}
#endif
