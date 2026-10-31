#if os(macOS)
import SwiftUI

/// A receipt projection shared by the menu and notch. It owns no worker or
/// assistant state; its actions keep the displayed run's identity.
struct MacBackgroundPreparationView: View {
    let activity: ScheduledBriefingActivity
    var systemSurface = false
    let onStop: (UUID) -> Void
    let onOpenTasks: () -> Void
    let onOpenSummary: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    private var primaryText: Color { systemSurface ? .white : SuzzmeTheme.textPrimary }
    private var secondaryText: Color {
        systemSurface ? .white.opacity(contrast == .increased ? 1 : 0.82) : SuzzmeTheme.textSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
            HStack(spacing: SuzzmeTheme.Spacing.small) {
                // Background preparation does not make the conversational
                // assistant listen, reason, or speak.
                SuzzmeFace(state: .idle, color: primaryText, animation: .minimal)
                    .frame(width: SuzzmeTheme.Layout.touchTarget, height: SuzzmeTheme.Layout.touchTarget)
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                    Text("Daily Summary")
                        .font(.headline)
                        .foregroundStyle(primaryText)
                    Text("Background task")
                        .font(.caption)
                        .foregroundStyle(secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: SuzzmeTheme.Spacing.xs) {
                    statusSymbol
                    Text(activity.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(activity.message)
                    .font(.subheadline)
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let retryAt = activity.retryAt {
                    Text("Retry scheduled for \(retryAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            if dynamicTypeSize.isAccessibilitySize {
                verticalActions
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: SuzzmeTheme.Spacing.xs) { actions }
                        .fixedSize(horizontal: true, vertical: false)
                    verticalActions
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("suzzme-background-preparation")
    }

    @ViewBuilder private var statusSymbol: some View {
        if activity.isRunning && !reduceMotion && scenePhase == .active {
            ProgressView()
                .controlSize(.small)
                .tint(primaryText)
                .frame(width: SuzzmeTheme.Spacing.medium, height: SuzzmeTheme.Spacing.medium)
                .accessibilityHidden(true)
        } else {
            Image(systemName: activity.symbol)
                .foregroundStyle(primaryText)
                .accessibilityHidden(true)
        }
    }

    private var verticalActions: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) { actions }
    }

    @ViewBuilder private var actions: some View {
        if activity.isRunning {
            Button {
                onStop(activity.id)
            } label: {
                Text(activity.isStopping ? "Stopping…" : "Stop")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
            }
            .disabled(!activity.canStop)
            .buttonStyle(.bordered)
            .tint(primaryText)
            .accessibilityLabel(activity.isStopping ? "Stopping Daily Summary preparation" : "Stop Daily Summary preparation")
            .accessibilityHint("Stops this preparation run. Automatic preparation keeps its current setting.")
            .accessibilityIdentifier("suzzme-background-stop")
        }
        if activity.canOpenSummary {
            Button(action: onOpenSummary) {
                Text("Open Summary")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
            }
            .buttonStyle(.bordered)
            .tint(primaryText)
            .accessibilityHint("Opens the current Daily Summary")
            .accessibilityIdentifier("suzzme-background-open-summary")
        }
        Button(action: onOpenTasks) {
            Text("Open Tasks")
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
        }
        .buttonStyle(.bordered)
        .tint(primaryText)
        .accessibilityLabel("Open Background Tasks")
        .accessibilityIdentifier("suzzme-background-open-tasks")
    }
}
#endif
