import SwiftUI
import Observation

enum AppDestination: String, CaseIterable, Identifiable {
    case home, today, briefing, memory, sources, history, settings
    #if os(macOS)
    case backgroundTasks
    #endif
    var id: Self { self }
    var title: String {
        switch self {
        case .home: "Home"
        case .today: "Today"
        case .briefing: "Daily Summary"
        case .memory: "Personal Memory"
        case .sources: "Sources"
        case .history: "History"
        case .settings: "Settings"
        #if os(macOS)
        case .backgroundTasks: "Background Tasks"
        #endif
        }
    }
    var symbol: String {
        switch self {
        case .home: "house"
        case .today: "sun.max"
        case .briefing: "text.alignleft"
        case .memory: "square.stack.3d.up"
        case .sources: "tray.2"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        #if os(macOS)
        case .backgroundTasks: "clock.arrow.circlepath"
        #endif
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
            case .today: DailyContextView()
            case .briefing:
                #if os(iOS)
                MobileCompanionSummaryView()
                #else
                BriefingView()
                #endif
            case .memory: MemoryView()
            case .sources: SourcesView()
            case .history: HistoryView()
            case .settings: SettingsView()
            #if os(macOS)
            case .backgroundTasks: BackgroundTasksView()
            #endif
            }
        }
        .navigationTitle(destination.title)
    }
}
