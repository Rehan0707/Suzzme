import SwiftUI

struct SuzzmeCard<Content: View>: View {
    var highlighted = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? SuzzmeTheme.wash : SuzzmeTheme.surface,
                        in: RoundedRectangle(cornerRadius: SuzzmeTheme.cornerRadius))
    }
}

struct SuzzmeSectionHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
    }
}

struct SuzzmePriorityBadge: View {
    let priority: SuzzmeItem.Priority
    var body: some View {
        Label(priority.rawValue.capitalized, systemImage: priority == .urgent ? "exclamationmark.circle" : "circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(SuzzmeTheme.accent)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(SuzzmeTheme.background, in: Capsule())
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
        Image(systemName: symbol).foregroundStyle(SuzzmeTheme.accent)
            .accessibilityLabel(source.rawValue.capitalized)
    }
}

struct SuzzmeEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(SuzzmeTheme.accent)
                .accessibilityHidden(true)
            Text(title).font(.largeTitle.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text(message).font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 16)
    }
}

struct SuzzmeGreeting: View {
    let greeting: String
    let count: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(greeting).font(.largeTitle.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text("Here’s what matters today.").font(.title3).foregroundStyle(.secondary)
            Text("\(count) things to give a little attention.")
                .font(.subheadline).foregroundStyle(SuzzmeTheme.accent).padding(.top, 4)
        }
    }
}
