import SwiftUI

struct SuzzmeItemRow: View {
    let item: SuzzmeItem
    var showTime = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs)) : AnyLayout(HStackLayout(alignment: .top, spacing: SuzzmeTheme.Spacing.medium))
        layout {
            if showTime, let date = item.dueDate {
                Text(date, style: .time).font(.subheadline.monospacedDigit())
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .frame(minWidth: 80, alignment: .leading)
            } else {
                SuzzmeSourceIcon(source: item.source).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                Text(item.title).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   item.summary.localizedCaseInsensitiveCompare(item.title) != .orderedSame {
                    Text(item.summary).font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, SuzzmeTheme.Spacing.xs)
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
