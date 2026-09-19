#if os(iOS)
import SwiftUI

struct MobileRootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        @Bindable var router = router
        if sizeClass == .regular {
            NavigationSplitView {
                List(AppDestination.allCases, selection: Binding<AppDestination?>(
                    get: { router.selection }, set: { router.selection = $0 ?? .home }
                )) { destination in
                    Label(destination.title, systemImage: destination.symbol).tag(destination)
                }
                .navigationTitle("Suzzme")
            } detail: {
                NavigationStack { DestinationView(destination: router.selection).navigationBarTitleDisplayMode(.inline) }
            }
        } else {
            TabView(selection: $router.selection) {
                ForEach([AppDestination.home, .briefing, .memory]) { destination in
                    NavigationStack { DestinationView(destination: destination).navigationBarTitleDisplayMode(.inline) }
                        .tabItem { Label(destination.title, systemImage: destination.symbol) }
                        .tag(destination)
                }
            }
        }
    }
}
#endif
