import SwiftUI

struct ItemDetailView: View {
    let item: SuzzmeItem
    var body: some View {
        SuzzmePage {
            SuzzmePriorityBadge(priority: item.priority)
            Text(item.title).font(.title.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(item.summary).font(.body).foregroundStyle(SuzzmeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            SuzzmeCard {
                Label { Text(item.source.rawValue.capitalized) } icon: { SuzzmeSourceIcon(source: item.source) }
                LabeledContent("Type", value: item.category.rawValue.capitalized)
                if let due = item.dueDate {
                    LabeledContent("When") { Text(due, format: .dateTime.weekday().month().day().hour().minute()) }
                }
                LabeledContent("Status", value: item.isCompleted ? "Completed" : "Open")
            }
            Text("Saved on this device. Viewing this item does not change its source.")
                .font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("Details")
    }
}
