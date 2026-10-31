#if os(macOS)
import SwiftUI

struct BackgroundPreparationReceiptRow: View {
    let receipt: ScheduledBriefingReceipt
    var retryScheduled = false

    private var presentation: BackgroundPreparationReceiptPresentation {
        .init(receipt: receipt)
    }

    var body: some View {
        HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.medium) {
            Image(systemName: presentation.symbol)
                .font(.title3)
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .frame(width: SuzzmeTheme.Layout.symbolColumn)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                Text(presentation.title)
                    .font(.headline)
                Text(presentation.mode)
                    .font(.subheadline)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                Text("\(presentation.dateLabel) \(presentation.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                if let metadata = presentation.metadata {
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                }
                if let detail = presentation.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                }
                if retryScheduled, let retryAt = receipt.retryAt {
                    Text("Next attempt \(retryAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, SuzzmeTheme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}
#endif
