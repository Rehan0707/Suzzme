import SwiftUI

struct BriefingView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        SuzzmePage {
            SuzzmeEmptyState(symbol: "text.alignleft", title: "Your day, with perspective.",
                             message: "A few useful thoughts, before the day gets loud. This sample shows how your daily briefing will feel.")
            if let briefing = environment.briefing {
                SuzzmeCard(highlighted: true) {
                    Text(briefing.date, format: .dateTime.weekday(.wide).month().day()).font(.caption).foregroundStyle(.secondary)
                    Text(briefing.greeting).font(.title2.weight(.semibold))
                    Text(briefing.summary).font(.title3)
                }
                DisclosureGroup("Explore the sample day (\(briefing.attentionCount))") {
                    ForEach(briefing.importantItems + briefing.upcomingItems + briefing.carriedOverItems) { item in
                        NavigationLink { ItemDetailView(item: item) } label: { SuzzmeItemRow(item: item) }.buttonStyle(.plain)
                    }
                }
            }
            Text("Personal briefings will arrive with on-device intelligence in a later step.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
