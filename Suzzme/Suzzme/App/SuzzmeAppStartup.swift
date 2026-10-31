import SwiftUI
import SwiftData
import Observation
import os

/// Containers are Sendable in SwiftData; their contexts are created only after
/// preparation returns to the main actor. Existing store locations are retained.
struct SuzzmePersistencePreparation: Sendable {
    enum UnavailableStore: String, Sendable {
        case personalInformation = "Personal Memory and saved items"
        case sourceInformation = "Saved source information"
    }

    var personalContainer: ModelContainer?
    var informationContainer: ModelContainer?
    var unavailable: [UnavailableStore] = []

    @concurrent static func open(retaining previous: Self? = nil) async -> Self {
        #if os(iOS)
        // The companion uses an account-scoped received-summary cache. Source,
        // memory, and AI preparation stores belong to the Mac runtime.
        return Self()
        #else
        var result = Self(personalContainer: previous?.personalContainer,
                          informationContainer: previous?.informationContainer)
        let logger = Logger(subsystem: "Suzzme", category: "Startup")
        if result.personalContainer == nil {
            do {
                result.personalContainer = try ModelContainer(for: StoredSuzzmeItem.self,
                    StoredSuzzmeMemory.self, StoredSuzzmeMemoryRelationship.self)
            } catch {
                result.unavailable.append(.personalInformation)
                logger.error("Saved information could not be opened: \(String(describing: error), privacy: .private)")
            }
        }
        if result.informationContainer == nil {
            do { result.informationContainer = try InformationPersistence.makeContainer() }
            catch {
                result.unavailable.append(.sourceInformation)
                logger.error("Source information could not be opened: \(String(describing: error), privacy: .private)")
            }
        }
        return result
        #endif
    }
}

/// Exactly one production environment and its platform surfaces per bootstrap.
@MainActor final class SuzzmeAppRuntime {
    let persistence: SuzzmePersistencePreparation
    let environment: AppEnvironment
    let initialURLs: [URL]
    #if os(macOS)
    let globalInvocation: MacGlobalInvocationController
    let companionMenu: MacCompanionMenuController
    let scheduledBriefing: MacScheduledBriefingController
    let launchAtLogin: MacLaunchAtLoginController
    #elseif os(iOS)
    let liveActivity = SuzzmeLiveActivityController()
    private var applicationPhase: ScenePhase = .inactive
    private var backgroundTask: Task<Void, Never>?
    private var presentationTask: Task<Void, Never>?
    private var reduceMotion = false
    private var summaryActivityDate: Date?
    private var summaryActivitySessionID: UUID?
    #endif

    init(persistence: SuzzmePersistencePreparation, initialURLs: [URL]) {
        self.persistence = persistence
        self.initialURLs = initialURLs
        #if os(macOS)
        let proactiveStore: ProactiveIntelligenceStore? = ProactiveIntelligenceStore(fileURL: ProactiveIntelligenceStore.defaultURL())
        #else
        let proactiveStore: ProactiveIntelligenceStore? = nil
        #endif
        let environment = AppEnvironment(
            itemStore: persistence.personalContainer.map { SuzzmeItemStore(container: $0) },
            memoryStore: persistence.personalContainer.map { LongTermMemoryStore(modelContainer: $0) },
            informationStore: persistence.informationContainer.map { InformationStore(modelContainer: $0) },
            proactiveStore: proactiveStore)
        self.environment = environment
        #if os(iOS)
        CompanionApplicationDelegate.runtime = self
        #endif
        #if os(macOS)
        let invocation = MacGlobalInvocationController(environment: environment)
        self.globalInvocation = invocation
        self.companionMenu = MacCompanionMenuController(environment: environment, invocation: invocation)
        self.scheduledBriefing = MacScheduledBriefingController(environment: environment)
        self.launchAtLogin = MacLaunchAtLoginController()
        MacAppLifetime.integrationInvocation = invocation
        MacAppLifetime.browserBridge = environment.browserBridge
        environment.browserBridge.prepare(integrations: environment.integrations)
        #endif
    }

