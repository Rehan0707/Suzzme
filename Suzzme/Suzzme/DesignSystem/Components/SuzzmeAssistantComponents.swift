import SwiftUI

enum SuzzmeConversationRole: Sendable {
    case user
    case assistant
}

struct SuzzmeConversationMessageRow: View {
    let role: SuzzmeConversationRole
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
            Text(role == .user ? "You" : "Suzzme")
                .font(.caption.weight(.semibold))
                .foregroundStyle(role == .assistant ? SuzzmeTheme.intelligencePrimary : SuzzmeTheme.textSecondary)
            Text(text)
                .font(.body)
                .foregroundStyle(SuzzmeTheme.textPrimary)
                .lineSpacing(SuzzmeTheme.Spacing.xxs)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(role == .user ? SuzzmeTheme.Spacing.medium : 0)
        .modifier(SuzzmeConversationBubbleGlass(isUserMessage: role == .user))
        .frame(maxWidth: role == .user ? SuzzmeTheme.Layout.readingWidth * 0.88 : .infinity, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: role == .user ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(role == .user ? "You said: \(text)" : "Suzzme answered: \(text)")
    }
}

struct SuzzmeResponseAttribution: View {
    let route: SuzzmeRoute
    let contextCount: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: SuzzmeTheme.Spacing.medium) {
                source
                if contextCount > 0 { context }
            }
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                source
                if contextCount > 0 { context }
            }
        }
        .font(.caption)
        .foregroundStyle(SuzzmeTheme.textSecondary)
    }

    private var source: some View {
        Label(sourceTitle, systemImage: sourceSymbol)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var context: some View {
        Label("Using authorized context", systemImage: "checkmark.shield")
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sourceTitle: String {
        switch route {
        case .onDeviceIntelligence: "Generated on this device"
        case .localContext: "Answered from authorized local context"
        case .deterministic: "Answered without generative AI"
        }
    }

    private var sourceSymbol: String {
        switch route {
        case .onDeviceIntelligence: "apple.intelligence"
        case .localContext: "checkmark.shield"
        case .deterministic: "text.badge.checkmark"
        }
    }
}

struct SuzzmeAssistantStatusIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let state: SuzzmeAssistantState
    let statusMessage: String?
    let colors: SuzzmePresenceColors
    let animation: SuzzmePresenceAnimation
    var audioLevel = 0.0
    var speechProgress: Double?
    var isGreeting = false

    var body: some View {
        HStack(spacing: SuzzmeTheme.Spacing.medium) {
            SuzzmeMascot(
                state: state,
                size: SuzzmeTheme.Spacing.hero,
                animation: reduceMotion ? .minimal : animation,
                audioLevel: audioLevel,
                speechProgress: speechProgress ?? 0,
                isGreeting: isGreeting
            )
            .padding(SuzzmeTheme.Spacing.xs)
            .suzzmeContentSurface(cornerRadius: SuzzmeTheme.Radius.control,
                                  tint: signatureTint)
            .shadow(color: signatureGlow, radius: state.isActiveIntelligence ? 14 : 0)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                Text(state == .idle ? "Suzzme" : SuzzmeAssistantPresentation.make(for: state).title)
                    .font(.headline)
                if state == .speaking, let speechProgress {
                    ProgressView(value: speechProgress)
                        .tint(colors.primary)
                        .accessibilityLabel("Spoken answer progress")
                } else {
                    Text(statusMessage ?? defaultStatus)
                        .font(.caption)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Suzzme status: \(statusMessage ?? defaultStatus)")
        .onChange(of: state) { _, current in
            guard scenePhase == .active,
                  [.listening, .awaitingConfirmation, .success, .error].contains(current) else { return }
            AccessibilityNotification.Announcement(statusMessage ?? defaultStatus).post()
        }
    }

    private var defaultStatus: String {
        state == .idle ? "Ready when you are" : SuzzmeAssistantPresentation.make(for: state).systemStatus
    }

    private var signatureTint: Color {
        colors.primary.opacity(state.isActiveIntelligence ? 0.18 : 0.08)
    }

    private var signatureGlow: Color {
        state.isActiveIntelligence ? colors.glow.opacity(SuzzmeTheme.Motion.presenceGlow) : .clear
    }
}

private struct SuzzmeConversationBubbleGlass: ViewModifier {
    let isUserMessage: Bool
    func body(content: Content) -> some View {
        if isUserMessage {
            content.suzzmeContentSurface(cornerRadius: SuzzmeTheme.Radius.card,
                                         tint: SuzzmeTheme.intelligencePrimary.opacity(0.12))
        } else {
            content
        }
    }
}

struct SuzzmeAssistantComposer: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var text: String
    let isProcessing: Bool
    let voiceTitle: String
    let voiceSymbol: String
    let onVoice: () -> Void
    let onSend: () -> Void
    var onCancel: (() -> Void)? = nil
    var isEnabled = true
    var showsVoiceButton = true
    var focusInput = false
    var focusRequest: UUID? = nil
    var externalFocus: FocusState<Bool>.Binding? = nil
    @FocusState private var isFocused: Bool

    init(text: Binding<String>, isProcessing: Bool, voiceTitle: String, voiceSymbol: String,
         onVoice: @escaping () -> Void, onSend: @escaping () -> Void,
         onCancel: (() -> Void)? = nil, isEnabled: Bool = true, showsVoiceButton: Bool = true,
         focusInput: Bool = false, focusRequest: UUID? = nil, externalFocus: FocusState<Bool>.Binding? = nil) {
        _text = text
        self.isProcessing = isProcessing
        self.voiceTitle = voiceTitle
        self.voiceSymbol = voiceSymbol
        self.onVoice = onVoice
        self.onSend = onSend
        self.onCancel = onCancel
        self.isEnabled = isEnabled
        self.showsVoiceButton = showsVoiceButton
        self.focusInput = focusInput
        self.focusRequest = focusRequest
        self.externalFocus = externalFocus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
            HStack(alignment: .bottom, spacing: SuzzmeTheme.Spacing.small) {
                TextField(
                    dynamicTypeSize.isAccessibilitySize ? "Question" : "Ask Suzzme or follow up",
                    text: $text,
                    axis: .vertical
                )
                .font(.body)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .focused(externalFocus ?? $isFocused)
                .disabled(!isEnabled)
                .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                .accessibilityLabel("Question for Suzzme")
                .accessibilityIdentifier("suzzme-assistant-input")
                .submitLabel(.send)
                .onSubmit(send)

                Button {
                    if isProcessing { onCancel?() } else { send() }
                } label: {
                    Image(systemName: isProcessing ? "stop.fill" : "arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: SuzzmeTheme.Layout.touchTarget, minHeight: SuzzmeTheme.Layout.touchTarget)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(SuzzmeTheme.intelligencePrimary)
                .suzzmeProminentContrast()
                .accessibilityLabel(isProcessing ? "Cancel request" : "Send question")
                .accessibilityIdentifier("suzzme-assistant-submit")
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isProcessing ? onCancel == nil : !isEnabled || normalizedText.isEmpty)
            }
            .padding(SuzzmeTheme.Spacing.small)
            .suzzmeGlassControlSurface(cornerRadius: SuzzmeTheme.Radius.card,
                                       tint: SuzzmeTheme.intelligencePrimary.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.card, style: .continuous)
                    .strokeBorder(
                        contrast == .increased || hasFocus ? SuzzmeTheme.textSecondary : SuzzmeTheme.separator,
                        lineWidth: contrast == .increased || hasFocus ? SuzzmeTheme.hairline * 2 : SuzzmeTheme.hairline
                    )
            }

            if showsVoiceButton {
                Button(action: onVoice) {
                    Label(voiceTitle, systemImage: voiceSymbol)
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                }
                .buttonStyle(.bordered)
                .disabled(!isEnabled)
            }
        }
        .onAppear { if focusInput && isEnabled && !isProcessing { setFocus(true) } }
        .onChange(of: focusRequest) { _, _ in if isEnabled && !isProcessing { setFocus(true) } }
    }

    private var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var hasFocus: Bool { externalFocus?.wrappedValue ?? isFocused }
    private func setFocus(_ value: Bool) {
        if let externalFocus { externalFocus.wrappedValue = value } else { isFocused = value }
    }

    private func send() {
        guard isEnabled, !isProcessing, !normalizedText.isEmpty else { return }
        setFocus(false)
        onSend()
    }
}

