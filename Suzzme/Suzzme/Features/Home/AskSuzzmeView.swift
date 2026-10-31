import SwiftUI
import OSLog

#if os(macOS)
private struct SuzzmeAssistantSheetSizing: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.presentationSizing(.fitted)
        } else {
            content
        }
    }
}
#endif

/// One presentation for typed and spoken requests through the existing core.
struct AskSuzzmeView: View {
    private static let submissionLog = Logger(subsystem: "Suzzme", category: "Submission")
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var text = ""
    @State private var conversation = SuzzmeConversationPresentation()
    @State private var conversationID: UUID? = UUID()
    @State private var capability: IntelligenceCapability?
    @State private var requestRevision = UUID()
    @State private var activeEntryID: UUID?
    @State private var ownedVoiceSessionID: UUID?
    @State private var voiceEntryID: UUID?
    @State private var focusRequest: UUID?
    @State private var followsConversation = true
    @State private var scrollToLatest = false
    @State private var didStartInitialInteraction = false
    @State private var submittedQuestion = ""
    @State private var result: SuzzmeUnderstandingResult?
    @State private var response: SuzzmeCoreResponse?
    @State private var isUnderstanding = false
    @State private var isStartingVoice = false
    @State private var message: String?
    @AppStorage("suzzme.voice.readAnswersAloud") private var readAnswerAloud = true
    @State private var connectionSuggestion: IntegrationConnectionSuggestion?
    @State private var connectionSuggestionOwner: UUID?
    @State private var showsGitHubConnection = false
    @State private var presentationOwnership = AskSuzzmePresentationOwnership()
    @State private var requestTask: Task<Void, Never>?
    @FocusState private var inputFocused: Bool
    private let focusInput: Bool
    private let submitOnAppear: Bool
    private let startVoiceOnAppear: Bool
    private let showsDismissButton: Bool
    private let usesParentNavigationStack: Bool

    init(initialText: String = "", focusInput: Bool = false, submitOnAppear: Bool = false,
         startVoiceOnAppear: Bool = false, showsDismissButton: Bool = true,
         usesParentNavigationStack: Bool = false) {
        _text = State(initialValue: initialText)
        self.focusInput = focusInput || !initialText.isEmpty
        self.submitOnAppear = submitOnAppear
        self.startVoiceOnAppear = startVoiceOnAppear
        self.showsDismissButton = showsDismissButton
        self.usesParentNavigationStack = usesParentNavigationStack
    }

    private var isProcessing: Bool {
        [.transcribing, .understanding, .gatheringContext, .reasoning, .planning, .acting].contains(environment.presenceState) || isUnderstanding || isStartingVoice
            || (environment.voice.isPreparingSpeech && !environment.voice.isPreviewing)
    }
    private var isListeningPresentation: Bool { environment.voice.isListening }
    private var focusedSession: Bool { isListeningPresentation || isProcessing || environment.presenceState == .speaking }
    private var awaitsAction: Bool {
        guard let action = response?.action else { return false }
        return action.status == .awaitingConfirmation && environment.presentedAction?.id == action.id
            && environment.presentedActionOwner == presentationOwnership.requestID
    }
    private var ownsCurrentInteraction: Bool {
        guard let owner = presentationOwnership.requestID else { return false }
        return environment.currentInteractionID == owner
    }
    private var canCompose: Bool {
        !focusedSession && !awaitsAction && environment.screenConsentRequestID == nil
    }
    private var voiceTurnIsWaitingForResponse: Bool {
        guard let owner = ownedVoiceSessionID,
              owner == presentationOwnership.requestID,
              ownsCurrentInteraction else { return false }
        if isStartingVoice { return true }
        guard environment.voice.sessionID == owner else { return false }
        return environment.voice.isFinalizing || [
            .transcribing, .understanding, .gatheringContext, .reasoning,
            .planning, .acting, .speaking
        ].contains(environment.presenceState)
    }