    func retirePlatformSurfaces() async {
        #if os(macOS)
        await scheduledBriefing.retire()
        companionMenu.stop()
        globalInvocation.stop()
        environment.browserBridge.stop()
        #elseif os(iOS)
        backgroundTask?.cancel()
        backgroundTask = nil
        presentationTask?.cancel()
        presentationTask = nil
        await liveActivity.update(.idle)
        #endif
    }

    #if os(iOS)
    @discardableResult
    func updateApplicationPhase(to phase: ScenePhase) -> Task<Void, Never>? {
        guard applicationPhase != phase else { return backgroundTask }
        applicationPhase = phase
        backgroundTask?.cancel()
        backgroundTask = nil
        updateLiveActivity(reduceMotion: reduceMotion)
        guard phase == .background else { return nil }
        backgroundTask = Task { [weak self] in
            guard let self, self.applicationPhase == .background, !Task.isCancelled else { return }
            await self.environment.cancelVoiceSession()
            guard self.applicationPhase == .background, !Task.isCancelled else { return }
            await self.environment.cancelInformationIntake(respectingTaskCancellation: true)
            guard self.applicationPhase == .background, !Task.isCancelled else { return }
            await self.environment.cancelProactivePreparation(respectingTaskCancellation: true)
        }
        return backgroundTask
    }

    /// Every scene asks this single owner to sample current state. A delayed
    /// scene callback never supplies an old phase, session or foreground flag.
    func updateLiveActivity(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        presentationTask?.cancel()
        presentationTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            if !self.environment.hasCheckedCompanionSummary,
               CompanionSummaryStore.currentUser != nil, self.environment.presenceState == .idle { return }
            let date = self.environment.companionSummary?.generatedAt
            if date != self.summaryActivityDate {
                self.summaryActivityDate = date
                self.summaryActivitySessionID = date == nil ? nil : UUID()
            }
            let recent = date.map { Date.now.timeIntervalSince($0) >= 0 && Date.now.timeIntervalSince($0) < 3600 } ?? false
            let design = SuzzmeLiveActivityDesign(rawValue: UserDefaults.standard.string(
                forKey: SuzzmeLiveActivityDesign.defaultsKey) ?? "") ?? .companion
            await self.liveActivity.update(self.environment.presenceState,
                theme: SuzzmeMascotAppearance.shared.color.rawValue,
                sessionID: self.environment.presenceRequestID,
                design: design,
                motionEnabled: !self.reduceMotion && self.environment.invocation.presenceAnimation != .minimal,
                foreground: self.applicationPhase != .background,
                summarySessionID: recent ? self.summaryActivitySessionID : nil)
        }
    }
    #endif
}

#if os(iOS)
private struct SuzzmeApplicationPhaseKey: EnvironmentKey {
    static let defaultValue: ScenePhase = .inactive
}
private struct SuzzmeApplicationRuntimeKey: EnvironmentKey {
    static let defaultValue: SuzzmeAppRuntime? = nil
}
extension EnvironmentValues {
    var suzzmeApplicationPhase: ScenePhase {
        get { self[SuzzmeApplicationPhaseKey.self] }
        set { self[SuzzmeApplicationPhaseKey.self] = newValue }
    }
    var suzzmeApplicationRuntime: SuzzmeAppRuntime? {
        get { self[SuzzmeApplicationRuntimeKey.self] }
        set { self[SuzzmeApplicationRuntimeKey.self] = newValue }
    }
}
#endif

/// This state owns startup only; it never becomes a second assistant lifecycle.
@MainActor @Observable final class SuzzmeAppStartup {
    enum Phase {
        case preparing(SuzzmePersistencePreparation?, retiringRequest: Bool)
        case recovery(SuzzmePersistencePreparation)
        case ready(SuzzmeAppRuntime)
    }
    private(set) var phase: Phase = .preparing(nil, retiringRequest: false)
    @ObservationIgnored private var preparationTask: Task<Void, Never>?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var pendingURLs: [URL] = []
    @ObservationIgnored private let preparePersistence: @Sendable (SuzzmePersistencePreparation?) async -> SuzzmePersistencePreparation
    #if os(iOS)
    @ObservationIgnored private var applicationPhase: ScenePhase = .inactive

