import SwiftUI
import SwiftData

@main
struct SuzzmeApp: App {
    @State private var environment: AppEnvironment

    init() {
        let container = try? ModelContainer(for: StoredSuzzmeItem.self, StoredSuzzmeMemory.self, StoredSuzzmeMemoryRelationship.self)
        let store = container.map { SuzzmeItemStore(container: $0) }
        _environment = State(initialValue: AppEnvironment(itemStore: store, memoryStore: container.map { LongTermMemoryStore(modelContainer: $0) }))
    }
    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView()
                .environment(environment)
                .tint(SuzzmeTheme.accent)
        }
        .defaultSize(width: 1080, height: 820)
        Settings {
            NavigationStack { SettingsView() }
                .environment(environment)
                .tint(SuzzmeTheme.accent)
                .frame(width: 480, height: 560)
        }
        #else
        WindowGroup {
            ContentView()
                .environment(environment)
                .tint(SuzzmeTheme.accent)
        }
        #endif
    }
}
