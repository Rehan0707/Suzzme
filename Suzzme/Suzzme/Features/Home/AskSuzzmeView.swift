import SwiftUI

/// Typed and spoken requests both travel through the same local Suzzme core.
struct AskSuzzmeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var text = ""
    @State private var result: SuzzmeUnderstandingResult?
    @State private var response: SuzzmeCoreResponse?
    @State private var isUnderstanding = false
    @State private var message: String?
    @State private var readAnswerAloud = false
    @FocusState private var inputFocused: Bool

    init(initialText: String = "") {
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            SuzzmePage {
                VStack(spacing: SuzzmeTheme.Spacing.medium) {
                    SuzzmeFace(state: environment.presenceState, color: environment.invocation.presenceTheme.colors(for: colorScheme).face, lineWidth: 4, animation: environment.invocation.presenceAnimation)
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                    VStack(spacing: 4) {
                        Text(environment.presenceState == .idle ? "What’s on your mind?" : SuzzmeAssistantPresentation.make(for: environment.presenceState).title).font(.title2.weight(.semibold))
                        if environment.presenceState == .idle {
                            Text("Type or speak naturally.").foregroundStyle(SuzzmeTheme.textSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

                if !environment.voice.isListening && ![.listening, .transcribing, .speaking].contains(environment.presenceState) {
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 150)
                    .padding(SuzzmeTheme.Spacing.small)
                    .background(SuzzmeTheme.controlFill, in: RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.control, style: .continuous))
                    .focused($inputFocused)
                    .accessibilityLabel("Information for Suzzme to understand")
                    .accessibilityHint("Type a question or follow-up")
                }

                SuzzmeActionControls {
                    Button {
                        if environment.voice.isListening { environment.voice.stop() }
                        else { Task { await environment.startVoiceSession() } }
                    } label: {
                        Label(environment.voice.isListening ? "Finish speaking" : environment.presenceState == .speaking ? "Interrupt and talk" : "Voice", systemImage: environment.voice.isListening ? "checkmark" : "mic")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(environment.voice.isListening ? "Finish speaking and send" : environment.presenceState == .speaking ? "Interrupt the answer and start listening" : "Start voice conversation")
                    .accessibilityHint(environment.voice.isListening ? "Sends the words you have spoken to Suzzme" : "Speak naturally, then finish when you are done")

                    if environment.voice.isListening || environment.presenceState == .speaking {
                        Button(environment.voice.isListening ? "Cancel recording" : "Cancel conversation", role: .cancel) {
                            response = nil
                            result = nil
                            Task { await environment.cancelVoiceSession() }
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        inputFocused = false
                        Task { await understand() }
                    } label: {
                        Label(isUnderstanding ? "Understanding…" : "Send", systemImage: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .suzzmeProminentContrast()
                    .disabled(isUnderstanding || environment.voice.isListening || environment.presenceState == .speaking || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !environment.voice.isListening && environment.presenceState != .speaking {
                    Toggle("Read this conversation’s answers aloud", isOn: $readAnswerAloud)
                        .disabled(!environment.voice.speaksResponses)
                    if !environment.voice.speaksResponses {
                        Text("Enable spoken responses in Voice settings to hear answers.")
                            .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                }

                if let response {
                    SuzzmeCard(highlighted: response.route == .onDeviceIntelligence) {
                        Text(response.text).font(.body)
                        if response.contextCount > 0 {
                            Label("Checked your local context", systemImage: "checkmark.shield")
                                .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                        }
                    }
                }

                if let action = response?.action, action.status == .awaitingConfirmation {
                    SuzzmeCard(highlighted: true) {
                        SuzzmeConfirmationSummary(
                            title: action.title,
                            destructive: [.deleteReminder, .deleteCalendarEvent, .forgetMemory].contains(action.type)
                        )
                        SuzzmeActionControls {
                            Button("Cancel", role: .cancel) {
                                text = "cancel"
                                Task { await understand(confirmationActionID: action.id, submittedText: "cancel") }
                            }
                            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                            Button(action.type.confirmationLabel, role: [.deleteReminder, .deleteCalendarEvent, .forgetMemory].contains(action.type) ? .destructive : nil) {
                                text = "confirm"
                                Task { await understand(confirmationActionID: action.id, submittedText: "confirm") }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint([.deleteReminder, .deleteCalendarEvent, .forgetMemory].contains(action.type) ? .red : SuzzmeTheme.accent)
                    .suzzmeProminentContrast()
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .disabled(isUnderstanding)
                    .accessibilityLabel("Action confirmation: \(action.title)")
                }

                if let result, !result.items.isEmpty {
                    SuzzmeSectionHeader(title: "What Suzzme noticed")
                    ForEach(result.items) { item in
                        SuzzmeCard(highlighted: item.priority == .important || item.priority == .urgent) {
                            SuzzmeItemRow(item: item)
                        }
                    }
                    Button("Save to Suzzme") { save(result) }
                        .buttonStyle(.borderedProminent)
                    .suzzmeProminentContrast()
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
#if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Dismiss Keyboard") { inputFocused = false }
                }
#endif
            }
        }
        .onAppear {
            if environment.presenceState == .awaitingConfirmation || environment.presenceState == .speaking {
                response = environment.lastVoiceResponse
                result = environment.lastUnderstandingResult
            }
        }
        .onChange(of: environment.voice.finalizedSessionID) { _, _ in
            text = environment.voice.finalTranscript ?? text
        }
        .onChange(of: environment.lastVoiceResponseRevision) { _, _ in
            response = environment.lastVoiceResponse
            result = environment.lastUnderstandingResult
        }
        .onDisappear {
            let requestID = environment.currentInteractionID
            Task { await environment.dismissInteraction(requestID) }
        }
    }


    private func understand(speakResponse: Bool = false, confirmationActionID: UUID? = nil, submittedText: String? = nil) async {
        guard !isUnderstanding else { return }
        isUnderstanding = true
        message = nil
        defer { isUnderstanding = false }
        do {
            response = try await environment.askSuzzme(submittedText ?? text, speakResponse: speakResponse || readAnswerAloud, confirmationActionID: confirmationActionID)
            result = environment.lastUnderstandingResult
        } catch is CancellationError {
            message = "Understanding was cancelled."
        } catch {
            message = "Suzzme couldn’t understand that request. Nothing was changed."
        }
    }

    private func save(_ result: SuzzmeUnderstandingResult) {
        do {
            let count = try environment.saveUnderstandingResult(result)
            message = count == 1 ? "Saved to Suzzme." : "Nothing new was saved."
        } catch {
            message = "That item couldn’t be saved. Please try again."
        }
    }
}

extension SuzzmeActionType {
    var confirmationLabel: String {
        switch self {
        case .createReminder: "Create Reminder"
        case .updateReminder: "Update Reminder"
        case .completeReminder: "Complete Reminder"
        case .deleteReminder: "Delete Reminder"
        case .createCalendarEvent: "Create Event"
        case .updateCalendarEvent: "Update Event"
        case .deleteCalendarEvent: "Delete Event"
        case .forgetMemory: "Forget Memory"
        case .openApp: "Open App"
        case .openFile: "Open File"
        case .draftMessage: "Prepare Draft"
        case .sendMessage: "Send Message"
        case .runShortcut: "Run Shortcut"
        }
    }
}