    func updateApplicationPhase(to phase: ScenePhase) {
        applicationPhase = phase
        runtime?.updateApplicationPhase(to: phase)
    }
    #endif

    init(preparePersistence: @escaping @Sendable (SuzzmePersistencePreparation?) async -> SuzzmePersistencePreparation = { previous in
        await SuzzmePersistencePreparation.open(retaining: previous)
    }) {
        self.preparePersistence = preparePersistence
    }

    var runtime: SuzzmeAppRuntime? {
        if case .ready(let runtime) = phase { return runtime }
        return nil
    }

    @discardableResult
    func prepareIfNeeded() -> Task<Void, Never>? {
        guard case .preparing(let previous, false) = phase else { return nil }
        if let preparationTask { return preparationTask }
        revision += 1
        let owner = revision
        let prepare = preparePersistence
        preparationTask = Task { [weak self] in
            let prepared = await prepare(previous)
            guard let self, self.revision == owner, !Task.isCancelled else { return }
            self.preparationTask = nil
            if prepared.unavailable.isEmpty { self.activate(prepared) }
            else { self.phase = .recovery(prepared) }
        }
        return preparationTask
    }

    func retry() async {
        let previous: SuzzmePersistencePreparation
        let retiring: SuzzmeAppRuntime?
        switch phase {
        case .preparing: return
        case .recovery(let prepared): previous = prepared; retiring = nil
        case .ready(let runtime):
            guard !runtime.persistence.unavailable.isEmpty else { return }
            previous = runtime.persistence; retiring = runtime
        }
        revision += 1
        let owner = revision
        preparationTask?.cancel(); preparationTask = nil
        phase = .preparing(previous, retiringRequest: retiring != nil)
        await retiring?.retirePlatformSurfaces()
        if let retiring { await retiring.environment.cancelGlobalInteraction() }
        guard revision == owner, case .preparing = phase else { return }
        phase = .preparing(previous, retiringRequest: false)
        prepareIfNeeded()
    }

    func continueWithAvailableFeatures() {
        let prepared: SuzzmePersistencePreparation
        switch phase {
        case .ready: return
        case .recovery(let available): prepared = available
        case .preparing(_, true): return
        case .preparing(let available, false):
            prepared = available ?? .init(personalContainer: nil, informationContainer: nil,
                unavailable: [.personalInformation, .sourceInformation])
        }
        revision += 1
        preparationTask?.cancel(); preparationTask = nil
        activate(prepared)
    }

    func queueURLWhilePreparing(_ url: URL) {
        guard runtime == nil, pendingURLs.count < 4 else { return }
        pendingURLs.append(url)
    }

    private func activate(_ persistence: SuzzmePersistencePreparation) {
        let urls = pendingURLs
        pendingURLs = []
        let runtime = SuzzmeAppRuntime(persistence: persistence, initialURLs: urls)
        #if os(iOS)
        runtime.updateApplicationPhase(to: applicationPhase)
        #endif
        phase = .ready(runtime)
    }

    isolated deinit { preparationTask?.cancel() }
}

struct SuzzmeStartupRoot: View {
    let startup: SuzzmeAppStartup

