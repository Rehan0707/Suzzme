import SwiftUI

/// An interactive day planner and focus time proposer presented in the Daily Summary.
/// Suggests optimal uninterrupted focus windows around existing calendar events
/// and allows one-tap scheduling directly into macOS Apple Calendar.
struct DayPlanFocusView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isSchedulingID: UUID?
    @State private var scheduleError: String?

    let timeline: DayScheduleTimeline

    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            header

            if timeline.proposedFocusBlocks.isEmpty {
                emptyStateCard
            } else {
                ForEach(timeline.proposedFocusBlocks) { block in
                    focusCard(for: block)
                }
            }

            if let error = scheduleError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.destructive)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
            HStack(spacing: SuzzmeTheme.Spacing.xs) {
                Image(systemName: "calendar.badge.clock")
                    .font(.headline)
                    .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                Text("Today’s Focus & Action Plan")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            Text("Suzzme mapped your calendar gaps and open commitments to find your best focus time.")
                .font(.subheadline)
                .foregroundStyle(SuzzmeTheme.textSecondary)
        }
    }

    private var emptyStateCard: some View {
        SuzzmeCard {
            HStack(spacing: SuzzmeTheme.Spacing.small) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                    Text("Schedule Full Today")
                        .font(.headline)
                    Text("Your remaining hours are committed. Suzzme will monitor your calendar for any cancellations or openings.")
                        .font(.subheadline)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func focusCard(for block: ProposedFocusBlock) -> some View {
        let isScheduled = environment.scheduledFocusBlockIDs.contains(block.id)
        let isWorking = isSchedulingID == block.id
        let isFocusActive = environment.activeFocusActivity?.id == block.id

        SuzzmeCard {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                // Header tag & duration
                HStack(alignment: .center) {
                    if isFocusActive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(SuzzmeTheme.intelligencePrimary)
                                .frame(width: 7, height: 7)
                            Text("Active in Mac Notch · \(environment.activeFocusActivity?.remainingDescription ?? "")")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                        }
                    } else {
                        SuzzmeStateLabel(title: "Recommended Focus Window", symbol: "sparkles")
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(block.windowDescription)
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SuzzmeTheme.intelligencePrimary.opacity(0.12))
                    .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                    .clipShape(Capsule())
                }

                // Title & Reason
                Text(block.title)
                    .font(.headline)

                Text(block.reason)
                    .font(.subheadline)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Matched tasks if available
                if !block.suggestedTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suggested commitments to tackle:")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                        ForEach(block.suggestedTasks, id: \.self) { task in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.circle")
                                    .font(.caption2)
                                    .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                                    .padding(.top, 2)
                                Text(task)
                                    .font(.caption)
                                    .foregroundStyle(SuzzmeTheme.textPrimary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                Divider()

                // Action Controls
                HStack(spacing: SuzzmeTheme.Spacing.small) {
                    if isFocusActive {
                        Button {
                            environment.stopFocusSession()
                        } label: {
                            Label("End Focus Session", systemImage: "stop.circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(SuzzmeTheme.warning)
                    } else {
                        Button {
                            environment.startFocusSession(for: block)
                        } label: {
                            Label("Start Focus Now", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SuzzmeTheme.intelligencePrimary)
                        .suzzmeProminentContrast()
                    }

                    if isScheduled {
                        HStack(spacing: SuzzmeTheme.Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("In Calendar")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        .padding(.vertical, 6)
                    } else {
                        Button {
                            scheduleBlock(block)
                        } label: {
                            if isWorking {
                                HStack(spacing: SuzzmeTheme.Spacing.xs) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Scheduling…")
                                }
                            } else {
                                Label("Add to Calendar", systemImage: "calendar.badge.plus")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isWorking)
                    }

                    NavigationLink {
                        AskSuzzmeView(
                            initialText: "Plan my day around the \(block.durationMinutes)-minute focus block from \(block.windowDescription)",
                            focusInput: false,
                            submitOnAppear: true,
                            showsDismissButton: true
                        )
                    } label: {
                        Label("Plan in Ask Suzzme", systemImage: "bubble.left.and.text.bubble.right")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func scheduleBlock(_ block: ProposedFocusBlock) {
        isSchedulingID = block.id
        scheduleError = nil
        Task {
            defer { isSchedulingID = nil }
            let success = await environment.scheduleFocusBlock(block)
            if !success {
                scheduleError = "Couldn't add to Apple Calendar. Check Calendar permission in System Settings."
            }
        }
    }
}
