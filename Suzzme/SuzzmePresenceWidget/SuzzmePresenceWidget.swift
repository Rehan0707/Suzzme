import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

@main
struct SuzzmePresenceWidgets: WidgetBundle {
    var body: some Widget { SuzzmeSessionActivity() }
}

struct SuzzmeSessionActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SuzzmeLiveActivityAttributes.self) { context in
            SuzzmeSessionLockScreen(context: context)
                .widgetURL(destination(for: context.state.phase))
        } dynamicIsland: { context in
            let color = context.state.appearance.islandColor
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SuzzmeIslandLeading(context: context, color: color)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SuzzmeIslandTrailing(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SuzzmeSessionExpanded(context: context)
                }
            } compactLeading: {
                SuzzmeIslandCompactLeading(context: context, color: color)
            } compactTrailing: {
                SuzzmeIslandCompactTrailing(context: context, color: color)
            } minimal: {
                SuzzmeIslandMinimal(context: context, color: color)
            }
            .keylineTint(color)
            .widgetURL(destination(for: context.state.phase))
        }
    }

    private func destination(for phase: SuzzmeLiveActivityPhase) -> URL? {
        switch phase {
        case .summaryReady, .urgentReady: URL(string: "suzzme://summary")
        default: URL(string: "suzzme://ask")
        }
    }
}

private struct SuzzmeIslandLeading: View {
    let context: ActivityViewContext<SuzzmeLiveActivityAttributes>
    let color: Color

    @ViewBuilder var body: some View {
        switch context.state.design {
        case .companion:
            SuzzmeActivityFace(phase: context.state.phase, color: color,
                motionEnabled: context.state.motionEnabled, stale: context.isStale)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
        case .briefing:
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(color)
                .accessibilityLabel("Daily briefing")
        case .focus:
            Image(systemName: context.isStale ? "moon" : context.state.phase.symbol)
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(color)
                .accessibilityLabel(context.isStale ? "Open Suzzme to continue" : context.state.phase.title)
        }
    }
}

private struct SuzzmeIslandTrailing: View {
    let context: ActivityViewContext<SuzzmeLiveActivityAttributes>

    @ViewBuilder var body: some View {
        switch context.state.design {
        case .companion, .focus:
            Text("Suzzme").font(.headline).foregroundStyle(.white)
        case .briefing:
            Text("Daily briefing").font(.headline).foregroundStyle(.white)
        }
    }
}

private struct SuzzmeIslandCompactLeading: View {
    let context: ActivityViewContext<SuzzmeLiveActivityAttributes>
    let color: Color

    @ViewBuilder var body: some View {
        switch context.state.design {
        case .companion:
            SuzzmeActivityFace(phase: context.state.phase, color: color,
                motionEnabled: context.state.motionEnabled, stale: context.isStale)
                .frame(width: 22, height: 22).accessibilityHidden(true)
        case .briefing:
            Image(systemName: "sun.horizon.fill").font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color).accessibilityHidden(true)
        case .focus:
            Image(systemName: context.isStale ? "moon" : context.state.phase.symbol)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
                .accessibilityLabel(context.isStale ? "Open Suzzme to continue" : context.state.phase.title)
        }
    }
}

private struct SuzzmeIslandCompactTrailing: View {
    let context: ActivityViewContext<SuzzmeLiveActivityAttributes>
    let color: Color

    @ViewBuilder var body: some View {
        switch context.state.design {
        case .companion:
            SuzzmeActivitySymbol(phase: context.state.phase, stale: context.isStale,
                color: color, motionEnabled: context.state.motionEnabled)
        case .briefing:
            Text(context.isStale ? "Open" : context.state.phase.compactLabel)
                .font(.caption2.weight(.semibold)).lineLimit(1).foregroundStyle(color)
                .accessibilityLabel(context.isStale ? "Open Suzzme to continue" : context.state.phase.title)
        case .focus:
            SuzzmeActivitySymbol(phase: context.state.phase, stale: context.isStale,
                color: color, motionEnabled: context.state.motionEnabled)
        }
    }
}

