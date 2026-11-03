import SwiftUI
import WidgetKit

/// Companion's public Lock Screen presentation. ActivityKit supplies geometry;
/// this card never paints a custom Island or runs a repeating animation.
struct SuzzmeCompanionActivityCard: View {
    let phase: SuzzmeLiveActivityPhase
    var appearance: SuzzmeLiveActivityAppearance = .blue
    var startedAt: Date = .now
    var motionEnabled = true
    var stale = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    private var color: Color { appearance.color(dark: scheme == .dark) }
    private var accessible: Bool { typeSize.isAccessibilitySize }
    private var animates: Bool { motionEnabled && !stale && !reduceMotion && !luminanceReduced }
    private var destination: URL? { URL(string: phase == .summaryReady || phase == .urgentReady ? "suzzme://summary" : "suzzme://ask") }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !accessible {
                HStack(spacing: 8) {
                    SuzzmeActivityFace(phase: phase, color: color, motionEnabled: animates, stale: stale)
                        .frame(width: 28, height: 28)
                    Text("Suzzme").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    SuzzmeActivitySymbol(phase: phase, stale: stale, color: color, motionEnabled: animates)
                }
            }
            Text(stale ? (accessible ? "Open Suzzme" : "Open Suzzme to continue") : accessible ? shortTitle : phase.title)
                .font(.headline).lineLimit(accessible ? 1 : 2)
                .contentTransition(animates ? .opacity : .identity)
            if !accessible && !stale {
                Text(phase.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 8) {
                if accessible {
                    SuzzmeCharacterArtwork().frame(width: 26, height: 26)
                } else if !phase.isTerminal && !stale {
                    Text(startedAt, style: .timer)
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .accessibilityLabel("Session elapsed time")
                } else {
                    Label(stale ? "Update needed" : "Ready", systemImage: stale ? "clock" : "checkmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if let destination {
                    Link(destination: destination) {
                        Text(phase == .summaryReady || phase == .urgentReady ? "Read summary" : accessible ? "Open" : "Open Suzzme")
                            .font(.subheadline.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(color)
                    .accessibilityLabel(phase == .summaryReady || phase == .urgentReady ? "Read summary in Suzzme" : "Open this session in Suzzme")
                }
            }
        }
        .padding(14)
        .foregroundStyle(.primary)
        .animation(animates ? .smooth(duration: 0.25) : nil, value: phase)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suzzme session")
        .accessibilityValue(stale ? "Update needed" : phase.title)
    }

    private var shortTitle: String {
        switch phase {
        case .listening: "Listening"
        case .understanding: "Thinking"
        case .checking: "Checking"
        case .confirmation: "Review"
        case .working: "Working"
        case .speaking: "Speaking"
        case .summaryReady: "Ready"
        case .urgentReady: "Update ready"
        case .completed: "Complete"
        }
    }
}

struct SuzzmeCompanionEntry: TimelineEntry {
    let date: Date
    let snapshot: SuzzmeCompanionSnapshot?
}

/// WidgetKit owns the standard content margins and refresh schedule. This is a
/// meaningful status snapshot, never a live percentage or microphone meter.
struct SuzzmeCompanionSmallView: View {
    let entry: SuzzmeCompanionEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var phase: SuzzmeLiveActivityPhase? { entry.snapshot?.visiblePhase(at: entry.date) }
    private var color: Color { (entry.snapshot?.appearance ?? .blue).color(dark: scheme == .dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SuzzmeCharacterArtwork().frame(width: typeSize.isAccessibilitySize ? 28 : 40, height: typeSize.isAccessibilitySize ? 28 : 40)
                Spacer(minLength: 8)
                Image(systemName: phase?.symbol ?? "sun.horizon")
                    .font(.caption.weight(.semibold)).foregroundStyle(color)
                    .widgetAccentable().accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            Text(typeSize.isAccessibilitySize ? status : title)
                .font(typeSize.isAccessibilitySize ? .caption : .headline)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if !typeSize.isAccessibilitySize {
                Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: phase == nil || phase == .summaryReady || phase == .urgentReady ? "suzzme://summary" : "suzzme://ask"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Suzzme Companion")
        .accessibilityValue(status)
        .accessibilityHint("Opens the related content in Suzzme")
    }

    private var title: String {
        switch phase {
        case .summaryReady: "Your day,\nunderstood."
        case .urgentReady: "An update\nfor you."
        case .understanding: "Connecting\nthe dots."
        case .checking: "Your context,\ntogether."
        case .speaking: "A little\nperspective."
        case .listening: "A moment\nto listen."
        case .confirmation: "Your review\ncomes first."
        case .working: "Your request,\nin progress."
        case .completed: "All done."
        case nil: "Your day,\nwith Suzzme."
        }
    }

    private var status: String {
        switch phase {
        case .summaryReady: "Ready to read"
        case .understanding: "Thinking"
        case nil: "Open Suzzme"
        default: phase?.title ?? "Open Suzzme"
        }
    }
}