    var body: some View {
        Group {
            if usesParentNavigationStack {
                conversationNavigationContent
            } else {
                NavigationStack { conversationNavigationContent }
            }
        }
        #if os(macOS)
        .focusedSceneValue(\.assistantPresentation, .constant(true))
        .frame(minWidth: usesParentNavigationStack ? 0 : SuzzmeTheme.Layout.assistantMinimumWidth,
               idealWidth: usesParentNavigationStack ? nil : SuzzmeTheme.Layout.readingWidth,
               minHeight: usesParentNavigationStack ? 0 : 560)
        .modifier(SuzzmeAssistantSheetSizing())
        #endif
        .sheet(isPresented: $showsGitHubConnection) {
            NavigationStack {
                ComposioIntegrationsView(initialServiceID: "github",
                    initialResource: connectionSuggestion?.resourceURL,
                    initialQuestion: submittedQuestion)
                    .environment(environment)
            }
        }
        .onChange(of: environment.currentInteractionID) { _, newOwner in
            if connectionSuggestionOwner != newOwner { connectionSuggestion = nil }
            if ownedVoiceSessionID != nil, !presentationOwnership.isKnownRequest(newOwner),
               let entryID = activeEntryID,
               let entry = conversation.entries.first(where: { $0.id == entryID }) {
                _ = conversation.fail("This voice request ended or was replaced by a newer request.",
                    entryID: entryID, requestID: entry.requestID, cancelled: true)
                activeEntryID = nil
            }
        }
        .onChange(of: environment.integrations.accounts) { _, accounts in
            guard let owner = connectionSuggestionOwner, owner == environment.currentInteractionID else { return }
            connectionSuggestion = IntegrationConnectionSuggestion.make(question: submittedQuestion, accounts: accounts)
        }
        .onAppear {
            if !submitOnAppear, !startVoiceOnAppear, let owner = environment.currentInteractionID,
               owner == environment.voice.sessionID {
                conversationID = environment.currentConversationID
            }
            conversation.purgeExpired()
            presentationOwnership.captureInitialRequest(environment.currentInteractionID, confirmationOwner: environment.presentedActionOwner)
            if environment.currentInteractionID == environment.voice.sessionID {
                ownedVoiceSessionID = environment.voice.sessionID
            }
            if let initial = environment.lastVoiceResponse, initial.text == environment.presentedResponse,
               ownsCurrentInteraction, let owner = presentationOwnership.requestID, conversation.entries.isEmpty,
               [.awaitingConfirmation, .speaking, .success].contains(environment.presenceState) {
                response = initial
                result = environment.lastUnderstandingResult
                let question = ownedVoiceSessionID == environment.voice.finalizedSessionID ? environment.voice.finalTranscript ?? "" : ""
                let entryID = conversation.append(question: question, requestID: owner)
                _ = conversation.complete(initial, entryID: entryID, requestID: owner)
            }
        }
        .task {
            guard !Task.isCancelled, !didStartInitialInteraction else { return }
            didStartInitialInteraction = true
            if startVoiceOnAppear { startVoiceRequest() }
            else if submitOnAppear && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sendTypedRequest(replacingCurrent: true)
            }
            capability = await environment.intelligenceCapability()
        }
        .onChange(of: environment.voice.finalizedSessionID) { _, _ in captureOwnedVoiceTranscript() }
        .onChange(of: environment.lastVoiceResponseRevision) { _, _ in receiveOwnedVoiceResponse() }
        .onChange(of: environment.presenceState) { _, state in
            if state == .error, ownsCurrentInteraction, ownedVoiceSessionID == environment.voice.sessionID {
                captureOwnedVoiceTranscript()
                if environment.voice.finalizedSessionID == nil {
                    focusRequest = UUID()
                    inputFocused = true
                }
                if let entryID = voiceEntryID, let sessionID = ownedVoiceSessionID {
                    _ = conversation.fail(environment.assistant.message ?? "The voice request could not finish.",
                        entryID: entryID, requestID: sessionID)
                    activeEntryID = nil
                }
            }
        }
        .onDisappear {
            requestRevision = UUID()
            requestTask?.cancel()
            let requestID = presentationOwnership.requestID
            Task { await environment.dismissInteraction(requestID) }
        }
    }

    private var conversationNavigationContent: some View {
            ScrollViewReader { proxy in
                SuzzmeAssistantConversationScroll(followsConversation: $followsConversation) {
                    conversationPresence
                    availabilityNotice
                    if conversation.entries.isEmpty && !focusedSession {
                        SuzzmeScreenIntroduction(title: "What’s on your mind?",
                            message: "Ask about your day, think something through, or share something you’d like Suzzme to remember.")
                    }
                    ForEach(conversation.entries) { entry in conversationEntry(entry) }
                    liveVoicePresentation
                    screenConsent
                    actionConfirmation
                    connectionInvitation
                    noticedItems
                    if let voiceMessage = environment.voice.message {
                        SuzzmeAssistantNotice(symbol: "mic.slash", title: "Voice needs attention", message: voiceMessage)
                        NavigationLink("Review voice settings") { VoiceSettingsView() }
                            .frame(minHeight: SuzzmeTheme.Layout.touchTarget, alignment: .leading)
                    }
                    if let message {
                        SuzzmeAssistantNotice(symbol: "info.circle", title: "Conversation", message: message)
                    }
                    if focusedSession && !ownsCurrentInteraction {
                        SuzzmeAssistantNotice(symbol: "waveform", title: "Suzzme is active elsewhere",
                            message: "Finish or cancel using the control that started this request. Your conversation stays here.")
                    }
                    if dynamicTypeSize.isAccessibilitySize { interactionControls }
                }
                .onChange(of: conversation.revision) { _, _ in
                    guard followsConversation || scrollToLatest else { return }
                    scrollToLatest = false
                    withAnimation(SuzzmeTheme.Motion.disclosure(reduceMotion: reduceMotion)) {
                        proxy.scrollTo("assistant-conversation-bottom", anchor: .bottom)
                    }
                }
                .overlay(alignment: .bottom) {
                    if !followsConversation && !conversation.entries.isEmpty {
                        Button {
                            withAnimation(SuzzmeTheme.Motion.disclosure(reduceMotion: reduceMotion)) {
                                proxy.scrollTo("assistant-conversation-bottom", anchor: .bottom)
                            }
                        } label: {
                            Label("Latest message", systemImage: "arrow.down")
                                .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Return to the end of this conversation")
                        .accessibilityIdentifier("suzzme-assistant-latest")
                        .padding(.bottom, SuzzmeTheme.Spacing.small)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !dynamicTypeSize.isAccessibilitySize { interactionControls }
                }
            }
            .navigationTitle("Ask Suzzme")
            .tint(SuzzmeTheme.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if showsDismissButton {
                        Button("Done", action: finishVoiceOrDismiss)
                            .keyboardShortcut(.cancelAction)
                            .disabled(voiceTurnIsWaitingForResponse && !environment.voice.isListening)
                            .accessibilityLabel(environment.voice.isListening ? "Finish speaking and send" : "Done")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Group {
                        #if os(iOS)
                        NavigationLink { MobileMacSourcesView() } label: {
                            Label("Mac Sources", systemImage: "tray.2")
                        }
                        #else
                        NavigationLink { SourcesView().navigationTitle("Sources") } label: {
                            Label("Sources", systemImage: "tray.2")
                        }
                        #endif
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Review sources")
                    .help("Review sources")
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Dismiss Keyboard") { inputFocused = false; focusRequest = nil }
                }
                #endif
            }
    }

    private var availabilityNotice: some View {
        Group {
            #if os(iOS)
            if environment.companionSummary != nil {
                Label("Ask about your Mac-prepared day. Detailed Mac source reads remain on your Mac.",
                      systemImage: "desktopcomputer")
                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            #endif
            if let capability {
                if capability == .available {
                    Label(capability.displayDescription, systemImage: "apple.intelligence")
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                } else {
                    SuzzmeAssistantNotice(symbol: "apple.intelligence", title: "On-device model unavailable",
                        message: capability.displayDescription + " You can still use supported local context and actions.")
                }
            } else {
                Label("Checking on-device intelligence…", systemImage: "apple.intelligence")
                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
            }
        }
    }

    private func conversationEntry(_ entry: SuzzmeConversationEntry) -> some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            if !entry.question.isEmpty {
                SuzzmeConversationMessageRow(role: .user, text: entry.question)
                    .accessibilityIdentifier("suzzme-turn-\(entry.id.uuidString)-user")
            }
            if let answer = entry.response {
                SuzzmeConversationMessageRow(role: .assistant, text: answer.text).draggable(answer.text)
                    .accessibilityIdentifier("suzzme-turn-\(entry.id.uuidString)-assistant")
                SuzzmeResponseAttribution(route: answer.route, contextCount: answer.contextCount)
                SuzzmeActionControls {
                    ShareLink(item: answer.text) { Label("Share", systemImage: "square.and.arrow.up") }
                    Button {
                        environment.voice.speak(answer.text)
                    } label: { Label("Read aloud", systemImage: "speaker.wave.2") }
                    .disabled(!environment.voice.speaksResponses || focusedSession || awaitsAction || environment.screenConsentRequestID != nil)
                }
                .font(.caption).buttonStyle(.borderless).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            if let failure = entry.failure {
                SuzzmeAssistantNotice(symbol: entry.wasCancelled ? "stop.circle" : "exclamationmark.triangle",
                    title: entry.wasCancelled ? "Request cancelled" : "Couldn’t complete this request", message: failure,
                    isWarning: !entry.wasCancelled)
                SuzzmeActionControls {
                    if let question = conversation.retryQuestion(for: entry.id) {
                        Button("Try again") { sendTypedRequest(question: question) }
                            .disabled(!canCompose)
                    }
                    Button("Edit question") { text = entry.question; focusRequest = UUID() }
                        .disabled(!canCompose)
                }
                .buttonStyle(.bordered)
            }
        }
        .id(entry.id)
    }

    @ViewBuilder private var liveVoicePresentation: some View {
        if ownedVoiceSessionID == environment.voice.sessionID, ownsCurrentInteraction,
           isListeningPresentation || !environment.voice.partialTranscript.isEmpty && isProcessing {
            SuzzmeCard {
                if environment.voice.isListening {
                    SuzzmeListeningField(level: environment.voice.audioLevel,
                        color: SuzzmePresenceColors.mascot(for: colorScheme).primary,
                        animation: environment.invocation.presenceAnimation).frame(maxWidth: 140)
                }
                Text(environment.voice.partialTranscript.isEmpty ? "Go ahead. I’m listening." : environment.voice.partialTranscript)
                    .font(.body).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(environment.voice.partialTranscript.isEmpty ? "Go ahead. I’m listening." : "Live transcription: \(environment.voice.partialTranscript)")
            }
        }
    }

    private var conversationPresence: some View {
        SuzzmeAssistantStatusIndicator(state: environment.presenceState,
            statusMessage: environment.voice.isPreparingSpeech ? "Preparing voice on this device…"
                : isStartingVoice && !environment.voice.isListening ? "Getting ready to listen…" : environment.assistant.message,
            colors: SuzzmePresenceColors.mascot(for: colorScheme),
            animation: environment.invocation.presenceAnimation,
            audioLevel: environment.voice.isListening ? environment.voice.audioLevel : 0,
            speechProgress: environment.voice.isSpeaking ? environment.voice.speechProgress : nil,
            isGreeting: conversation.entries.isEmpty && environment.presenceState == .idle)
    }

    private var interactionControls: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
            preparedComposer
            SuzzmeActionControls {
                if !isProcessing { voiceButton }
                if focusedSession && ownsCurrentInteraction { cancelSessionButton }
                if !focusedSession { answerSpeechOptions }
            }
        }
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 0 : SuzzmeTheme.Layout.compactInset)
        .padding(.vertical, SuzzmeTheme.Spacing.small)
        .frame(maxWidth: SuzzmeTheme.Layout.readingWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .background { composerBackground }
        .overlay(alignment: .top) { Divider() }
    }

    private var preparedComposer: some View {
        SuzzmeAssistantComposer(text: $text, isProcessing: isProcessing,
            voiceTitle: voiceButtonTitle, voiceSymbol: environment.voice.isListening ? "checkmark" : "mic",
            onVoice: { handleVoiceControl() }, onSend: { sendTypedRequest() },
            onCancel: cancelRequestAction, isEnabled: canCompose, showsVoiceButton: false,
            focusInput: focusInput && !submitOnAppear, focusRequest: focusRequest, externalFocus: $inputFocused)
    }

    private var cancelRequestAction: (() -> Void)? {
        guard ownsCurrentInteraction else { return nil }
        return { cancelOwnedRequest() }
    }

    @ViewBuilder private var composerBackground: some View {
        if reduceTransparency { SuzzmeTheme.backgroundPrimary }
        else { Rectangle().fill(.bar) }
    }

    private var answerSpeechOptions: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
            Toggle("Read answers aloud", isOn: $readAnswerAloud)
                .toggleStyle(.switch)
                .font(.subheadline)
                .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                .disabled(!environment.voice.speaksResponses)
                .accessibilityHint(environment.voice.speaksResponses ? "Speak Suzzme’s answers to typed questions" : "Enable spoken answers in Voice settings")
            if !environment.voice.speaksResponses {
                NavigationLink("Voice settings") { VoiceSettingsView() }
                    .font(.footnote)
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget, alignment: .leading)
            }
        }
    }

    private var cancelSessionButton: some View {
        Button(environment.voice.isListening ? "Cancel recording" : "Cancel request", role: .cancel,
            action: cancelOwnedRequest)
            .buttonStyle(.bordered).keyboardShortcut(.cancelAction)
    }

    private var voiceButton: some View {
        Button(action: handleVoiceControl) {
            Label(voiceButtonTitle, systemImage: environment.voice.isListening ? "checkmark" : "mic")
                .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
        }
        #if os(macOS)
        .buttonStyle(.borderless)
        #else
        .buttonStyle(.bordered)
        #endif
        .disabled(!(canCompose || ownsCurrentInteraction && (environment.voice.isListening || environment.voice.isSpeaking || awaitsAction)))
        .accessibilityLabel(environment.voice.isListening ? "Finish speaking and send" : environment.voice.isSpeaking ? "Interrupt the answer and start listening" : "Start voice conversation")
    }

    private func handleVoiceControl() {
        inputFocused = false
        if environment.voice.isListening && ownsCurrentInteraction { environment.voice.stop() }
        else if environment.presenceState == .listening && ownsCurrentInteraction { cancelOwnedRequest() }
        else if canCompose || ownsCurrentInteraction && (environment.voice.isSpeaking || awaitsAction) { startVoiceRequest() }
    }

    private func finishVoiceOrDismiss() {
        if environment.voice.isListening && ownsCurrentInteraction {
            environment.voice.stop()
            return
        }
        guard !voiceTurnIsWaitingForResponse else { return }
        dismiss()
    }

    private func startVoiceRequest() {
        guard !isProcessing, !environment.voice.isListening else { return }
        requestTask?.cancel()
        requestRevision = UUID()
        let owner = presentationOwnership.beginRequest(confirmationOwner: environment.presentedActionOwner)
        isStartingVoice = true
        ownedVoiceSessionID = owner
        voiceEntryID = nil
        activeEntryID = nil
        message = nil
        requestTask = Task {
            defer { if presentationOwnership.requestID == owner { isStartingVoice = false } }
            let started = await environment.invokeSuzzme(
                requestID: owner, conversationID: conversationID, waitsForRelease: true
            )
            guard !Task.isCancelled, presentationOwnership.requestID == owner else { return }
            if !started, let voiceMessage = environment.voice.message {
                message = voiceMessage
                focusRequest = UUID()
                inputFocused = true
            }
        }
    }

    private func captureOwnedVoiceTranscript() {
        guard let sessionID = environment.voice.finalizedSessionID, sessionID == ownedVoiceSessionID,
              let transcript = environment.voice.finalTranscript, !transcript.isEmpty else { return }
        guard presentationOwnership.requestID == sessionID
            || presentationOwnership.requestID == environment.currentInteractionID && ownsCurrentInteraction else { return }
        if voiceEntryID == nil {
            scrollToLatest = true
            voiceEntryID = conversation.append(question: transcript, requestID: sessionID)
        }
        activeEntryID = voiceEntryID
        submittedQuestion = transcript
        text = ""
    }

    private func receiveOwnedVoiceResponse() {
        guard let sessionID = ownedVoiceSessionID, sessionID == environment.voice.sessionID else { return }
        presentationOwnership.finishVoiceResponse(sessionID: sessionID, currentRequestID: environment.currentInteractionID)
        guard ownsCurrentInteraction, let answer = environment.lastVoiceResponse else { return }
        captureOwnedVoiceTranscript()
        if let entryID = voiceEntryID {
            _ = conversation.complete(answer, entryID: entryID, requestID: sessionID)
        } else {
            let entryID = conversation.append(question: "", requestID: sessionID)
            _ = conversation.complete(answer, entryID: entryID, requestID: sessionID)
            voiceEntryID = entryID
        }
        response = answer
        result = environment.lastUnderstandingResult
        capability = result?.capability ?? capability
        activeEntryID = nil
    }

    private func cancelOwnedRequest() {
        guard let owner = presentationOwnership.requestID, ownsCurrentInteraction else { return }
        Self.submissionLog.notice("assistant-cancel activated")
        requestRevision = UUID()
        requestTask?.cancel()
        isUnderstanding = false
        isStartingVoice = false
        if let entryID = activeEntryID,
           let entry = conversation.entries.first(where: { $0.id == entryID }) {
            _ = conversation.fail("You can edit your question or try a read-only question again.",
                entryID: entryID, requestID: entry.requestID, cancelled: true)
        }
        activeEntryID = nil
        Task { await environment.dismissInteraction(owner) }
    }

    private var voiceButtonTitle: String {
        if dynamicTypeSize.isAccessibilitySize {
            return isListeningPresentation ? "Finish" : environment.presenceState == .speaking ? "Interrupt" : "Talk"
        }
        return isListeningPresentation ? "Finish speaking" : environment.presenceState == .speaking ? "Interrupt and talk" : "Talk to Suzzme"
    }

    @ViewBuilder private var screenConsent: some View {
        #if os(macOS)
        if let consentID = environment.screenConsentRequestID, consentID == presentationOwnership.requestID {
            SuzzmeCard {
                Label("Screen access for this question", systemImage: "rectangle.dashed")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(environment.screenConsentMessage ?? "Allow this screen for your question?")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                SuzzmeActionControls {
                    Button("Allow once") { Task { await environment.respondToScreenConsent(requestID: consentID, granted: true) } }
                        .buttonStyle(.borderedProminent).suzzmeProminentContrast()
                    Button("Don’t capture", role: .cancel) { Task { await environment.respondToScreenConsent(requestID: consentID, granted: false) } }
                        .buttonStyle(.bordered)
                }
            }
        }
        #endif
    }

    @ViewBuilder private var actionConfirmation: some View {
        if let action = response?.action, awaitsAction {
            SuzzmeCard(highlighted: true) {
                SuzzmeConfirmationSummary(title: action.title, destructive: [.deleteReminder, .deleteCalendarEvent, .forgetMemory].contains(action.type))
                SuzzmeActionControls {
                    Button("Cancel", role: .cancel) { sendConfirmation(actionID: action.id, confirmed: false) }
                        .buttonStyle(.bordered).keyboardShortcut(.cancelAction)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    Button(action.type.confirmationLabel, role: [.deleteReminder, .deleteCalendarEvent, .forgetMemory].contains(action.type) ? .destructive : nil) {
                        sendConfirmation(actionID: action.id, confirmed: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint([.deleteReminder, .deleteCalendarEvent, .forgetMemory].contains(action.type) ? SuzzmeTheme.destructive : SuzzmeTheme.accent)
                    .suzzmeProminentContrast().keyboardShortcut(.defaultAction)
                }
            }
            .accessibilityElement(children: .contain).disabled(isUnderstanding)
            .accessibilityLabel("Action confirmation: \(action.title)")
        }
    }

    @ViewBuilder private var connectionInvitation: some View {
        if let suggestion = connectionSuggestion, let owner = connectionSuggestionOwner, owner == environment.currentInteractionID,
           !focusedSession, !awaitsAction, environment.screenConsentRequestID == nil {
            SuzzmeCard {
                Label(suggestion.hasSavedAccount ? "Review GitHub access" : "Connect GitHub to Suzzme", systemImage: "puzzlepiece.extension")
                    .font(.headline).accessibilityAddTraits(.isHeader)
                Text("Read \(suggestion.repository) with an account you choose. Suzzme checks access before answering; connecting doesn’t run your question automatically.")
                    .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SuzzmeActionControls {
                    Button("Not now") { connectionSuggestion = nil; connectionSuggestionOwner = nil }
                        .buttonStyle(.bordered)
                    if suggestion.hasSavedAccount {
                        NavigationLink("Review connection") {
                            IntegrationsView()
                        }.buttonStyle(.borderedProminent).suzzmeProminentContrast()
                    } else {
                        Button("Connect GitHub") {
                            environment.integrations.beginAuthorization(); showsGitHubConnection = true
                        }.buttonStyle(.borderedProminent).suzzmeProminentContrast()
                            .disabled(environment.integrations.isBusy)
                    }
                }
            }
        }
    }

    @ViewBuilder private var noticedItems: some View {
        if let result, !result.items.isEmpty, !focusedSession {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                SuzzmeSectionHeader(title: "What Suzzme noticed")
                ForEach(result.items) { item in SuzzmeItemRow(item: item); Divider() }
                Button("Save to Suzzme") { save(result) }.buttonStyle(.bordered)
            }
        }
    }

    private func sendTypedRequest(question: String? = nil, replacingCurrent: Bool = false) {
        guard canCompose || replacingCurrent else { return }
        let request = (question ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        guard request.count <= SuzzmeConversationPresentation.maximumQuestionCharacters else {
            message = "Please shorten your question to 12,000 characters or fewer. Nothing was submitted."
            return
        }
        guard PrivacyEngine().classify(request).policy != .neverProcess else {
            text = ""
            message = "Suzzme won’t process secret or authentication information. The input was not retained in your conversation."
            return
        }
        inputFocused = false
        requestTask?.cancel()
        let owner = presentationOwnership.beginRequest()
        let revision = UUID()
        requestRevision = revision
        let entryID = conversation.append(question: request, requestID: owner)
        activeEntryID = entryID
        scrollToLatest = true
        submittedQuestion = request
        text = ""
        response = nil
        result = nil
        connectionSuggestion = nil
        connectionSuggestionOwner = nil
        ownedVoiceSessionID = nil
        isUnderstanding = true
        requestTask = Task { await understand(request: request, owner: owner, entryID: entryID, revision: revision) }
    }

    private func sendConfirmation(actionID: UUID, confirmed: Bool) {
        guard !isUnderstanding, environment.presentedAction?.id == actionID,
              let owner = environment.presentedActionOwner, owner == presentationOwnership.requestID,
              owner == environment.currentInteractionID else {
            message = "That request changed. Review the current action before confirming."
            return
        }
        requestTask?.cancel()
        let revision = UUID()
        requestRevision = revision
        let entryID = conversation.append(question: confirmed ? "Confirm the reviewed action" : "Cancel the reviewed action", requestID: owner)
        activeEntryID = entryID
        scrollToLatest = true
        isUnderstanding = true
        requestTask = Task {
            await understand(request: confirmed ? "confirm" : "cancel", owner: owner,
                entryID: entryID, revision: revision, confirmationActionID: actionID)
        }
    }

    private func understand(request: String, owner: UUID, entryID: UUID, revision: UUID, confirmationActionID: UUID? = nil) async {
        guard requestRevision == revision, presentationOwnership.requestID == owner, !Task.isCancelled else { return }
        isUnderstanding = true
        message = nil
        defer { if requestRevision == revision { isUnderstanding = false; activeEntryID = nil } }
        do {
            let answer = try await environment.askSuzzme(request, speakResponse: readAnswerAloud,
                requestID: owner, confirmationActionID: confirmationActionID, conversationID: conversationID)
            guard requestRevision == revision, presentationOwnership.requestID == owner,
                  environment.currentInteractionID == owner, !Task.isCancelled else { return }
            _ = conversation.complete(answer, entryID: entryID, requestID: owner)
            response = answer
            result = environment.lastUnderstandingResult
            capability = result?.capability ?? capability
            if confirmationActionID == nil, answer.contextCount == 0, answer.action == nil {
                connectionSuggestionOwner = owner
                connectionSuggestion = IntegrationConnectionSuggestion.make(question: request, accounts: environment.integrations.accounts)
            }
        } catch is CancellationError {
            guard requestRevision == revision else { return }
            _ = conversation.fail("The request stopped before an answer was returned.", entryID: entryID,
                requestID: owner, cancelled: true)
        } catch {
            guard requestRevision == revision, presentationOwnership.requestID == owner else { return }
            let explanation: String
            if let known = error as? SuzzmeIntelligenceError {
                explanation = known.errorDescription ?? "Suzzme couldn’t complete that response. Please try again."
            } else if let known = error as? SuzzmeCoreError {
                explanation = known.errorDescription ?? "That request couldn’t be completed. Please try again."
            } else {
                explanation = "That request couldn’t be completed. Please try again."
            }
            _ = conversation.fail(explanation, entryID: entryID, requestID: owner)
        }
    }

    private func save(_ result: SuzzmeUnderstandingResult) {
        do {
            let count = try environment.saveUnderstandingResult(result)
            message = count == 1 ? "Saved to Suzzme." : "Nothing new was saved."
        } catch { message = "That item couldn’t be saved. Please try again." }
    }
}

/// Ownership belongs to the presentation that started or initially displayed a
/// request. A newer global invocation must not be adopted by an older sheet.
struct AskSuzzmePresentationOwnership: Sendable {
    private(set) var requestID: UUID?
    private var hasAppeared = false
    private var confirmationOwner: UUID?

    mutating func captureInitialRequest(_ requestID: UUID?, confirmationOwner: UUID? = nil) {
        guard !hasAppeared else { return }
        hasAppeared = true
        self.requestID = requestID
        self.confirmationOwner = confirmationOwner
    }

    mutating func beginRequest(confirmationOwner: UUID? = nil) -> UUID {
        let requestID = UUID()
        hasAppeared = true
        self.requestID = requestID
        self.confirmationOwner = confirmationOwner
        return requestID
    }

    mutating func finishVoiceResponse(sessionID: UUID?, currentRequestID: UUID?) {
        guard let sessionID, let currentRequestID, requestID == sessionID,
              currentRequestID == requestID || currentRequestID == confirmationOwner else { return }
        // A voice confirmation restores its original Core request owner.
        requestID = currentRequestID
    }

    func isKnownRequest(_ candidate: UUID?) -> Bool {
        guard let candidate else { return false }
        return candidate == requestID || candidate == confirmationOwner
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
