import SwiftUI
import SwiftData

@main
struct SuzzmeApp: App {
    @State private var environment: AppEnvironment

    init() {
        let container = try? ModelContainer(for: StoredSuzzmeItem.self, StoredSuzzmeMemory.self, StoredSuzzmeMemoryRelationship.self)
        let store = container.map { SuzzmeItemStore(container: $0) }
        let informationContainer = try? InformationPersistence.makeContainer()
        let proactiveStore = ProactiveIntelligenceStore(fileURL: ProactiveIntelligenceStore.defaultURL())
        _environment = State(initialValue: AppEnvironment(itemStore: store, memoryStore: container.map { LongTermMemoryStore(modelContainer: $0) },
            informationStore: informationContainer.map { InformationStore(modelContainer: $0) }, proactiveStore: proactiveStore))
    }
    var body: some Scene {
        #if os(macOS)
        Window("Suzzme", id: "main") {
            ContentView()
                .environment(environment)
                .tint(SuzzmeTheme.accent)
        }
        .defaultSize(width: 1080, height: 820)
        Settings {
            NavigationStack { SettingsView() }
                .environment(environment)
                .tint(SuzzmeTheme.accent)
                .frame(width: 520, height: 680)
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
