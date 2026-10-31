import SwiftUI

struct HistoryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var searchText = ""

    private var savedItems: [SuzzmeItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return environment.activityItems.filter {
            query.isEmpty || $0.title.localizedStandardContains(query) || $0.summary.localizedStandardContains(query)
        }
    }

    var body: some View {
        SuzzmePage {
            SuzzmeScreenIntroduction(title: "Saved with Suzzme", message: "Structured information you chose to keep, stored on this device.")
            if environment.activityItems.isEmpty {
                SuzzmeEmptyState(symbol: "clock.arrow.circlepath", title: "Nothing saved yet", message: "Ask Suzzme to understand something, then choose what to keep.")
            } else if savedItems.isEmpty {
                SuzzmeEmptyState(symbol: "magnifyingglass", title: "No matching items", message: "Try another phrase or clear your search.")
                Button("Clear Search") { searchText = "" }.buttonStyle(.bordered)
            } else {
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
                    ForEach(savedItems) { item in
                        NavigationLink { ItemDetailView(item: item) } label: {
                            SuzzmeItemRow(item: item)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("View the saved item and its source")
                        if item.id != savedItems.last?.id { Divider() }
                    }
                }
            }
        }
        .navigationTitle("History")
        .searchable(text: $searchText, prompt: "Search saved items")
    }
}
