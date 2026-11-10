#if os(macOS)
import SwiftUI

/// An interactive, Apple-native Dynamic Focus Island for the macOS Notch and top-center surfaces.
/// Displays live focus countdown, target commitments, and quick break/completion controls.
struct MacNotchFocusView: View {
    let activity: MacFocusActivity
    let isHovered: Bool
    let hasNotch: Bool
    var notchWidth: CGFloat = 180
    var notchHeight: CGFloat = 0
    var onToggleExpand: (() -> Void)? = nil
    var onHoverChanged: ((Bool) -> Void)? = nil
    let onExtend: () -> Void
    let onStop: () -> Void
    let onOpenPlan: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if isHovered {
                expandedFocusCard
            } else {
                compactFocusPill
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            onHoverChanged?(hovering)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suzzme Focus Session. \(activity.title). \(activity.remainingDescription)")
        .accessibilityIdentifier("suzzme-notch-focus-island")
    }

    // MARK: - Compact Island Pill

    private var compactFocusPill: some View {
        Button {
            onToggleExpand?()
        } label: {
            HStack(spacing: SuzzmeTheme.Spacing.small) {
                SuzzmeFace(state: .understanding, color: SuzzmeTheme.intelligencePrimary, animation: .gentle)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(activity.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(SuzzmeTheme.intelligencePrimary)
                            .frame(width: 5, height: 5)
                        Text(activity.remainingDescription)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.80))
                    }
                }

                Spacer(minLength: 4)

                // Mini Progress Ring
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.15), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: CGFloat(activity.progress))
                        .stroke(SuzzmeTheme.intelligencePrimary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, SuzzmeTheme.Spacing.medium)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Focus Card

    private var expandedFocusCard: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
            // Header: Status tag & Digital Timer
            HStack(alignment: .center) {
                HStack(spacing: SuzzmeTheme.Spacing.xs) {
                    SuzzmeFace(state: .understanding, color: SuzzmeTheme.intelligencePrimary, animation: .gentle)
                        .frame(width: 20, height: 20)
                    Text("Focus Session")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                        .textCase(.uppercase)
                }

                Spacer()

                Text(activity.formattedTimer)
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(.white)
                    .accessibilityLabel("\(activity.remainingDescription)")
            }

            // Title & Description
            Text(activity.title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)

            // Progress Bar
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(height: 5)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [SuzzmeTheme.intelligencePrimary, SuzzmeTheme.controlAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(proxy.size.width * CGFloat(activity.progress), 8), height: 5)
                }
            }
            .frame(height: 5)
            .accessibilityHidden(true)

            // Target Commitments / Tasks
            if !activity.targetTasks.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(activity.targetTasks.prefix(2), id: \.self) { task in
                        HStack(spacing: SuzzmeTheme.Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                            Text(task)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Divider()
                .background(.white.opacity(0.12))

            // Action Controls
            HStack(spacing: SuzzmeTheme.Spacing.xs) {
                Button(action: onExtend) {
                    Label("+5m Break", systemImage: "cup.and.saucer.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .accessibilityIdentifier("suzzme-notch-focus-extend")
                .accessibilityHint("Adds 5 minutes to this focus window")

                Spacer()

                Button(action: onOpenPlan) {
                    Label("Day Plan", systemImage: "calendar.badge.clock")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .accessibilityIdentifier("suzzme-notch-focus-plan")

                Button(action: onStop) {
                    Text("Complete")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(SuzzmeTheme.intelligencePrimary)
                .accessibilityIdentifier("suzzme-notch-focus-stop")
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, SuzzmeTheme.Spacing.medium)
        .padding(.vertical, SuzzmeTheme.Spacing.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
#endif