private struct SuzzmeIslandMinimal: View {
    let context: ActivityViewContext<SuzzmeLiveActivityAttributes>
    let color: Color

    @ViewBuilder var body: some View {
        switch context.state.design {
        case .companion:
            SuzzmeActivityFace(phase: context.state.phase, color: color,
                motionEnabled: context.state.motionEnabled, stale: context.isStale)
                .frame(width: 22, height: 22).accessibilityHidden(true)
        case .briefing:
            Image(systemName: context.isStale ? "moon" : "sun.horizon.fill")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
                .accessibilityLabel(context.isStale ? "Open Suzzme to continue" : "Daily briefing")
        case .focus:
            Image(systemName: context.isStale ? "moon" : context.state.phase.symbol)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
                .accessibilityLabel(context.isStale ? "Open Suzzme to continue" : context.state.phase.title)
        }
    }
}

private struct SuzzmeSessionLockScreen: View {
    let context: ActivityViewContext<SuzzmeLiveActivityAttributes>
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let color = context.state.appearance.color(dark: scheme == .dark)
        HStack(alignment: .top, spacing: 14) {
            SuzzmeActivityFace(phase: context.state.phase, color: color,
                motionEnabled: context.state.motionEnabled, stale: context.isStale)
                .padding(10).frame(width: 44, height: 44)
                .background(color.opacity(0.10), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                if !dynamicTypeSize.isAccessibilitySize {
                    HStack {
                        Text("Suzzme").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        if !context.isStale && context.state.phase != .summaryReady && context.state.phase != .urgentReady {
                            Text(context.attributes.startedAt, style: .timer).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .accessibilityLabel("Session elapsed time")
                        }
                    }
                }
                Text(context.state.phase.displayTitle(stale: context.isStale,
                    accessibilitySize: dynamicTypeSize.isAccessibilitySize))
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                    .modifier(SuzzmeActivityContentMotion(phase: context.state.phase,
                        enabled: context.state.motionEnabled, stale: context.isStale))
                if !context.isStale && !dynamicTypeSize.isAccessibilitySize {
                    Text(context.state.phase.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .modifier(SuzzmeActivityContentMotion(phase: context.state.phase,
                            enabled: context.state.motionEnabled, stale: context.isStale))
                }
                if (context.state.phase == .summaryReady || context.state.phase == .urgentReady), let destination = URL(string: "suzzme://summary") {
                    Link("Read summary", destination: destination)
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
                if context.state.phase == .confirmation, let destination = URL(string: "suzzme://ask") {
                    Link(dynamicTypeSize.isAccessibilitySize ? "Review" : "Review in Suzzme", destination: destination)
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        .transition(.opacity)
                        .foregroundStyle(color)
                        .accessibilityLabel("Review in Suzzme")
                }
            }
        }
        .padding(16)
        .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
        .activitySystemActionForegroundColor(color)
        .foregroundStyle(Color(uiColor: .label))
        .modifier(SuzzmeActivityContentMotion(phase: context.state.phase,
            enabled: context.state.motionEnabled, stale: context.isStale))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suzzme session")
    }
}

private struct SuzzmeSessionExpanded: View {
    let context: ActivityViewContext<SuzzmeLiveActivityAttributes>
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(context.state.phase.displayTitle(stale: context.isStale,
                accessibilitySize: dynamicTypeSize.isAccessibilitySize))
                .font(.headline).fixedSize(horizontal: false, vertical: true)
                    .modifier(SuzzmeActivityContentMotion(phase: context.state.phase,
                        enabled: context.state.motionEnabled, stale: context.isStale))
            if !context.isStale && !dynamicTypeSize.isAccessibilitySize {
                Text(context.state.phase.detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if (context.state.phase == .summaryReady || context.state.phase == .urgentReady), let destination = URL(string: "suzzme://summary") {
                    Link("Read summary", destination: destination)
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
                if context.state.phase == .confirmation, let destination = URL(string: "suzzme://ask") {
                Link(dynamicTypeSize.isAccessibilitySize ? "Review" : "Review in Suzzme", destination: destination)
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        .transition(.opacity)
                    .foregroundStyle(context.state.appearance.islandColor)
                    .accessibilityLabel("Review in Suzzme")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .modifier(SuzzmeActivityContentMotion(phase: context.state.phase,
            enabled: context.state.motionEnabled, stale: context.isStale))
        .accessibilityElement(children: .contain)
    }
}

/// WidgetKit animates real content updates; the system owns Island expansion.
/// No repeating timeline is needed, and Always-On/stale content remains still.
private struct SuzzmeActivityContentMotion: ViewModifier {
    let phase: SuzzmeLiveActivityPhase
    let enabled: Bool
    let stale: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    private var animates: Bool { enabled && !stale && !reduceMotion && !luminanceReduced }

    func body(content: Content) -> some View {
        content
            .contentTransition(animates ? .opacity : .identity)
            .animation(animates ? .smooth(duration: 0.32) : nil, value: phase)
            .animation(animates ? .smooth(duration: 0.24) : nil, value: stale)
            .transaction { if !animates { $0.disablesAnimations = true } }
    }
}

private struct SuzzmeActivityFace: View {
    let phase: SuzzmeLiveActivityPhase
    let color: Color
    let motionEnabled: Bool
    let stale: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    private var animates: Bool { motionEnabled && !stale && !reduceMotion && !luminanceReduced }

    private var tilt: Double {
        guard animates else { return 0 }
        switch phase {
        case .understanding: return -3
        case .checking: return 3
        default: return 0
        }
    }

    private var scale: CGFloat {
        guard animates else { return 1 }
        switch phase {
        case .listening: return 1.04
        case .understanding: return 0.96
        case .checking: return 1.02
        case .confirmation, .summaryReady, .urgentReady: return 1
        case .working: return 0.98
        case .speaking: return 1.03
        }
    }

    var body: some View {
        SuzzmeCharacterArtwork()
            .scaleEffect(scale)
            .rotationEffect(.degrees(tilt))
            .animation(animates ? .spring(duration: 0.42, bounce: 0.12) : nil, value: phase)
            .transaction { if !animates { $0.disablesAnimations = true } }
            .accessibilityLabel("Suzzme")
            .accessibilityValue(stale ? "Open Suzzme to continue" : phase.title)
    }
}

#Preview("Session · Lock Screen", as: .content, using: SuzzmeLiveActivityAttributes()) {
    SuzzmeSessionActivity()
} contentStates: {
    SuzzmeLiveActivityAttributes.ContentState(phase: .listening)
    SuzzmeLiveActivityAttributes.ContentState(phase: .checking)
    SuzzmeLiveActivityAttributes.ContentState(phase: .confirmation, motionEnabled: false)
    SuzzmeLiveActivityAttributes.ContentState(phase: .speaking)
}

#Preview("Session · Expanded", as: .dynamicIsland(.expanded), using: SuzzmeLiveActivityAttributes()) {
    SuzzmeSessionActivity()
} contentStates: {
    SuzzmeLiveActivityAttributes.ContentState(phase: .summaryReady, design: .companion)
    SuzzmeLiveActivityAttributes.ContentState(phase: .understanding, design: .briefing)
    SuzzmeLiveActivityAttributes.ContentState(phase: .speaking, design: .focus)
    SuzzmeLiveActivityAttributes.ContentState(phase: .confirmation)
}

#Preview("Session · Compact", as: .dynamicIsland(.compact), using: SuzzmeLiveActivityAttributes()) {
    SuzzmeSessionActivity()
} contentStates: {
    SuzzmeLiveActivityAttributes.ContentState(phase: .listening, design: .companion)
    SuzzmeLiveActivityAttributes.ContentState(phase: .summaryReady, appearance: .deepBlue, design: .briefing)
    SuzzmeLiveActivityAttributes.ContentState(phase: .speaking, appearance: .burgundy, design: .focus)
}

#Preview("Session · Minimal", as: .dynamicIsland(.minimal), using: SuzzmeLiveActivityAttributes()) {
    SuzzmeSessionActivity()
} contentStates: {
    SuzzmeLiveActivityAttributes.ContentState(phase: .listening, design: .companion)
    SuzzmeLiveActivityAttributes.ContentState(phase: .summaryReady, design: .briefing)
    SuzzmeLiveActivityAttributes.ContentState(phase: .confirmation, appearance: .graphite, motionEnabled: false, design: .focus)
}

