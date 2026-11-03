import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

#if !SUZZME_PRESENCE_RENDER
@main
struct SuzzmePresenceWidgets: WidgetBundle {
    var body: some Widget {
        SuzzmeSessionActivity()
        SuzzmeCompanionWidget()
    }
}
#endif

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
    @Environment(\.dynamicTypeSize) private var typeSize

    @ViewBuilder var body: some View {
        switch context.state.design {
        case .companion, .focus:
            Text("Suzzme").font(typeSize.isAccessibilitySize ? .caption : .headline).lineLimit(1).foregroundStyle(.white)
        case .briefing:
            Text("Daily briefing").font(typeSize.isAccessibilitySize ? .caption : .headline).lineLimit(1).foregroundStyle(.white)
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
        HStack(spacing: 0) {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Suzzme")
        .accessibilityValue(context.isStale ? "Open Suzzme to continue" : context.state.phase.title)
    }
}

private struct SuzzmeSessionLockScreen: View {
    let context: ActivityViewContext<SuzzmeLiveActivityAttributes>
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        SuzzmeCompanionActivityCard(phase: context.state.phase,
            appearance: context.state.appearance, startedAt: context.attributes.startedAt,
            motionEnabled: context.state.motionEnabled, stale: context.isStale)
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(context.state.appearance.color(dark: scheme == .dark))
    }
}

private struct SuzzmeSessionExpanded: View {
    let context: ActivityViewContext<SuzzmeLiveActivityAttributes>
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(context.state.phase.displayTitle(stale: context.isStale,
                accessibilitySize: dynamicTypeSize.isAccessibilitySize))
                .font(dynamicTypeSize.isAccessibilitySize ? .caption : .headline)
                .lineLimit(1).fixedSize(horizontal: false, vertical: true)
                    .modifier(SuzzmeActivityContentMotion(phase: context.state.phase,
                        enabled: context.state.motionEnabled, stale: context.isStale))
            if !context.isStale && !dynamicTypeSize.isAccessibilitySize {
                Text(context.state.phase.detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if (context.state.phase == .summaryReady || context.state.phase == .urgentReady), let destination = URL(string: "suzzme://summary") {
                    Link("Read summary", destination: destination)
                        .font(dynamicTypeSize.isAccessibilitySize ? .caption.weight(.semibold) : .subheadline.weight(.semibold)).frame(minHeight: 44)
                }
                if context.state.phase == .confirmation, let destination = URL(string: "suzzme://ask") {
                Link(dynamicTypeSize.isAccessibilitySize ? "Review" : "Review in Suzzme", destination: destination)
                    .font(dynamicTypeSize.isAccessibilitySize ? .caption.weight(.semibold) : .subheadline.weight(.semibold)).frame(minHeight: 44)
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
            .animation(animates ? .smooth(duration: 0.25) : nil, value: phase)
            .animation(animates ? .smooth(duration: 0.24) : nil, value: stale)
    }
}

#if !SUZZME_PRESENCE_RENDER
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

#endif

private extension SuzzmeLiveActivityPhase {
    /// Keep the system's bounded surface legible at larger text sizes; the
    /// complete request and confirmation remain available in the app.
    func displayTitle(stale: Bool, accessibilitySize: Bool) -> String {
        if stale { return accessibilitySize ? "Open Suzzme" : "Open Suzzme to continue" }
        if accessibilitySize {
            switch self {
            case .listening: return "Listening"
            case .understanding: return "Thinking"
            case .checking: return "Checking"
            case .confirmation: return "Review"
            case .working: return "Working"
            case .speaking: return "Speaking"
            case .summaryReady: return "Ready"
            case .urgentReady: return "Update ready"
            case .completed: return "Complete"
            }
        }
        return title
    }
}
