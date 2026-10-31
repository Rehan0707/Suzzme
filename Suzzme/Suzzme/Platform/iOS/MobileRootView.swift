#if os(iOS)
import SwiftUI

private enum MobileTab: Hashable {
    case today, summary, settings
}

struct MobileRootView: View {
    @Environment(AppRouter.self) private var router
    @State private var selectedTab: MobileTab = .today
    @State private var todayPath: [AppDestination] = []

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $todayPath) {
                MobileCompanionTodayView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        DestinationView(destination: destination)
                            .navigationBarTitleDisplayMode(.inline)
                    }
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(MobileTab.today)

            NavigationStack { MobileCompanionSummaryView() }
                .tabItem { Label("Summary", systemImage: "text.alignleft") }
                .tag(MobileTab.summary)

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MobileTab.settings)
        }
        .tint(SuzzmeTheme.controlAccent)
        .onChange(of: router.selection) { _, destination in
            selectedTab = destination == .settings ? .settings : destination == .briefing ? .summary : .today
            if destination == .home {
                todayPath.removeAll()
            } else if destination != .settings && destination != .briefing && todayPath.last != destination {
                todayPath = [destination]
            }
        }
        .onChange(of: todayPath) { _, path in
            if selectedTab == .today {
                router.selection = path.last ?? .home
            }
        }
    }
}
#endif
