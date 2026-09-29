import SwiftUI

struct SuzzmeCard<Content: View>: View {
    var highlighted = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            content
        }
        .padding(SuzzmeTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            highlighted ? SuzzmeTheme.intelligenceSurface : SuzzmeTheme.backgroundSecondary,
            in: RoundedRectangle(cornerRadius: SuzzmeTheme.cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SuzzmeTheme.cornerRadius, style: .continuous)
                .strokeBorder(
                    highlighted ? SuzzmeTheme.intelligencePrimary.opacity(0.12) : .clear,
                    lineWidth: SuzzmeTheme.hairline
                )
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

struct SuzzmeEyebrow: View {
    let title: LocalizedStringResource
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(SuzzmeTheme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(SuzzmeTheme.accent.opacity(0.1), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(SuzzmeTheme.accent.opacity(0.2), lineWidth: SuzzmeTheme.hairline)
            }
    }
}

struct SuzzmePriorityBadge: View {
    let priority: SuzzmeItem.Priority

    var body: some View {
        Label(priority.rawValue.capitalized, systemImage: priority == .urgent ? "exclamationmark.circle" : "circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(SuzzmeTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(SuzzmeTheme.background, in: Capsule())
            .overlay {
                Capsule().strokeBorder(SuzzmeTheme.accent.opacity(0.18), lineWidth: SuzzmeTheme.hairline)
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
            .foregroundStyle(SuzzmeTheme.accent)
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
                .font(.largeTitle)
                .foregroundStyle(SuzzmeTheme.accent)
                .symbolRenderingMode(.hierarchical)
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
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium))
            : AnyLayout(HStackLayout())
        layout { content }
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

struct SuzzmeGreeting: View {
    let greeting: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SuzzmeEyebrow(title: "YOUR DAY", symbol: "sparkles")
            Text(greeting)
                .font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text("Here’s what matters today.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("\(count) things to give a little attention.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SuzzmeTheme.accent)
                .padding(.top, 4)
        }
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