    var body: some View {
        Group {
            switch startup.phase {
            case .preparing(_, let retiringRequest):
                SuzzmeStartupRecoveryView(isPreparing: true,
                    canContinue: !retiringRequest, unavailable: [], retry: {},
                    continueAction: startup.continueWithAvailableFeatures)
            case .recovery(let prepared):
                SuzzmeStartupRecoveryView(isPreparing: false,
                    canContinue: true, unavailable: prepared.unavailable,
                    retry: { Task { await startup.retry() } },
                    continueAction: startup.continueWithAvailableFeatures)
            case .ready(let runtime):
                VStack(spacing: 0) {
                    if !runtime.persistence.unavailable.isEmpty {
                        SuzzmeStartupNotice(unavailable: runtime.persistence.unavailable) {
                            Task { await startup.retry() }
                        }
                    }
                    ContentView(initialURLs: runtime.initialURLs)
                        .environment(runtime.environment)
                        .tint(SuzzmeTheme.accent)
                        #if os(iOS)
                        .environment(\.suzzmeApplicationRuntime, runtime)
                        #endif
                        #if os(macOS)
                        .environment(runtime.globalInvocation)
                        .environment(runtime.launchAtLogin)
                        .background {
                            MacCompanionMenuBridge(controller: runtime.companionMenu, invocation: runtime.globalInvocation)
                        }
                        #endif
                }
            }
        }
        .task { startup.prepareIfNeeded() }
        .onOpenURL(perform: startup.queueURLWhilePreparing)
        .tint(SuzzmeTheme.accent)
    }
}

private struct SuzzmeStartupRecoveryView: View {
    let isPreparing: Bool
    let canContinue: Bool
    let unavailable: [SuzzmePersistencePreparation.UnavailableStore]
    let retry: () -> Void
    let continueAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: SuzzmeTheme.Spacing.large) {
                SuzzmeMark()
                    .frame(width: 96, height: 96).accessibilityHidden(true)
                Text(isPreparing ? "Preparing Suzzme" : "Your saved information couldn’t be opened")
                    .font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(isPreparing ? "Opening your information on this device. The assistant will be ready shortly." : "Your saved information has not been changed. Try again, or continue with the available features.")
                    .foregroundStyle(SuzzmeTheme.textSecondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if isPreparing {
                    ProgressView().accessibilityLabel("Preparing local information")
                } else {
                    ForEach(unavailable, id: \.self) { store in
                        Label(store.rawValue, systemImage: "exclamationmark.circle")
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                    Button("Try again", action: retry)
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .accessibilityIdentifier("suzzme-startup-retry")
                }
                Button(isPreparing ? "Continue with limited features" : "Continue with available features", action: continueAction)
                    .buttonStyle(.bordered).controlSize(.large)
                    .disabled(!canContinue)
                    .accessibilityIdentifier("suzzme-startup-continue")
                if !canContinue {
                    Text("Finishing the current request before reopening storage.")
                        .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                }
                Text("Unavailable saved information will stay inaccessible until storage can be opened. You can retry without deleting it.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .padding(SuzzmeTheme.Spacing.extraLarge)
            .suzzmeGlassSurface(cornerRadius: SuzzmeTheme.Radius.hero,
                                tint: SuzzmeTheme.intelligencePrimary.opacity(0.12))
            .frame(maxWidth: SuzzmeTheme.Layout.companionWidth)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SuzzmeTheme.pageBackground.ignoresSafeArea())
        .accessibilityIdentifier(isPreparing ? "suzzme-startup-preparing" : "suzzme-startup-recovery")
    }
}

private struct SuzzmeStartupNotice: View {
    let unavailable: [SuzzmePersistencePreparation.UnavailableStore]
    let retry: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: SuzzmeTheme.Spacing.small) { message; retryButton }
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) { message; retryButton }
        }
        .padding(SuzzmeTheme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .suzzmeGlassSurface(cornerRadius: SuzzmeTheme.Radius.card,
                            tint: SuzzmeTheme.intelligencePrimary.opacity(0.1))
    }

    private var message: some View {
        Label("Some saved information is unavailable. Your data hasn’t been changed.", systemImage: "exclamationmark.circle")
            .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHint(unavailable.map(\.rawValue).joined(separator: ", "))
    }

    private var retryButton: some View {
        Button("Retry storage", action: retry)
            .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
            .accessibilityIdentifier("suzzme-storage-retry")
    }
}
