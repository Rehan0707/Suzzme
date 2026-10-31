import SwiftUI
import FirebaseCore

@main
struct SuzzmeApp: App {
    @AppStorage("suzzme.appearance") private var appearancePreference = SuzzmeAppearance.system.rawValue
    @State private var startup: SuzzmeAppStartup
    #if os(iOS)
    @UIApplicationDelegateAdaptor(CompanionApplicationDelegate.self) private var companionDelegate
    // In App, this is the aggregate phase of every window, rather than a
    // particular window's phase.
    @Environment(\.scenePhase) private var applicationPhase
    #endif
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppLifetime.self) private var appLifetime
    #endif

    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        let startup = SuzzmeAppStartup()
        _startup = State(initialValue: startup)
        #if os(macOS)
        MacAppLifetime.startup = startup
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        // One main scene; the delegate and menu bar preserve app lifetime.
        Window("Suzzme", id: "main") {
            SuzzmeStartupRoot(startup: startup)
                .preferredColorScheme(selectedAppearance.colorScheme)
        }
        .defaultSize(width: 1080, height: 820)
        .commands {
            if let runtime = startup.runtime {
                MacCompanionCommands(environment: runtime.environment, showCompanion: { runtime.companionMenu.show() })
            }
            #if DEBUG
            ApprovedDesignGalleryCommands()
            #endif
        }
        #if DEBUG
        Window("Approved Design Gallery", id: "approved-design-gallery") {
            NavigationStack {
                ApprovedDesignGalleryView()
            }
            .tint(SuzzmeTheme.accent)
        }
        .defaultSize(width: 1280, height: 820)
        #endif
        Settings {
            Group {
                if let runtime = startup.runtime {
                    SettingsView()
                        .environment(runtime.environment)
                        .environment(runtime.globalInvocation)
                        .environment(runtime.launchAtLogin)
                        .tint(SuzzmeTheme.accent)
                } else {
                    SuzzmeStartupRoot(startup: startup)
                }
            }
                .preferredColorScheme(selectedAppearance.colorScheme)
                .frame(minWidth: 760, idealWidth: 920, minHeight: 600, idealHeight: 720)
        }
        #else
        WindowGroup {
            SuzzmeStartupRoot(startup: startup)
                .preferredColorScheme(selectedAppearance.colorScheme)
                .environment(\.suzzmeApplicationPhase, applicationPhase)
        }
        .onChange(of: applicationPhase, initial: true) { _, phase in
            startup.updateApplicationPhase(to: phase)
        }
        #endif
    }

    private var selectedAppearance: SuzzmeAppearance {
        SuzzmeAppearance(rawValue: appearancePreference) ?? .system
    }
}
