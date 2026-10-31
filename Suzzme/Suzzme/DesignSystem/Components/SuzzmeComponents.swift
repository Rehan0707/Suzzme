import SwiftUI

struct SuzzmeCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    var highlighted = false
    @ViewBuilder var content: Content

    private var outline: Color {
        if contrast == .increased { return SuzzmeTheme.textSecondary }
        return highlighted
            ? SuzzmeTheme.intelligencePrimary.opacity(0.18)
            : SuzzmeTheme.separator.opacity(contrast == .increased ? 1 : colorScheme == .dark ? 0.55 : 0.42)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            content
        }
        .padding(SuzzmeTheme.Layout.compactInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? SuzzmeTheme.intelligenceSurface : SuzzmeTheme.backgroundSecondary,
                    in: RoundedRectangle(cornerRadius: SuzzmeTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SuzzmeTheme.cornerRadius, style: .continuous)
                .strokeBorder(outline, lineWidth: contrast == .increased ? 2 : SuzzmeTheme.hairline)
        }
    }
}

struct SuzzmeSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }
}

struct SuzzmeScreenIntroduction: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
            Text(title)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }
}

struct SuzzmeEyebrow: View {
    let title: LocalizedStringResource
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .imageScale(.small)
    }
}

struct SuzzmePriorityBadge: View {
    let priority: SuzzmeItem.Priority

    var body: some View {
        Label(priority.rawValue.capitalized, systemImage: priority == .urgent ? "exclamationmark.circle" : "circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(priority == .urgent ? SuzzmeTheme.warning : SuzzmeTheme.textSecondary)
            .padding(.horizontal, SuzzmeTheme.Spacing.small)
            .padding(.vertical, SuzzmeTheme.Spacing.xs)
            .background(priority == .urgent ? SuzzmeTheme.warning.opacity(0.08) : SuzzmeTheme.backgroundSecondary,
                        in: Capsule())
            .overlay {
                Capsule().strokeBorder(SuzzmeTheme.separator, lineWidth: SuzzmeTheme.hairline)
            }
    }
}

struct SuzzmeSourceIcon: View {
    let source: SuzzmeItem.Source

    var symbol: String {
        switch source {
        case .calendar: "calendar"
        case .mail: "envelope"
        case .messages, .message: "bubble.left.and.bubble.right"
        case .notification: "app.badge"
        case .reminders: "checklist"
        case .notes: "note.text"
        case .manual: "hand.draw"
        case .other: "tray"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(SuzzmeTheme.textSecondary)
            .accessibilityLabel(source.rawValue.capitalized)
    }
}

struct SuzzmeEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 48, height: 48)
                .background(SuzzmeTheme.backgroundSecondary, in: Circle())
                .overlay {
                    Circle().strokeBorder(SuzzmeTheme.separator, lineWidth: SuzzmeTheme.hairline)
                }
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, SuzzmeTheme.Spacing.small)
    }
}

struct SuzzmeStateLabel: View {
    let title: String
    let symbol: String
    var tone: Color = SuzzmeTheme.textSecondary

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tone)
            .accessibilityElement(children: .combine)
    }
}

/// Keeps action labels readable at accessibility text sizes.
struct SuzzmeActionControls<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder var content: Content

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) { content }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: SuzzmeTheme.Spacing.medium) { content }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) { content }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SuzzmeConfirmationSummary: View {
    let title: String
    let destructive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
            SuzzmeStateLabel(
                title: destructive ? "Destructive action" : "Your approval is needed",
                symbol: destructive ? "trash" : "checkmark.shield",
                tone: destructive ? SuzzmeTheme.destructive : SuzzmeTheme.intelligencePrimary
            )
            Text(title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text("Suzzme will act only after you confirm this exact change.")
                .font(.subheadline)
                .foregroundStyle(SuzzmeTheme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Native prominent buttons use a light brand fill in Dark Mode. Their label
/// must switch to dark ink instead of retaining the system's white foreground.
private struct SuzzmeProminentContrast: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
    #endif
    private var ink: Color {
        #if os(macOS)
        if controlActiveState == .inactive { return .primary }
        #endif
        return colorScheme == .dark ? .black : .white
    }
    func body(content: Content) -> some View {
        content.foregroundStyle(ink)
    }
}

extension View {
    func suzzmeProminentContrast() -> some View { modifier(SuzzmeProminentContrast()) }
}
