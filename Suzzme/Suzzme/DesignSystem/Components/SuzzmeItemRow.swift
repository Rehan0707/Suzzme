import SwiftUI

struct SuzzmeItemRow: View {
    let item: SuzzmeItem
    var showTime = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        layout {
            if showTime, let date = item.dueDate {
                Text(date, style: .time).font(.subheadline.monospacedDigit())
                    .foregroundStyle(SuzzmeTheme.accent)
                    .frame(minWidth: 80, alignment: .leading)
            } else {
                SuzzmeSourceIcon(source: item.source).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.headline)
                Text(item.summary).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Item card") {
    SuzzmeCard {
        if let item = MockIntelligenceService.sample().importantItems.first {
            SuzzmePriorityBadge(priority: item.priority)
            SuzzmeItemRow(item: item)
        }
    }.padding()
}
