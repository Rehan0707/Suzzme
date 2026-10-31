#if os(macOS)
import AppKit
import CoreGraphics
import Observation

/// App-lifetime adapters for the existing environment. Closing a SwiftUI
/// window never retires keyboard, transcript, or Presence ownership.
@MainActor @Observable
final class MacGlobalInvocationController {
    private let environment: AppEnvironment
    private let panel = MacAssistantPanelController()
    private let monitor = MacInvocationShortcutMonitor()
    private let guidance = MacGuidanceOverlay()
    private let cursorCompanion: MacCursorCompanion
    private var running = false
    private var observationGeneration = UUID()
    private var heldToken: UUID?
    private var interactionToken: UUID?
    private var startTask: Task<Void, Never>?
    private var finalTranscriptTask: Task<Void, Never>?
    private var briefingTask: Task<Void, Never>?
    private var lastFinalizedSessionID: UUID?
    private var lastBriefingRevision: UUID?
    private var configuredShortcut: SuzzmeKeyboardShortcut?
    private var configuredEnabled: Bool?
    private var appObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var notchReleaseMonitors: [Any] = []
    private var openIntegrationSettings: (@MainActor () -> Void)?
    private var openBackgroundDestination: (@MainActor (AppDestination) -> Void)?
    private var lastOpenedBrowserSetupID: UUID?

    var shortcutStatus: MacGlobalShortcutStatus { monitor.status }

    init(environment: AppEnvironment) {
        self.environment = environment
        self.cursorCompanion = MacCursorCompanion(environment: environment, guidance: guidance)
        guidance.onDismiss = { [weak self] presentation, reason in
            self?.cursorCompanion.endGuidance(presentation, reason: reason)
        }
        start()
    }

    func start() {
        guard !running else { return }
        running = true
        observationGeneration = UUID()
        installLifecycleObservers()
        observeEnvironment()
    }

