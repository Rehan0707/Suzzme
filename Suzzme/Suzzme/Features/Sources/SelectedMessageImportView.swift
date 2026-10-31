import SwiftUI
import UniformTypeIdentifiers

struct SelectedMessageImportView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedText = ""
    @State private var feedback: String?
    @State private var isImporting = false
    @State private var confirmsRemoval = false
    @State private var showingTextFile = false
    @State private var isReadingFile = false
    @State private var isSummarizing = false
    @State private var preparedSummary: String?
    private var exceedsImportLimit: Bool { selectedText.trimmingCharacters(in: .whitespacesAndNewlines).count > InformationLimits.selectedMessageCharacters }
    private var canSummarize: Bool { !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedText.count <= 24_000 }

    private var importedMessageCount: Int {
        environment.informationEvents.filter { $0.source == .messages }.count
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
                Text("Copy text from Messages or another app, or open an exported plain-text chat. Review what you select before Suzzme uses it.")
                    .font(.subheadline)
                    .foregroundStyle(SuzzmeTheme.textSecondary)

                TextEditor(text: $selectedText)
                    .frame(minHeight: 110)
                    .padding(SuzzmeTheme.Spacing.xs)
                    .overlay {
                        RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.control, style: .continuous)
                            .stroke(SuzzmeTheme.separator, lineWidth: SuzzmeTheme.hairline)
                    }
                    .accessibilityLabel("Selected message text")
                Button(isReadingFile ? "Opening text…" : "Open text file for review") { showingTextFile = true }
                    .buttonStyle(.bordered)
                    .disabled(isReadingFile || isImporting)

                if exceedsImportLimit {
                    Text("Choose an excerpt of at most \(InformationLimits.selectedMessageCharacters) characters. Nothing has been imported or silently cut off.")
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                }

                Button(isSummarizing ? "Summarizing on this device…" : "Prepare short summary on this device") {
                    prepareSummary()
                }
                .buttonStyle(.bordered)
                .disabled(!canSummarize || isSummarizing || isImporting || isReadingFile)
                if selectedText.count > 24_000 {
                    Text("Choose up to 24,000 characters for an on-device summary. The text will not be cut off silently.")
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                }
                if let preparedSummary {
                    Text("Review this summary before importing it")
                        .font(.headline)
                    Text(preparedSummary)
                        .font(.subheadline)
                        .textSelection(.enabled)
                    Button("Use reviewed summary") {
                        selectedText = preparedSummary
                        self.preparedSummary = nil
                        feedback = "Review the short text, then choose Import selected text."
                    }
                    .buttonStyle(.bordered)
                }

                SuzzmeActionControls {
                    Text("\(selectedText.count)/\(InformationLimits.selectedMessageCharacters)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                    Button(isImporting ? "Importing…" : "Import selected text") {
                        importMessage()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SuzzmeTheme.intelligencePrimary)
                    .suzzmeProminentContrast()
                    .disabled(selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || exceedsImportLimit || isImporting || isReadingFile)
                }

                if let feedback {
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                }

                InformationSourceControls(source: .messages)

                if importedMessageCount > 0 {
                    Button("Remove imported messages", role: .destructive) {
                        confirmsRemoval = true
                    }
                }
                Text("This does not connect a messaging account or read live content. Exported chat text is summarized only when you choose; the raw export is not saved by Suzzme. Text files up to 64 KB open for review. Approved excerpts stay on this device for up to 7 days and can be removed here. Original message dates are not inferred from the import time.")
                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, SuzzmeTheme.Spacing.xs)
        } header: {
            Text("Text you share")
        } footer: {
            Text("Manual sharing · Processed on this device")
        }
        .fileImporter(isPresented: $showingTextFile, allowedContentTypes: [.plainText]) { result in
            switch result {
            case .success(let url):
                isReadingFile = true
                Task {
                    do {
                        let text = try await Task.detached(priority: .userInitiated) { try SelectedMessageTextFile.preview(url) }.value
                        selectedText = text
                        feedback = "Opened for review. Choose a short excerpt or prepare an on-device summary."
                    } catch { feedback = "Choose a nonempty UTF-8 or UTF-16 text file no larger than 64 KB. Nothing was imported." }
                    isReadingFile = false
                }
            case .failure:
                feedback = "The file could not be opened. Nothing was imported."
            }
        }
        .confirmationDialog("Remove all imported message text?", isPresented: $confirmsRemoval) {
            Button("Remove imported messages", role: .destructive) {
                Task {
                    let removed = await environment.removeImportedMessages()
                    feedback = removed ? "Imported messages were removed from this device." : environment.informationError
                }
            }
        }
        .onChange(of: selectedText) { _, _ in preparedSummary = nil }
    }

    private func prepareSummary() {
        let text = selectedText
        isSummarizing = true
        feedback = nil
        Task {
            let summary = await environment.summarizeSelectedConversation(text)
            if selectedText == text { preparedSummary = summary }
            if summary == nil { feedback = environment.informationError ?? "The summary could not be prepared." }
            isSummarizing = false
        }
    }

    private func importMessage() {
        let text = selectedText
        isImporting = true
        Task {
            let result = await environment.importSelectedMessage(text)
            switch result {
            case .imported:
                selectedText = ""
                feedback = "Imported on this device for recent summaries."
            case .rejected:
                feedback = "Skipped because this text matched a protected-data rule."
            case .unavailable:
                feedback = environment.informationError ?? "The message could not be imported. Please try again."
            }
            isImporting = false
        }
    }
}