struct SuzzmeAssistantConversationScroll<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var followsConversation: Bool
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LazyVStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? SuzzmeTheme.Spacing.extraLarge : SuzzmeTheme.Spacing.large) {
                    content
                }
                .padding(.horizontal, SuzzmeTheme.Layout.compactInset)
                .padding(.vertical, SuzzmeTheme.Spacing.large)
                .frame(maxWidth: SuzzmeTheme.Layout.readingWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                // The scroll target belongs after the content padding so its
                // bottom anchor reaches the actual end of the scroll region.
                conversationEnd
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background(SuzzmeTheme.pageBackground)
    }

    @ViewBuilder private var conversationEnd: some View {
        if #available(iOS 18, macOS 15, *) {
            endMarker.onScrollVisibilityChange(threshold: 1) { followsConversation = $0 }
        } else {
            // Preserve the existing lifecycle behavior on older supported OSes.
            endMarker.onAppear { followsConversation = true }
                .onDisappear { followsConversation = false }
        }
    }

    private var endMarker: some View {
        Color.clear.frame(height: 1).id("assistant-conversation-bottom")
    }
}

struct SuzzmeAssistantNotice: View {
    let symbol: String
    let title: String
    let message: String
    var isWarning = false
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.medium) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(isWarning ? SuzzmeTheme.warning : SuzzmeTheme.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.plain)
                        .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                }
            }
        }
        .padding(SuzzmeTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .suzzmeContentSurface(cornerRadius: SuzzmeTheme.Radius.card,
                              tint: isWarning ? SuzzmeTheme.warning.opacity(0.12) : SuzzmeTheme.intelligencePrimary.opacity(0.1))
        .accessibilityElement(children: .contain)
    }
}

private extension SuzzmeAssistantState {
    var isActiveIntelligence: Bool {
        switch self {
        case .listening, .transcribing, .understanding, .gatheringContext, .reasoning, .planning, .acting, .speaking:
            true
        default:
            false
        }
    }
}