    func stop() {
        guard running else { return }
        running = false
        environment.integrations.clearBrowserHandoff()
        observationGeneration = UUID()
        let requestID = environment.currentInteractionID
        environment.voice.cancel()
        let ownedEnvironment = environment
        Task { await ownedEnvironment.dismissInteraction(requestID) }
        monitor.stop()
        removeNotchReleaseMonitors()
        heldToken = nil
        interactionToken = nil
        startTask?.cancel()
        startTask = nil
        guidance.dismiss()
        cursorCompanion.dismiss()
        finalTranscriptTask?.cancel()
        finalTranscriptTask = nil
        briefingTask?.cancel()
        briefingTask = nil
        panel.dismiss()
        for observer in appObservers { NotificationCenter.default.removeObserver(observer) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        appObservers.removeAll()
        workspaceObservers.removeAll()
    }

    /// Called only by the explicit, explained permission action in Settings.
    @discardableResult
    func requestInputMonitoringPermission() -> Bool {
        let granted = CGRequestListenEventAccess()
        configureShortcut(force: true)
        return granted
    }

    func refreshInputMonitoringPermission() { configureShortcut(force: true) }

    /// App URL delivery is metadata-only, including when Home is closed.
    func handleOpenURL(_ url: URL) {
        if url.scheme?.lowercased() == "suzzme", ["browser", "integrations"].contains(url.host?.lowercased() ?? "") {
            environment.integrations.receiveBrowserURL(url)
        } else { environment.handleGmailSignInURL(url) }
    }

    func configureBrowserSetupNavigation(_ openSettings: @escaping @MainActor () -> Void) {
        openIntegrationSettings = openSettings
        presentBrowserSetupIfNeeded()
    }

    func configureBackgroundNavigation(_ navigate: @escaping @MainActor (AppDestination) -> Void) {
        openBackgroundDestination = navigate
        if running { updatePanel() }
    }

    /// Background metadata may use Presence only when no interactive owner,
    /// permission review, browser request, or voice transition needs the surface.
    private func backgroundActivityForPresentation() -> ScheduledBriefingActivity? {
        guard running, openBackgroundDestination != nil,
              environment.proactivePreferences.dailyBriefingEnabled,
              environment.presenceState == .idle, environment.currentInteractionID == nil,
              environment.presentedResponse == nil, environment.presentedAction == nil,
              environment.screenConsentRequestID == nil, !environment.invocation.isActive,
              environment.proactivePresenceSignal != .timeCritical,
              heldToken == nil, startTask == nil,
              !environment.voice.isListening, !environment.voice.isFinalizing,
              !environment.voice.isSpeaking, !environment.voice.isPreparingSpeech,
              environment.integrations.browserHandoff.request?.isCurrent() != true else { return nil }
        let summary = environment.proactiveSnapshot?.briefing
        return environment.scheduledBriefing.activity(
            currentSummaryID: summary?.deliveryState == .ready ? summary?.id : nil,
            hasCompletionNotice: environment.scheduledBriefingNoticeID != nil
        )
    }

    private func presentBrowserSetupIfNeeded() {
        let handoff = environment.integrations.browserHandoff
        guard handoff.phase == .setup, let request = handoff.request, request.isCurrent(),
              lastOpenedBrowserSetupID != request.id, let openIntegrationSettings else { return }
        lastOpenedBrowserSetupID = request.id
        openIntegrationSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func observeEnvironment() {
        guard running else { return }
        let generation = observationGeneration
        withObservationTracking {
            configureShortcut()
            environment.retireFailedVoiceInvocationIfNeeded()
            updatePanel()
            updateGuidance()
            cursorCompanion.update()
            guidance.setCompanionPresent(cursorCompanion.isPointing)
            if let sessionID = environment.voice.finalizedSessionID,
               environment.voice.finalTranscript != nil, lastFinalizedSessionID != sessionID {
                lastFinalizedSessionID = sessionID
                finalTranscriptTask?.cancel()
                finalTranscriptTask = Task { @MainActor [weak self] in
                    guard let self, self.running, self.observationGeneration == generation, !Task.isCancelled else { return }
                    await self.environment.consumeFinalVoiceTranscript()
                }
            }
            let revision = environment.voice.briefingLifecycleRevision
            if environment.voice.completedBriefingID != nil || environment.voice.interruptedBriefingID != nil,
               lastBriefingRevision != revision {
                lastBriefingRevision = revision
                briefingTask = Task { @MainActor [weak self] in
                    guard let self, self.running, self.observationGeneration == generation, !Task.isCancelled else { return }
                    await self.environment.consumeBriefingVoiceLifecycle()
                }
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.observationGeneration == generation else { return }
                self.observeEnvironment()
            }
        }
    }

    private func configureShortcut(force: Bool = false) {
        guard running else { return }
        let shortcut = environment.invocation.keyboardShortcut
        let enabled = environment.invocation.globalPushToTalkEnabled
        let preferencesChanged = configuredShortcut != shortcut || configuredEnabled != enabled
        guard preferencesChanged || force else { return }
        // The monitor preserves held chords on refresh and checks actual tap
        // health before reusing it.
        configuredShortcut = shortcut
        configuredEnabled = enabled
        monitor.start(
            shortcut: shortcut,
            enabled: enabled,
            isInvocationActive: { [weak self] in self?.hasTransientInteraction == true },
            invoke: { [weak self] in self?.press() },
            release: { [weak self] in
                guard let self, self.environment.invocation.keyboardShortcut != .controlOption else { return }
                self.release()
            },
            cancel: { [weak self] in self?.cancel() }
        )
    }

    private var hasTransientInteraction: Bool {
        heldToken != nil || environment.presenceState != .idle || environment.invocation.isActive
    }

    private func press() {
        guard running else { return }
        if environment.invocation.keyboardShortcut == .controlOption {
            toggleControlOptionVoice()
            return
        }
        beginHeldVoice()
    }

    private func beginNotchPushToTalk() {
        guard running, !hasTransientInteraction else { return }
        installNotchReleaseMonitors()
        beginHeldVoice()
    }

    private func endNotchPushToTalk() {
        removeNotchReleaseMonitors()
        release()
    }

    private func beginHeldVoice() {
        guard running, heldToken == nil else { return }
        environment.integrations.clearBrowserHandoff()
        // A fresh keyboard or notch press retires the previous visual target immediately;
        // model and capture cancellation may finish asynchronously afterward.
        guidance.dismiss()
        let token = UUID()
        let generation = observationGeneration
        heldToken = token
        interactionToken = token
        startTask?.cancel()
        finalTranscriptTask?.cancel()
        finalTranscriptTask = nil
        startTask = Task { @MainActor [weak self] in
            guard let self, self.running, self.observationGeneration == generation,
                  self.heldToken == token, !Task.isCancelled else { return }
            await self.environment.beginGlobalPushToTalk(token: token)
            guard !Task.isCancelled, self.running, self.observationGeneration == generation,
                  self.interactionToken == token else { return }
            // Release can occur while a microphone permission sheet suspends start.
            if self.heldToken != token { await self.environment.endGlobalPushToTalk(token: token) }
        }
    }

    /// Control + Option is a tap-to-start shortcut. Releasing either key must
    /// not end capture; the user finishes from the visible Done control.
    private func toggleControlOptionVoice() {
        if environment.voice.isListening,
           environment.currentInteractionID == environment.voice.sessionID {
            environment.voice.stop()
            return
        }
        guard !environment.voice.isFinalizing,
              ![.transcribing, .understanding, .gatheringContext, .reasoning, .planning, .acting]
                .contains(environment.presenceState),
              startTask == nil else { return }

        environment.integrations.clearBrowserHandoff()
        guidance.dismiss()
        let token = UUID()
        let generation = observationGeneration
        interactionToken = token
        startTask = Task { @MainActor [weak self] in
            guard let self, self.running, self.observationGeneration == generation,
                  self.interactionToken == token, !Task.isCancelled else { return }
            await self.environment.invokeTransientVoice()
            guard self.running, self.observationGeneration == generation,
                  self.interactionToken == token else { return }
            self.startTask = nil
        }
    }

    private func release() {
        removeNotchReleaseMonitors()
        guard running, let token = heldToken else { return }
        heldToken = nil
        let generation = observationGeneration
        Task { @MainActor [weak self] in
            guard let self, self.running, self.observationGeneration == generation,
                  self.interactionToken == token else { return }
            await self.environment.endGlobalPushToTalk(token: token)
        }
    }

    private func cancel() {
        removeNotchReleaseMonitors()
        environment.integrations.clearBrowserHandoff()
        guidance.dismiss()
        cursorCompanion.dismiss()
        heldToken = nil
        interactionToken = nil
        startTask?.cancel()
        startTask = nil
        finalTranscriptTask?.cancel()
        finalTranscriptTask = nil
        let generation = observationGeneration
        Task { @MainActor [weak self] in
            guard let self, self.running, self.observationGeneration == generation,
                  self.interactionToken == nil else { return }
            await self.environment.cancelGlobalInteraction()
        }
    }

    private func installNotchReleaseMonitors() {
        guard notchReleaseMonitors.isEmpty else { return }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.endNotchPushToTalk() }
            return event
        }) { notchReleaseMonitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            Task { @MainActor [weak self] in self?.endNotchPushToTalk() }
        }) { notchReleaseMonitors.append(monitor) }
    }

    private func removeNotchReleaseMonitors() {
        for monitor in notchReleaseMonitors { NSEvent.removeMonitor(monitor) }
        notchReleaseMonitors.removeAll()
    }

    private func updatePanel() {
        presentBrowserSetupIfNeeded()
        // A completed scheduled run gives the existing ready signal a fresh
        // display identity. It never replaces a conversation or speaks aloud.
        if environment.presenceState != .idle { environment.dismissScheduledBriefingNotice() }
        let scheduledNotice = environment.presenceState == .idle && environment.presentedResponse == nil
            ? environment.scheduledBriefingNoticeID : nil
        let handoff = environment.integrations.browserHandoff
        let browserRequest = environment.presenceState == .idle && [.review, .alreadyAllowed].contains(handoff.phase)
            ? handoff.request.flatMap { request in request.isCurrent()
                ? MacBrowserConnectionRequest(service: request.service, repository: request.repository, id: request.id, alreadyAllowed: handoff.phase == .alreadyAllowed) : nil }
            : nil
        let action = environment.presentedAction
        let owner = environment.presentedActionOwner
        let consentID = environment.screenConsentRequestID
        let consentMessage = environment.screenConsentMessage
        let review = action.map {
            SuzzmePresenceReview(id: $0.id, title: $0.title, confirmationLabel: $0.type.confirmationLabel,
                isDestructive: [.deleteReminder, .deleteCalendarEvent, .forgetMemory].contains($0.type))
        } ?? consentID.map {
            SuzzmePresenceReview(id: $0, title: consentMessage ?? "Allow Suzzme to use this screen for your question?",
                confirmationLabel: "Allow once", isDestructive: false)
        }
        let backgroundActivity = backgroundActivityForPresentation()
        panel.update(
            state: environment.presenceState,
            theme: environment.invocation.presenceTheme,
            animation: environment.invocation.presenceAnimation,
            signal: environment.proactivePresenceSignal,
            review: review,
            connectionRequest: browserRequest,
            response: browserRequest == nil ? environment.presentedResponse ?? (environment.presenceState == .error ? environment.assistant.message : nil) : nil,
            audioLevel: environment.voice.audioLevel,
            speechProgress: environment.voice.speechProgress,
            interactionID: browserRequest?.id ?? environment.currentInteractionID
                ?? (backgroundActivity == nil ? scheduledNotice : nil),
            contextLabels: environment.presentedScreenMetadata.map { metadata in
                guard let requestID = environment.currentInteractionID,
                      metadata.isCurrent(requestID: requestID) else { return [] }
                let appName = metadata.activeApplicationPID.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
                return appName.map { [$0, "Screen"] } ?? ["Screen"]
            } ?? [],
            backgroundActivity: backgroundActivity,
            onConfirmation: { [weak self] confirmed in
                guard let self, self.running else { return }
                let generation = self.observationGeneration
                if let action, let owner {
                    Task {
                        guard self.running, self.observationGeneration == generation else { return }
                        do { try await self.environment.respondToPresentedAction(id: action.id, owner: owner, confirmed: confirmed) }
                        catch { /* The central pipeline owns error/state presentation. */ }
                    }
                } else if let consentID, self.environment.screenConsentRequestID == consentID {
                    Task {
                        guard self.running, self.observationGeneration == generation else { return }
                        await self.environment.respondToScreenConsent(requestID: consentID, granted: confirmed)
                    }
                }
            },
            onConnectionDecision: { [weak self] decision in
                guard let self, self.running, let browserRequest else { return }
                let handoffDecision: BrowserIntegrationHandoff.Decision
                switch decision {
                case .decline: handoffDecision = .no
                case .later: handoffDecision = .later
                case .connect: handoffDecision = .yes
                }
                self.environment.integrations.decideBrowserRequest(id: browserRequest.id, decision: handoffDecision)
                self.updatePanel()
            },
            onBackgroundStop: { [weak self] receiptID in
                guard let self, self.running else { return }
                self.environment.scheduledBriefing.cancelCurrentRun(receiptID: receiptID)
            },
            onOpenBackgroundTasks: { [weak self] in
                guard let self, let current = self.backgroundActivityForPresentation(),
                      current.id == backgroundActivity?.id else { return }
                self.panel.hideCurrentPresentation()
                self.openBackgroundDestination?(.backgroundTasks)
            },
            onOpenDailySummary: { [weak self] in
                guard let self, let current = self.backgroundActivityForPresentation(),
                      current.id == backgroundActivity?.id, current.canOpenSummary else { return }
                self.panel.hideCurrentPresentation()
                self.openBackgroundDestination?(.briefing)
            },
            onCancel: { [weak self] in self?.monitor.resetPressedState(); self?.cancel() },
            onFinish: { [weak self] in
                guard let self, self.running, self.environment.voice.isListening else { return }
                self.environment.voice.stop()
            },
            onInvoke: { [weak self] in
                guard let self, self.running, browserRequest == nil else { return }
                let generation = self.observationGeneration
                Task {
                    guard self.running, self.observationGeneration == generation else { return }
                    await self.environment.invokeTransientVoice()
                }
            },
            onPushToTalkPress: { [weak self] in self?.beginNotchPushToTalk() },
            onPushToTalkRelease: { [weak self] in self?.endNotchPushToTalk() }
        )
    }

    private func updateGuidance() {
        let reference = environment.presentedScreenGuidance
        let metadata = environment.presentedScreenMetadata
        guard environment.presenceState != .error,
              environment.presenceState != .idle || environment.presentedResponse != nil,
              environment.screenPreferences.visualGuidance,
              environment.screenConsentRequestID == nil, environment.presentedAction == nil,
              let reference, let metadata, let requestID = environment.currentInteractionID else {
            guidance.dismiss()
            return
        }
        _ = guidance.show(reference: reference, context: metadata, currentRequestID: requestID)
    }

    private func installLifecycleObservers() {
        let generation = observationGeneration
        observeApp(NSApplication.didBecomeActiveNotification) { [weak self] in self?.configureShortcut(force: true) }
        observeApp(NSApplication.willTerminateNotification) { [weak self] in self?.stop() }
        appObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.observationGeneration == generation else { return }
                await self.environment.invalidateScreenContext()
                self.updatePanel()
            }
        })
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didMoveNotification] {
            appObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in guard let self, self.running, self.observationGeneration == generation else { return }; self.updatePanel() }
            })
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.running, self.observationGeneration == generation else { return }
                self.activeSpaceDidChange()
            }
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.running, self.observationGeneration == generation else { return }
                    self.monitor.resetPressedState()
                    self.cancel()
                    self.monitor.stop()
                    await self.environment.invalidateScreenContext()
                }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.running, self.observationGeneration == generation else { return }
                    self.configureShortcut(force: true)
                    self.updatePanel()
                }
            })
        }
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.observationGeneration == generation else { return }
                await self.environment.invalidateScreenContext()
                self.updatePanel()
            }
        })
    }

    private func activeSpaceDidChange() {
        // The marker belongs to the Space where its screen evidence was read.
        // Retire it before any actor hop, while keeping voice and Presence alive.
        guidance.dismiss()
        updatePanel()
        guard let requestID = environment.currentInteractionID else { return }
        let generation = observationGeneration
        Task { @MainActor [weak self] in
            guard let self, self.running, self.observationGeneration == generation,
                  self.environment.currentInteractionID == requestID else { return }
            await self.environment.invalidateScreenContext(requestID: requestID)
            guard self.running, self.observationGeneration == generation,
                  self.environment.currentInteractionID == requestID else { return }
            self.updatePanel()
        }
    }

    private func observeApp(_ name: Notification.Name, action: @escaping @MainActor () -> Void) {
        let generation = observationGeneration
        appObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.observationGeneration == generation else { return }
                action()
            }
        })
    }

    isolated deinit { stop() }
}
#endif
