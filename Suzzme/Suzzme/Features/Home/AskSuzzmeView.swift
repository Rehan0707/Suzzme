import SwiftUI

/// Typed and spoken requests both travel through the same local Suzzme core.
struct AskSuzzmeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var result: SuzzmeUnderstandingResult?
    @State private var response: SuzzmeCoreResponse?
    @State private var isUnderstanding = false
    @State private var message: String?
    @State private var showsVoiceNotice = false

    var body: some View {
        NavigationStack {
            SuzzmePage {
                HStack(spacing: 14) {
                    SuzzmeMark().frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ask Suzzme").font(.title2.weight(.semibold))
                        Text("Share something you want help keeping track of.").foregroundStyle(.secondary)
                    }
                }

                TextEditor(text: $text)
                    .frame(minHeight: 150)
                    .padding(12)
                    .background(SuzzmeTheme.surface, in: RoundedRectangle(cornerRadius: SuzzmeTheme.cornerRadius))
                    .accessibilityLabel("Information for Suzzme to understand")

                HStack {
                    Button {
                        if environment.voice.isListening { environment.voice.stop() }
                        else { Task { await environment.startVoiceSession() } }
                    } label: {
                        Label(environment.voice.isListening ? "Stop" : "Voice", systemImage: environment.voice.isListening ? "stop.fill" : "mic")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(environment.voice.isListening ? "Stop listening" : "Start voice conversation")
                    .accessibilityHint("Speak naturally, then stop when you are done")

                    Button {
                        Task { await understand() }
                    } label: {
                        Label(isUnderstanding ? "Understanding…" : "Understand", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isUnderstanding || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let response {
                    SuzzmeCard(highlighted: response.route == .onDeviceIntelligence) {
                        Text(response.text).font(.body)
                        Text("Using \(response.contextCount) local context item(s)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let result, !result.items.isEmpty {
                    SuzzmeSectionHeader(title: "What Suzzme noticed")
                    ForEach(result.items) { item in
                        SuzzmeCard(highlighted: item.priority == .important || item.priority == .urgent) {
                            SuzzmeItemRow(item: item)
                            Text("Confidence \(item.confidence.formatted(.percent.precision(.fractionLength(0))))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button("Save to Suzzme") { save(result) }
                        .buttonStyle(.borderedProminent)
                }

                if environment.voice.isListening || !environment.voice.partialTranscript.isEmpty {
                    Text(environment.voice.partialTranscript.isEmpty ? "Listening…" : environment.voice.partialTranscript)
                        .font(.subheadline).foregroundStyle(.secondary).accessibilityLabel("Live transcription")
                }
                if let voiceMessage = environment.voice.message { Text(voiceMessage).font(.footnote).foregroundStyle(.secondary) }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }

                NavigationLink { SourcesView().navigationTitle("Intelligence Sources") } label: {
                    Label("Manage intelligence sources", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SuzzmeTheme.accent)
                }
            }
            .navigationTitle("Ask Suzzme")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: environment.voice.finalTranscript) {
            guard let transcript = environment.voice.finalTranscript, let sessionID = environment.voice.finalizedSessionID else { return }
            text = transcript
            await understandVoice(transcript, sessionID: sessionID)
        }
        .onDisappear { Task { await environment.cancelVoiceSession() } }
    }

    private func understand(speakResponse: Bool = false) async {
        isUnderstanding = true
        message = nil
        defer { isUnderstanding = false }
        do {
            response = try await environment.askSuzzme(text, speakResponse: speakResponse)
            result = environment.lastUnderstandingResult
            if result?.items.isEmpty == true { message = "Suzzme did not find a new item to save." }
        } catch is CancellationError {
            message = "Understanding was cancelled."
        } catch {
            message = error.localizedDescription
        }
    }

    private func understandVoice(_ transcript: String, sessionID: UUID) async {
        isUnderstanding = true
        message = nil
        defer { isUnderstanding = false }
        do {
            response = try await environment.submitVoiceTranscript(transcript, sessionID: sessionID)
            result = environment.lastUnderstandingResult
        } catch is CancellationError {
            // A newer typed or voice request owns the assistant now.
        } catch {
            message = error.localizedDescription
        }
    }

    private func save(_ result: SuzzmeUnderstandingResult) {
        do {
            let count = try environment.saveUnderstandingResult(result)
            message = count == 1 ? "Saved to Suzzme." : "Nothing new was saved."
        } catch {
            message = error.localizedDescription
        }
    }
}