private struct SuzzmeActivitySymbol: View {
    let phase: SuzzmeLiveActivityPhase
    let stale: Bool
    let color: Color
    let motionEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    var body: some View {
        let animates = motionEnabled && !stale && !reduceMotion && !luminanceReduced
        Image(systemName: stale ? "moon" : phase.symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
            .contentTransition(animates ? .symbolEffect(.replace) : .identity)
            .animation(animates ? .easeInOut(duration: 0.3) : nil, value: phase)
            .transaction { if !animates { $0.disablesAnimations = true } }
            .accessibilityLabel(stale ? "Open Suzzme to continue" : phase.title)
    }
}

private extension SuzzmeLiveActivityAppearance {
    var islandColor: Color { color(dark: true) }
    func color(dark: Bool) -> Color {
        switch self {
        case .blue: dark ? Color(red: 0.49, green: 0.74, blue: 0.98) : Color(red: 0.12, green: 0.43, blue: 0.82)
        case .pink: dark ? Color(red: 0.98, green: 0.49, blue: 0.72) : Color(red: 0.69, green: 0.20, blue: 0.43)
        case .red: dark ? Color(red: 0.98, green: 0.49, blue: 0.52) : Color(red: 0.76, green: 0.22, blue: 0.27)
        case .orange: dark ? Color(red: 0.98, green: 0.66, blue: 0.49) : Color(red: 0.72, green: 0.34, blue: 0.12)
        case .yellow: dark ? Color(red: 0.98, green: 0.87, blue: 0.49) : Color(red: 0.54, green: 0.40, blue: 0.04)
        case .green: dark ? Color(red: 0.50, green: 0.98, blue: 0.49) : Color(red: 0.16, green: 0.48, blue: 0.20)
        case .teal: dark ? Color(red: 0.49, green: 0.98, blue: 0.89) : Color(red: 0.02, green: 0.48, blue: 0.46)
        case .purple: dark ? Color(red: 0.76, green: 0.49, blue: 0.98) : Color(red: 0.48, green: 0.25, blue: 0.70)
        case .suzzmePurple: dark ? Color(red: 0.80, green: 0.68, blue: 1) : Color(red: 0.38, green: 0.12, blue: 0.62)
        case .burgundy: dark ? Color(red: 0.94, green: 0.57, blue: 0.54) : Color(red: 0.50, green: 0.12, blue: 0.23)
        case .deepBlue: dark ? Color(red: 0.52, green: 0.77, blue: 1) : Color(red: 0.08, green: 0.25, blue: 0.57)
        case .silver: dark ? Color(red: 0.82, green: 0.86, blue: 0.91) : Color(red: 0.38, green: 0.42, blue: 0.49)
        case .graphite: dark ? Color(red: 0.88, green: 0.90, blue: 0.96) : Color(red: 0.17, green: 0.19, blue: 0.24)
        }
    }
}

private extension SuzzmeLiveActivityPhase {
    /// Keep the system's bounded surface legible at larger text sizes; the
    /// complete request and confirmation remain available in the app.
    func displayTitle(stale: Bool, accessibilitySize: Bool) -> String {
        if stale { return accessibilitySize ? "Open Suzzme" : "Open Suzzme to continue" }
        if accessibilitySize && self == .confirmation { return "Review needed" }
        return title
    }
}
