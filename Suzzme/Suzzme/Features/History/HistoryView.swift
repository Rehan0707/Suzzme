import SwiftUI

struct HistoryView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        SuzzmePage {
            SuzzmeEmptyState(symbol: "clock.arrow.circlepath", title: "A quiet record of what Suzzme noticed.",
                             message: "Structured information you chose to save stays on this device.")
            if !environment.activityItems.isEmpty {
                SuzzmeSectionHeader(title: "Saved to Suzzme")
                ForEach(environment.activityItems) { item in
                    SuzzmeCard {
                        Label(item.source.rawValue.capitalized, systemImage: "tray.and.arrow.down")
                            .font(.caption).foregroundStyle(SuzzmeTheme.accent)
                        SuzzmeItemRow(item: item)
                    }
                }
            } else if let items = environment.briefing?.completedItems {
                SuzzmeSectionHeader(title: "A sample small win")
                ForEach(items) { item in
                    SuzzmeCard {
                        Label("Completed · Demo", systemImage: "checkmark.circle").font(.caption).foregroundStyle(SuzzmeTheme.accent)
                        SuzzmeItemRow(item: item)
                    }
                }
            }
            Text(environment.activityItems.isEmpty ? "Saved items will appear here after you use the Brain Lab." : "Items are stored locally on this device.")
                .foregroundStyle(.secondary)
        }
    }
}
