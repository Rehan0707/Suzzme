#if DEBUG
import SwiftUI

enum BrainLabSamples {
    static let inputs = [
        "Hey everyone, registrations for the university coding competition close tomorrow at 5 PM. Submit the registration form before the deadline.",
        "Tomorrow's Apple Developer Club meeting will begin at 11 AM in Lab 2.",
        "The new lab received six Macs this semester.",
        "Please submit the project report before Friday.",
        "Last year's coding competition was held in October."
    ]
}

struct SuzzmeBrainLabView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var text = BrainLabSamples.inputs[0]
    @State private var result: SuzzmeUnderstandingResult?
    @State private var capability: IntelligenceCapability?
    @State private var isUnderstanding = false
    @State private var statusMessage: String?

    var body: some View {
        SuzzmePage {
            SuzzmeEmptyState(
                symbol: "brain",
                title: "Suzzme Brain Lab",
                message: "Paste something Suzzme should understand. This debug tool keeps input in memory and saves only the structured items you choose."
            )

            Menu("Load a sample") {
                ForEach(Array(BrainLabSamples.inputs.enumerated()), id: \.offset) { index, sample in
                    Button("Test \(index + 1)") { text = sample }
                }
            }
            .buttonStyle(.bordered)

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 160)
                .padding(12)
                .background(SuzzmeTheme.surface, in: RoundedRectangle(cornerRadius: SuzzmeTheme.cornerRadius))
                .accessibilityLabel("Text for Suzzme to understand")

            if let capability {
                Label(capability.displayDescription, systemImage: capability.usesFoundationModels ? "sparkles" : "text.magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await understand() }
            } label: {
                Label(isUnderstanding ? "Understanding…" : "Understand", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isUnderstanding || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let result {
                SuzzmeSectionHeader(title: "Detected items")
                ForEach(result.items) { item in
                    BrainLabItemCard(item: item, reason: result.reason(for: item))
                }
                if result.items.isEmpty {
                    Text("No new items were found. \(result.skippedDuplicateCount) duplicate item(s) were skipped.")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Save to Suzzme") { save(result) }
                        .buttonStyle(.borderedProminent)
                }
            }

            if let statusMessage {
                Text(statusMessage).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Brain Lab")
        .task { capability = await environment.intelligenceCapability() }
    }

    private func understand() async {
        isUnderstanding = true
        statusMessage = nil
        defer { isUnderstanding = false }
        do {
            result = try await environment.understand(text: text)
            statusMessage = result?.skippedDuplicateCount == 0 ? nil : "Duplicate items are not shown."
        } catch is CancellationError {
            statusMessage = "Understanding was cancelled."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func save(_ result: SuzzmeUnderstandingResult) {
        do {
            let count = try environment.saveUnderstandingResult(result)
            statusMessage = count == 0 ? "Nothing new was saved." : "Saved \(count) item\(count == 1 ? "" : "s") to Suzzme."
        } catch {
            statusMessage = "Couldn’t save the extracted items."
        }
    }
}

private struct BrainLabItemCard: View {
    let item: SuzzmeItem
    let reason: String

    var body: some View {
        SuzzmeCard(highlighted: item.priority == .important || item.priority == .urgent) {
            HStack {
                SuzzmePriorityBadge(priority: item.priority)
                Spacer()
                Text(item.category.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
            }
            Text(item.title).font(.headline)
            Text(item.summary).foregroundStyle(.secondary)
            dueDateView
            Text(confidenceText).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var dueDateView: some View {
        if let dueDate = item.dueDate {
            Label {
                Text(dueDate, format: .dateTime.weekday().month().day().hour().minute())
            } icon: {
                Image(systemName: "calendar")
            }
                .font(.subheadline).foregroundStyle(SuzzmeTheme.accent)
        } else {
            Text("No reliable due date").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var confidenceText: String {
        "Confidence \(item.confidence.formatted(.percent.precision(.fractionLength(0)))) · \(reason)"
    }
}
#endif
