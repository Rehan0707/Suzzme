import SwiftUI

struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showsCompanion = false
    var body: some View {
        SuzzmePage {
            SuzzmeHalo(state: environment.presenceState)
            if let briefing = environment.briefing {
                SuzzmeGreeting(greeting: briefing.greeting, count: briefing.attentionCount)
                Label("A sample day, thoughtfully arranged", systemImage: "sparkle")
                    .font(.caption).foregroundStyle(.secondary)
                if let important = briefing.importantItems.first {
                    VStack(alignment: .leading, spacing: 14) {
                        SuzzmeSectionHeader(title: "Most important")
                        NavigationLink {
                            ItemDetailView(item: important)
                        } label: {
                            SuzzmeCard(highlighted: true) {
                                HStack {
                                    SuzzmePriorityBadge(priority: important.priority)
                                    Spacer()
                                    Image(systemName: "arrow.up.right").accessibilityHidden(true)
                                }
                                Text(important.title).font(.title2.weight(.semibold))
                                Text(important.summary).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Label("Take a closer look", systemImage: "arrow.right").font(.subheadline.weight(.medium))
                                    .foregroundStyle(SuzzmeTheme.accent)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    SuzzmeSectionHeader(title: "On today’s horizon")
                    ForEach(briefing.upcomingItems.prefix(3)) { item in
                        NavigationLink { ItemDetailView(item: item) } label: {
                            SuzzmeItemRow(item: item, showTime: true)
                        }.buttonStyle(.plain)
                    }
                }
                if let item = briefing.carriedOverItems.first {
                    VStack(alignment: .leading, spacing: 14) {
                        SuzzmeSectionHeader(title: "From yesterday")
                        NavigationLink { ItemDetailView(item: item) } label: {
                            SuzzmeCard { SuzzmeItemRow(item: item) }
                        }.buttonStyle(.plain)
                    }
                }
                NavigationLink {
                    HistoryView().navigationTitle("Activity")
                } label: {
                    Label("View activity", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SuzzmeTheme.accent)
                }
                Button {
                    Task { _ = await environment.invokeSuzzme() }
                } label: {
                    Label("Talk to Suzzme", systemImage: "mic.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Starts a voice conversation with Suzzme")
                Button { showsCompanion = true } label: {
                    HStack(spacing: 14) {
                        SuzzmeMark().frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("A little room to think").font(.headline)
                            Text("Meet your future companion").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Text("Demo information · Nothing connected · Everything stays here")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let message = environment.errorMessage {
                SuzzmeEmptyState(symbol: "sun.max", title: "A moment to regroup", message: message)
                Button("Try again") { Task { await environment.loadIfNeeded() } }
            } else {
                ProgressView("Arranging your day…").frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showsCompanion) {
            AskSuzzmeView().frame(minWidth: 300, minHeight: 350)
        }
        #if DEBUG && os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Developer settings")
            }
        }
        #endif
    }
}

#Preview("Home · Light") {
    NavigationStack { HomeView() }.environment(AppEnvironment.preview).preferredColorScheme(.light)
}
#Preview("Home · Dark") {
    NavigationStack { HomeView() }.environment(AppEnvironment.preview).preferredColorScheme(.dark)
}
#Preview("Home · Accessible type") {
    NavigationStack { HomeView() }.environment(AppEnvironment.preview).environment(\.dynamicTypeSize, .accessibility3)
}
