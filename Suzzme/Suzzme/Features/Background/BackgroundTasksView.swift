#if os(macOS)
import SwiftUI

/// A secondary view over the app-owned scheduler and its bounded receipts.
/// Opening or closing this view does not start, stop, or refresh the worker.
struct BackgroundTasksView: View {
    @Environment(AppEnvironment.self) private var environment

    private var engine: ScheduledBriefingEngine { environment.scheduledBriefing }
    private var status: BackgroundPreparationStatus {
        .init(readiness: engine.readiness, isRunning: engine.isRunning,
              isStopping: engine.isStopping,
              automaticPreparationEnabled: engine.automaticPreparationEnabled,
              hasError: engine.errorMessage != nil, hasNextRun: engine.nextRunAt != nil)
    }
    private var history: [ScheduledBriefingReceipt] {
        engine.receipts.filter { $0.id != engine.currentReceipt?.id }
    }
    private var canPrepare: Bool {
        engine.canRunNow && !environment.isPreparingBriefing
    }

    var body: some View {
        List {
            Section {
                SuzzmeScreenIntroduction(
                    title: "Background on this Mac",
                    message: "See what Suzzme is preparing and what finished recently."
                )
                .padding(.vertical, SuzzmeTheme.Spacing.xs)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section("Daily Summary") {
                currentStatus

                Toggle(isOn: Binding(
                    get: { engine.automaticPreparationEnabled },
                    set: { engine.setEnabled($0) }
                )) {
                    Text("Prepare Automatically")
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget, alignment: .leading)
                }
                .accessibilityHint("Uses your Daily Summary Preferred Time while Suzzme is running on this Mac. Turning it off also stops the current preparation.")

                if let nextRunAt = engine.nextRunAt {
                    LabeledContent("Next Preparation") {
                        Text(nextRunAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .multilineTextAlignment(.trailing)
                    }
                }

                preparationControls
            }

            if let errorMessage = engine.errorMessage {
                Section("Needs attention") {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                    if engine.enabled && !engine.automaticPreparationEnabled {
                        Button {
                            engine.setEnabled(false)
                        } label: {
                            Text("Save Off Setting Again")
                                .frame(minHeight: SuzzmeTheme.Layout.touchTarget, alignment: .leading)
                        }
                        .accessibilityHint("Saves automatic preparation as off without turning it on")
                    }
                }
            }

            Section {
                if history.isEmpty {
                    SuzzmeEmptyState(
                        symbol: "clock.arrow.circlepath",
                        title: engine.isRunning ? "No earlier preparations" : "No preparation history yet",
                        message: "Recent preparation results will appear here. Use Prepare Now when you’re ready."
                    )
                } else {
                    ForEach(history) { receipt in
                        BackgroundPreparationReceiptRow(
                            receipt: receipt,
                            retryScheduled: engine.isRetryScheduled(for: receipt)
                        )
                    }
                }
            } header: {
                Text("Recent preparations")
            } footer: {
                Text("History shows results, not summary text or source details.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Open") {
                NavigationLink { BriefingView() } label: {
                    Text("Read Current Daily Summary")
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget, alignment: .leading)
                }
                NavigationLink { ProactiveIntelligenceSettingsView() } label: {
                    Text("Daily Summary Settings")
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget, alignment: .leading)
                }
            }

            Section("How it runs") {
                Text("Uses Calendar, Reminders, and enabled source summaries you’ve already allowed. Processing stays on this Mac; connected sources may need the internet.")
                Text("Continues after Home closes while Suzzme is running and your Mac is awake. On wake or relaunch, it catches up on today’s missed summary. Quitting Suzzme stops preparation.")
                Text("Background preparation never uses the microphone or screen, or performs actions.")
            }
            .font(.subheadline)
            .foregroundStyle(SuzzmeTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .suzzmeReadableList()
        .navigationTitle("Background Tasks")
    }

    private var currentStatus: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
            if status.showsProgress {
                ProgressView(status.title)
                    .accessibilityLabel(status.title)
            } else {
                SuzzmeStateLabel(title: status.title, symbol: status.symbol)
            }
            Text(status.message)
                .font(.subheadline)
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let receipt = engine.currentReceipt {
                Text(receipt.slot.manualRequestID == nil ? "Automatic preparation" : "Requested by you")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                Text("Started \(receipt.startedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
            }
        }
        .padding(.vertical, SuzzmeTheme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var preparationControls: some View {
        if engine.isRunning {
            Button {
                engine.cancelCurrentRun()
            } label: {
                Text(engine.isStopping ? "Stopping…" : "Stop Preparation")
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget, alignment: .leading)
            }
            .disabled(engine.isStopping)
            .accessibilityHint("Stops this preparation. Automatic preparation keeps its current setting.")
        } else {
            Button {
                Task { await engine.runNow() }
            } label: {
                Text("Prepare Now")
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget, alignment: .leading)
            }
            .disabled(!canPrepare)
            .accessibilityHint("Prepares the current Daily Summary using sources you’ve already allowed")
            if !canPrepare, engine.readiness == .ready, environment.isPreparingBriefing {
                Text("A Daily Summary is already being prepared. Try again when it finishes.")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("Background Tasks") {
    NavigationStack { BackgroundTasksView() }
        .environment(AppEnvironment.preview)
}
#endif
