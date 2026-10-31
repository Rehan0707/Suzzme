#if os(macOS)
import SwiftUI

struct ScheduledBriefingSettingsSection: View {
    @Environment(AppEnvironment.self) private var environment

    private var engine: ScheduledBriefingEngine { environment.scheduledBriefing }

    var body: some View {
        Section("Automatic preparation on this Mac") {
            Toggle("Prepare Automatically", isOn: Binding(
                get: { engine.automaticPreparationEnabled },
                set: { engine.setEnabled($0) }
            ))
            .accessibilityHint("Turning this off also stops the current preparation")

            Text("Uses your preferred time and sources you’ve enabled. Your data stays on this Mac; connected sources may need the internet.")
                .font(.caption)
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !environment.proactivePreferences.dailyBriefingEnabled {
                Text("Turn on Daily Summary above to prepare summaries.")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
            } else if let nextRunAt = engine.nextRunAt {
                LabeledContent("Next summary") {
                    Text(nextRunAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .multilineTextAlignment(.trailing)
                }
            }

            if engine.isRunning {
                ProgressView(engine.isStopping ? "Stopping Preparation…" : "Preparing Daily Summary…")
                Button("Stop Preparation") { engine.cancelCurrentRun() }
                    .disabled(engine.isStopping)
            } else {
                Button("Prepare Now") { Task { await engine.runNow() } }
                    .disabled(!engine.canRunNow || environment.isPreparingBriefing)
            }

                NavigationLink("Read Daily Summary") { BriefingView() }
            NavigationLink("View preparation activity") { BackgroundTasksView() }

            if let errorMessage = engine.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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

            DisclosureGroup("How automatic preparation works") {
                Text("Preparation continues while Suzzme is running and your Mac is awake. After sleep or relaunch, it catches up on today’s missed summary. Quitting Suzzme stops preparation. It never uses the microphone or screen, or performs actions.")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
#endif
