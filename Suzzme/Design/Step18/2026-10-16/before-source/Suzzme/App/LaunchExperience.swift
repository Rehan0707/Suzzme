import SwiftUI

enum LaunchPhase: Equatable { case splash, authentication, onboarding, app }

struct SplashView: View {
    var body: some View {
        ZStack {
            SuzzmeTheme.backgroundPrimary.ignoresSafeArea()
            SuzzmeFace(color: .primary, lineWidth: 5)
                .frame(width: 104, height: 104)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Suzzme")
    }
}

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onComplete: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @AppStorage("suzzme.profile.name") private var profileName = ""
    @State private var step = 0
    @State private var intelligenceCapability: IntelligenceCapability?
    private let pages = OnboardingPage.pages

    var body: some View {
        ZStack {
            SuzzmeTheme.launchGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    pageContent
                        .id(step)
                        .transition(.opacity)
                        .padding(.vertical, SuzzmeTheme.Spacing.large)
                }
                controls
            }
            .padding(SuzzmeTheme.Spacing.large)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .suzzmeSelectionFeedback(trigger: step)
        .task(id: step) {
            guard pages[step].kind == .availability else { return }
            let capability = await environment.intelligenceCapability()
            guard !Task.isCancelled else { return }
            intelligenceCapability = capability
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: SuzzmeTheme.Spacing.xs) {
                SuzzmeMark().frame(width: 34, height: 34)
                Text("Suzzme").font(.headline)
            }
            Spacer()
            Button("Skip", action: onComplete).foregroundStyle(SuzzmeTheme.textSecondary)
        }
    }

    @ViewBuilder private var pageContent: some View {
        let page = pages[step]
        VStack(spacing: SuzzmeTheme.Spacing.extraLarge) {
            SuzzmeFace(color: SuzzmeTheme.intelligencePrimary, lineWidth: 5)
                .frame(width: 108, height: 108)
                .accessibilityHidden(true)
            VStack(spacing: SuzzmeTheme.Spacing.small) {
                Label(page.eyebrow, systemImage: page.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                Text(page.title)
                    .font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(page.message)
                    .font(.title3)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            pageDetails(page.kind)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func pageDetails(_ kind: OnboardingPage.Kind) -> some View {
        switch kind {
        case .profile:
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                Text("What should Suzzme call you?").font(.headline)
                TextField("Your name", text: $profileName)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.name)
                    .submitLabel(.done)
                Text("Stored only on this device. You can change it in Settings.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            .frame(maxWidth: 420)
        case .capabilities:
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
                capability("Talk naturally", "waveform")
                capability("Understand your day", "calendar")
                capability("Remember what matters", "square.stack.3d.up")
                capability("Help with changes you approve", "checkmark.shield")
            }
            .frame(maxWidth: 420)
        case .availability:
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
                if let intelligenceCapability {
                    Label(intelligenceCapability.usesFoundationModels ? "On-device model ready" : "Local assistance available",
                          systemImage: intelligenceCapability.usesFoundationModels ? "checkmark.circle" : "info.circle")
                        .font(.headline)
                    Text(intelligenceCapability.displayDescription)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("You can always type and use supported local information. Generative answers need a supported device with Apple Intelligence enabled.")
                        .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ProgressView("Checking on-device availability…")
                }
            }
            .frame(maxWidth: SuzzmeTheme.Layout.primaryColumnMinimum, alignment: .leading)
        case .privacy:
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
                capability("On-device first", "iphone")
                capability("Minimum necessary access", "hand.raised")
                capability("Memory and sources stay under your control", "lock.shield")
            }
            .frame(maxWidth: 460)
        case .voice:
            VStack(spacing: SuzzmeTheme.Spacing.medium) {
                SuzzmeStateLabel(title: "Microphone and Speech access are requested when you first talk to Suzzme.", symbol: "mic")
                Toggle("Speak Suzzme’s responses", isOn: Binding(
                    get: { environment.voice.speaksResponses },
                    set: { environment.voice.speaksResponses = $0 }
                ))
            }
            .frame(maxWidth: 460)
        case .permissions:
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
                Text("Connect now or later in Settings. Without access, Suzzme stays usable and tells you what it could not check.")
                    .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                ForEach(SuzzmeContextSourceKind.allCases) { source in onboardingPermissionRow(source) }
                if let error = environment.sourcePermissionError {
                    Text(error).font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
            .frame(maxWidth: 500)
            .task { await environment.refreshSourcePermissions() }
        case .personalize:
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
                Picker("Presence theme", selection: Binding(
                    get: { environment.invocation.presenceTheme },
                    set: { environment.invocation.presenceTheme = $0 }
                )) {
                    ForEach(SuzzmePresenceTheme.allCases) { theme in Text(theme.title).tag(theme) }
                }
                Text("A quiet color for the moments Suzzme is helping.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            .frame(maxWidth: 420)
        }
    }

    private func capability(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.headline)
    }

    private func onboardingPermissionRow(_ source: SuzzmeContextSourceKind) -> some View {
        let state = environment.sourcePermissions[source] ?? .notDetermined
        let details = HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.small) {
            Image(systemName: source.symbol).frame(width: 24)
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                Text(source.title).font(.headline)
                Text(source.permissionPurpose).font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: SuzzmeTheme.Spacing.small) {
                details
                Spacer(minLength: SuzzmeTheme.Spacing.small)
                onboardingPermissionAction(source, state: state)
            }
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                details
                onboardingPermissionAction(source, state: state)
            }
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private func onboardingPermissionAction(_ source: SuzzmeContextSourceKind, state: SuzzmePermissionState) -> some View {
        if state == .notDetermined || state == .writeOnly {
            Button("Allow") { Task { await environment.requestSourcePermission(source) } }
                .buttonStyle(.bordered)
                .controlSize(.large)
        } else {
            Label(state.displayName, systemImage: state == .authorized ? "checkmark.circle" : "exclamationmark.circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(SuzzmeTheme.textSecondary)
        }
    }

    private var controls: some View {
        VStack(spacing: SuzzmeTheme.Spacing.medium) {
            ProgressView(value: Double(step + 1), total: Double(pages.count))
                .tint(SuzzmeTheme.intelligencePrimary)
                .accessibilityLabel("Setup progress")
                .accessibilityValue("Step \(step + 1) of \(pages.count)")
            ViewThatFits {
                HStack(spacing: SuzzmeTheme.Spacing.small) { navigationButtons }
                VStack(spacing: SuzzmeTheme.Spacing.small) { navigationButtons }
            }
        }
    }

    @ViewBuilder private var navigationButtons: some View {
        if step > 0 {
            Button("Back") { withAnimation(reduceMotion ? nil : .easeInOut(duration: SuzzmeTheme.Motion.standard)) { step -= 1 } }
                .buttonStyle(.bordered).controlSize(.large)
        }
        Button(step == pages.count - 1 ? "Start using Suzzme" : "Continue") {
            if step == pages.count - 1 { onComplete() }
            else { withAnimation(reduceMotion ? nil : .easeInOut(duration: SuzzmeTheme.Motion.standard)) { step += 1 } }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
    }
}

private struct OnboardingPage {
    enum Kind { case profile, capabilities, availability, privacy, voice, permissions, personalize }
    let kind: Kind
    let eyebrow: LocalizedStringResource
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let symbol: String

    static let pages: [Self] = [
        .init(kind: .profile, eyebrow: "HELLO", title: "Make it personal", message: "A name is enough to begin.", symbol: "person.crop.circle"),
        .init(kind: .capabilities, eyebrow: "SUZZME", title: "A little less to hold", message: "Talk naturally. Suzzme helps organize context and prepares changes for your approval.", symbol: "sparkles"),
        .init(kind: .availability, eyebrow: "INTELLIGENCE", title: "Ready for your device", message: "Suzzme checks what this device can do and makes its limits clear.", symbol: "iphone"),
        .init(kind: .privacy, eyebrow: "ON DEVICE", title: "Private by design", message: "Suzzme uses minimum-necessary information and keeps its intelligence local whenever supported.", symbol: "lock.shield"),
        .init(kind: .voice, eyebrow: "VOICE", title: "Talk naturally", message: "Ask a question, think out loud, or pick up where you left off.", symbol: "mic"),
        .init(kind: .permissions, eyebrow: "YOUR CHOICE", title: "Connect only what helps", message: "Every source explains why it is useful before requesting access.", symbol: "hand.raised"),
        .init(kind: .personalize, eyebrow: "PRESENCE", title: "Make Suzzme yours", message: "Choose the color you’ll see when Suzzme listens and responds.", symbol: "circle.hexagongrid")
    ]
}

extension SuzzmeContextSourceKind {
    var title: String { switch self { case .calendar: "Calendar"; case .reminders: "Reminders"; case .contacts: "Contacts" } }
    var symbol: String { switch self { case .calendar: "calendar"; case .reminders: "checklist"; case .contacts: "person.crop.circle" } }
    var permissionPurpose: String {
        switch self {
        case .calendar: "Understand your schedule when you ask."
        case .reminders: "Understand tasks and commitments."
        case .contacts: "Identify people you ask about."
        }
    }
}

#Preview("Meet Suzzme") { SignInView(onContinue: {}, onGuestContinue: {}) }
#Preview("Onboarding") { OnboardingView(onComplete: {}).environment(AppEnvironment.preview) }
