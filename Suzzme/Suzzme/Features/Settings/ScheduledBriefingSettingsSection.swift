#if os(macOS)
import SwiftUI

struct ScheduledBriefingSettingsSection: View {
    @Environment(AppEnvironment.self) private var environment

    private var engine: ScheduledBriefingEngine { environment.scheduledBriefing }

    var body: some View {
        Section("Background on This Mac") {
            Toggle("Prepare Automatically", isOn: Binding(
                get: { engine.automaticPreparationEnabled },
                set: { engine.setEnabled($0) }
            ))
            .accessibilityHint("Turning this off also stops the current preparation")

            Text("Uses your Preferred Time, Calendar and Reminders you’ve already allowed, and enabled source summaries. Processing stays on this Mac; connected sources may need the internet.")
                .font(.caption)
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)


            if !environment.proactivePreferences.dailyBriefingEnabled {
                Text("Turn on Daily Summary above to prepare summaries.")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
            } else if let nextRunAt = engine.nextRunAt {
                LabeledContent("Next Preparation") {
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
            NavigationLink("View Background Tasks") { BackgroundTasksView() }

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

            Text("Continues after Home closes while Suzzme is running and your Mac is awake. On wake or relaunch, it catches up on today’s missed summary. Quitting Suzzme stops preparation. It never uses the microphone or screen, or performs actions.")
                .font(.caption)
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
