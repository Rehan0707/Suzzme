#if os(macOS)
// Adapted from Clicky's CompanionPanelView.swift. Copyright (c) 2026 Farza.
// MIT license: Suzzme/ReferenceSource/Clicky/LICENSE.
import AppKit
import SwiftUI

/// Compact companion controls; all requests use the same owners as Home.
struct MacMenuBarView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(MacGlobalInvocationController.self) private var globalInvocation
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("suzzme.appearance") private var appearance = SuzzmeAppearance.system.rawValue
    @State private var showsAssistant = false
    @State private var showsPresence = false
    @State private var draft = ""
    @State private var submittedDraft = ""
    @State private var capability: IntelligenceCapability?
    @State private var showsControls = false
    let onClose: () -> Void
    let onNavigate: (AppDestination) -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                        Text(environment.presenceState == .idle ? "Ready when you are" :
                            SuzzmeAssistantPresentation.make(for: environment.presenceState).title)
                            .font(.title3.weight(.semibold))
                        Text(environment.presenceState == .idle ?
                            "Ask, talk, or check your day." :
                            environment.assistant.message ?? SuzzmeAssistantPresentation.make(for: environment.presenceState).systemStatus)
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(alignment: .bottom) {
                        TextField("Ask Suzzme…", text: $draft, axis: .vertical)
                            .lineLimit(1...3).textFieldStyle(.plain).onSubmit(send)
                            .accessibilityLabel("Question for Suzzme")
                        Button(action: send) {
                            Image(systemName: "arrow.up").frame(width: SuzzmeTheme.Layout.touchTarget,
                                height: SuzzmeTheme.Layout.touchTarget)
                        }
                        .buttonStyle(.bordered).accessibilityLabel("Send question")
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(SuzzmeTheme.Spacing.xs)
                    .suzzmeGlassControlSurface(cornerRadius: SuzzmeTheme.Radius.control,
                                               tint: SuzzmeTheme.intelligencePrimary.opacity(0.12))
                    Button {
                        Task { await environment.invokeTransientVoice() }
                        onClose()
                    } label: {
                        Label("Talk to Suzzme", systemImage: "mic.fill")
                            .frame(maxWidth: .infinity, minHeight: SuzzmeTheme.Layout.touchTarget)
                    }
                    .buttonStyle(.borderedProminent).suzzmeProminentContrast()
                    shortcutHelp
                    if environment.presenceState != .idle {
                        Button("Stop conversation", role: .cancel) {
                            Task { await environment.cancelGlobalInteraction() }
                        }.buttonStyle(.bordered)
                    }
                    Divider()
                    if environment.proactivePreferences.dailyBriefingEnabled,
                       let activity = environment.scheduledBriefing.activity(
                        currentSummaryID: environment.proactiveSnapshot?.briefing?.deliveryState == .ready
                            ? environment.proactiveSnapshot?.briefing?.id : nil,
                        hasCompletionNotice: environment.scheduledBriefingNoticeID != nil
                    ) {
                        MacBackgroundPreparationView(
                            activity: activity,
                            onStop: { environment.scheduledBriefing.cancelCurrentRun(receiptID: $0) },
                            onOpenTasks: { onNavigate(.backgroundTasks) },
                            onOpenSummary: { onNavigate(.briefing) }
                        )
                        Divider()
                    }
                    quickActions
                    DisclosureGroup("Controls and permissions", isExpanded: $showsControls) {
                        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                            Toggle("Show companion near cursor", isOn: Binding(
                                get: { environment.invocation.cursorCompanionEnabled },
                                set: { environment.invocation.cursorCompanionEnabled = $0 }
                            )).font(.subheadline)
                            LabeledContent("Microphone", value: voicePermission(environment.voice.microphonePermission)).font(.caption)
                            LabeledContent("Speech Recognition", value: voicePermission(environment.voice.speechPermission)).font(.caption)
                            LabeledContent("Global shortcut", value: globalInvocation.shortcutStatus.title).font(.caption)
                            Text("Screen access is optional. Suzzme asks before using it; your day and voice stay usable without it.")
                                .font(.caption).foregroundStyle(.secondary)
                            if let capability {
                                Text(capability.displayDescription).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, SuzzmeTheme.Spacing.small)
                    }
                    .font(.subheadline)
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                }
                .padding(SuzzmeTheme.Layout.compactInset)
            }
            Divider()
            HStack {
                Button("Open Suzzme") { onNavigate(.home) }
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                Spacer()
                Button(action: { onNavigate(.sources) }) {
                    Image(systemName: "tray.2")
                        .frame(width: SuzzmeTheme.Layout.touchTarget, height: SuzzmeTheme.Layout.touchTarget)
                }
                    .accessibilityLabel("Sources and web connections")
                Menu {
                    Button("Settings", action: onSettings)
                    Button("Presence Settings") { showsPresence = true }
                    Divider()
                    Button("Quit Suzzme") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: SuzzmeTheme.Layout.touchTarget, height: SuzzmeTheme.Layout.touchTarget)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .accessibilityLabel("Companion options")
            }
            .buttonStyle(.plain).frame(minHeight: SuzzmeTheme.Layout.touchTarget)
            .padding(.horizontal, SuzzmeTheme.Layout.compactInset)
            Text("Intelligence and voice on this device")
                .font(.caption2).foregroundStyle(.secondary).padding(.bottom, SuzzmeTheme.Spacing.small)
        }
        .background {
            ZStack {
                SuzzmeTheme.backgroundPrimary
                RadialGradient(colors: [SuzzmeTheme.intelligenceSurface.opacity(0.5), .clear],
                               center: .top, startRadius: 8, endRadius: 380)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.largeSurface, style: .continuous))
        .preferredColorScheme(SuzzmeAppearance(rawValue: appearance)?.colorScheme)
        .task { capability = await environment.intelligenceCapability() }
        .sheet(isPresented: $showsAssistant) {
            AskSuzzmeView(initialText: submittedDraft, focusInput: true, submitOnAppear: true)
                .frame(minWidth: 480, idealWidth: 520, minHeight: 580, idealHeight: 640)
        }
        .sheet(isPresented: $showsPresence) {
            NavigationStack {
                PresenceSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showsPresence = false }
                                .keyboardShortcut(.cancelAction)
                        }
                    }
            }
            .frame(minWidth: 440, idealWidth: 520, minHeight: 460)
        }
    }

    private var header: some View {
        HStack(spacing: SuzzmeTheme.Spacing.small) {
            SuzzmeMascot(state: environment.presenceState,
                size: SuzzmeTheme.Layout.touchTarget,
                isAnimated: false,
                animation: environment.invocation.presenceAnimation,
                audioLevel: environment.voice.isListening ? environment.voice.audioLevel : 0,
                speechProgress: environment.voice.isSpeaking ? environment.voice.speechProgress : 0)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                Text("Suzzme").font(.headline)
                Text(environment.presenceState == .idle ? "Your personal companion" :
                    SuzzmeAssistantPresentation.make(for: environment.presenceState).systemStatus)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark").frame(width: SuzzmeTheme.Layout.touchTarget, height: SuzzmeTheme.Layout.touchTarget)
            }.buttonStyle(.plain).accessibilityLabel("Close companion panel")
        }
        .padding(.horizontal, SuzzmeTheme.Spacing.medium).padding(.vertical, SuzzmeTheme.Spacing.xs)
    }

    private var shortcutDescription: String {
        switch globalInvocation.shortcutStatus {
        case .ready:
            "Hold \(environment.invocation.keyboardShortcut.title) to talk. Release to send. Escape cancels."
        case .needsPermission:
            "Global push to talk needs Input Monitoring. You can use Talk to Suzzme now."
        case .unavailable:
            "The global shortcut is unavailable. Use Talk to Suzzme, or review Settings to retry."
        case .disabled:
            "Global push to talk is off. Use Talk to Suzzme, or choose a shortcut in Settings."
        }
    }

    private var shortcutHelp: some View {
        HStack(alignment: .center, spacing: SuzzmeTheme.Spacing.xs) {
            Text(shortcutDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if globalInvocation.shortcutStatus == .needsPermission || globalInvocation.shortcutStatus == .unavailable {
                Button("Set up", action: onSettings)
                    .buttonStyle(.bordered)
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                    .accessibilityLabel("Set up global shortcut")
                    .accessibilityHint("Opens Settings to review Input Monitoring. The Talk button works without global shortcut access.")
            }
        }
    }

    private var quickActions: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: SuzzmeTheme.Spacing.xs) { quickActionButtons }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: SuzzmeTheme.Spacing.xs) {
                    quickActionButtons
                }
            }
        }
    }

    @ViewBuilder private var quickActionButtons: some View {
        quickAction("Today", accessibilityLabel: "What do I have today?", symbol: "sun.max") {
            submittedDraft = "What do I have today?"; showsAssistant = true
        }
        quickAction("Daily Summary", symbol: "text.alignleft") { onNavigate(.briefing) }
        quickAction("Background Tasks", symbol: "clock.arrow.circlepath") { onNavigate(.backgroundTasks) }
        quickAction("This Screen", accessibilityLabel: "Ask about this screen", symbol: "viewfinder") {
            Task { await environment.askAboutCurrentScreen() }; onClose()
        }
    }

    private func quickAction(_ title: String, accessibilityLabel: String? = nil, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: SuzzmeTheme.Layout.touchTarget, alignment: .leading)
                .padding(.horizontal, SuzzmeTheme.Spacing.xs)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(accessibilityLabel ?? title)
    }

    private func voicePermission(_ permission: VoiceSessionController.Permission) -> String {
        switch permission {
        case .authorized: "Allowed"
        case .notDetermined: "Not requested"
        case .denied: "Off"
        case .restricted: "Restricted"
        case .unavailable: "Unavailable"
        }
    }

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        submittedDraft = question
        draft = ""
        showsAssistant = true
    }
}
#endif
