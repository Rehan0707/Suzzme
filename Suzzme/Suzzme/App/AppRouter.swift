import SwiftUI
import Observation

enum AppDestination: String, CaseIterable, Identifiable {
    case home, briefing, memory, sources, history, settings
    var id: Self { self }
    var title: String {
        switch self {
        case .home: "Today"
        case .briefing: "Briefing"
        case .memory: "Memory"
        case .sources: "Sources"
        case .history: "History"
        case .settings: "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .home: "sun.max"
        case .briefing: "text.alignleft"
        case .memory: "square.stack.3d.up"
        case .sources: "tray.2"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

@MainActor @Observable
final class AppRouter {
    var selection: AppDestination = .home
}

struct DestinationView: View {
    let destination: AppDestination
    var body: some View {
        Group {
            switch destination {
            case .home: HomeView()
            case .briefing: BriefingView()
            case .memory: MemoryView()
            case .sources: SourcesView()
            case .history: HistoryView()
            case .settings: SettingsView()
            }
        }
        .navigationTitle(destination.title)
    }
}
