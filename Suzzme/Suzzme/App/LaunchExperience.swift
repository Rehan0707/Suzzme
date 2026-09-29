import SwiftUI

enum LaunchPhase: Equatable { case splash, authentication, onboarding, app }

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        ZStack {
            SuzzmeTheme.backgroundPrimary.ignoresSafeArea()
            SuzzmeFace(color: .primary, lineWidth: 5)
                .frame(width: 104, height: 104)
                .scaleEffect(isVisible || reduceMotion ? 1 : 0.9)
                .opacity(isVisible || reduceMotion ? 1 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Suzzme")
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: SuzzmeTheme.Motion.calm)) { isVisible = true }
        }
    }
}

/// Account sync is not part of the current local build. This screen states that
/// boundary explicitly instead of presenting non-functional credentials.
struct SignInView: View {
    let onContinue: () -> Void
    let onGuestContinue: () -> Void

    var body: some View {
        ZStack {
            SuzzmeTheme.launchGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: SuzzmeTheme.Spacing.extraLarge) {
                    Spacer(minLength: SuzzmeTheme.Spacing.hero)
                    SuzzmeFace(color: .primary, lineWidth: 5)
                        .frame(width: 112, height: 112)
                    VStack(spacing: SuzzmeTheme.Spacing.small) {
                        Text("Meet Suzzme").font(.largeTitle.weight(.bold))
                        Text("A quiet intelligence layer for the things that matter in your day.")
                            .font(.title3)
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Get Started", action: onGuestContinue)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: 360)
                        .accessibilityHint("Continues with local, on-device setup")
                    Label("No account needed. Your information stays on this device.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                        .multilineTextAlignment(.center)
                    Text("Account sync is not available.")
                        .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                    Spacer(minLength: SuzzmeTheme.Spacing.large)
                }
                .padding(SuzzmeTheme.Spacing.large)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct OnboardingView: View {
    let onComplete: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @AppStorage("suzzme.profile.name") private var profileName = "Rehan"
    @State private var step = 0
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
                    .font(.largeTitle.weight(.bold))
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
        return HStack(spacing: SuzzmeTheme.Spacing.small) {
            Image(systemName: source.symbol).frame(width: 24)
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                Text(source.title).font(.headline)
                Text(source.permissionPurpose).font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            Spacer()
            if state == .notDetermined || state == .writeOnly {
                Button("Allow") { Task { await environment.requestSourcePermission(source) } }
                    .buttonStyle(.bordered)
            } else {
                Text(state.displayName).font(.caption.weight(.medium))
            }
        }
        .frame(minHeight: 44)
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
            Button("Back") { withAnimation(.easeInOut(duration: SuzzmeTheme.Motion.standard)) { step -= 1 } }
                .buttonStyle(.bordered).controlSize(.large)
        }
        Button(step == pages.count - 1 ? "Start using Suzzme" : "Continue") {
            if step == pages.count - 1 { onComplete() }
            else { withAnimation(.easeInOut(duration: SuzzmeTheme.Motion.standard)) { step += 1 } }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
    }
}

private struct OnboardingPage {
    enum Kind { case profile, capabilities, privacy, voice, permissions, personalize }
    let kind: Kind
    let eyebrow: LocalizedStringResource
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let symbol: String

    static let pages: [Self] = [
        .init(kind: .profile, eyebrow: "HELLO", title: "Make it personal", message: "A name is enough to begin.", symbol: "person.crop.circle"),
        .init(kind: .capabilities, eyebrow: "SUZZME", title: "A little less to hold", message: "Talk naturally. Suzzme helps organize context and prepares changes for your approval.", symbol: "sparkles"),
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
