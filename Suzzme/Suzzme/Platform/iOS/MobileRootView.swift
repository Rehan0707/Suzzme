#if os(iOS)
import SwiftUI

struct MobileRootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    private let primaryDestinations: [AppDestination] = [.home, .briefing, .memory]

    var body: some View {
        @Bindable var router = router

        if sizeClass == .regular {
            NavigationSplitView {
                List(primaryDestinations, selection: Binding<AppDestination?>(
                    get: { router.selection },
                    set: { router.selection = $0 ?? .home }
                )) { destination in
                    Label(destination.title, systemImage: destination.symbol)
                        .tag(destination)
                }
                .navigationTitle("Suzzme")
                .safeAreaInset(edge: .top) {
                    sidebarBrand
                }
                .safeAreaInset(edge: .bottom) {
                    NavigationLink { SettingsView() } label: {
                        Label("Settings", systemImage: "gearshape")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .buttonStyle(.plain)
                    .background(.bar)
                }
            } detail: {
                NavigationStack {
                    DestinationView(destination: router.selection)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        } else {
            TabView(selection: $router.selection) {
                ForEach(primaryDestinations) { destination in
                    NavigationStack {
                        DestinationView(destination: destination)
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .tabItem {
                        Label(destination.title, systemImage: destination.symbol)
                    }
                    .tag(destination)
                }
            }
        }
    }

    private var sidebarBrand: some View {
        HStack(spacing: 12) {
            SuzzmeMark().frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Suzzme").font(.headline)
                Text("Your calm companion")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
#endif
