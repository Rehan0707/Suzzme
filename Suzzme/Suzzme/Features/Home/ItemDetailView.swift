import SwiftUI

struct ItemDetailView: View {
    let item: SuzzmeItem
    var body: some View {
        SuzzmePage {
            SuzzmePriorityBadge(priority: item.priority)
            Text(item.title).font(.largeTitle.weight(.semibold))
            Text(item.summary).font(.title3).foregroundStyle(.secondary)
            SuzzmeCard {
                Label { Text("Sample from \(item.source.rawValue)") } icon: { SuzzmeSourceIcon(source: item.source) }
                LabeledContent("Type", value: item.category.rawValue.capitalized)
                if let due = item.dueDate {
                    LabeledContent("When") { Text(due, format: .dateTime.weekday().month().day().hour().minute()) }
                }
                LabeledContent("Status", value: item.isCompleted ? "Completed" : "Open")
            }
            Text("This is demo information. No connected source or reminder has been changed.")
                .font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("Details")
    }
}
