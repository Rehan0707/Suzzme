import SwiftUI
import FirebaseAuth
#if os(macOS)
import AppKit
#endif

struct SplashView: View {
    var body: some View {
        ZStack {
            SuzzmeTheme.backgroundPrimary.ignoresSafeArea()
            SuzzmeMascot(size: 104, isAnimated: false)
                .accessibilityHidden(true)
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
    @State private var showsGmailSetup = false
    @State private var selectedSummaryTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
    private let pages = OnboardingPage.pages

    var body: some View {
        ZStack {
            SuzzmeTheme.launchGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                GeometryReader { geometry in
                    ScrollView {
                        pageContent
                            .id(step)
                            .transition(.opacity)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: geometry.size.height, alignment: .center)
                    }
                    .scrollIndicators(.hidden)
                }
                controls
            }
            .padding(.horizontal, SuzzmeTheme.Spacing.large)
            .padding(.vertical, SuzzmeTheme.Spacing.medium)
            .frame(maxWidth: SuzzmeTheme.Layout.readingWidth)
            .frame(maxWidth: .infinity)
        }
        .suzzmeSelectionFeedback(trigger: step)
        .sheet(isPresented: $showsGmailSetup) {
            NavigationStack {
                ScrollView { GmailConnectionView().padding(SuzzmeTheme.Spacing.large) }
                    .navigationTitle("Gmail")
                    .toolbar { Button("Done") { showsGmailSetup = false } }
            }
            .frame(minWidth: 480, minHeight: 400)
        }
        .onAppear {
            var calendar = Calendar.current
            calendar.timeZone = TimeZone(identifier: environment.proactivePreferences.timeZoneIdentifier) ?? .current
            selectedSummaryTime = calendar.date(bySettingHour: environment.proactivePreferences.briefingHour,
                                                minute: environment.proactivePreferences.briefingMinute,
                                                second: 0, of: .now) ?? selectedSummaryTime
            guard profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let user = CompanionSummaryStore.currentUser else { return }
            let accountName = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !accountName.isEmpty {
                profileName = accountName
            } else if let localPart = user.email?.split(separator: "@").first {
                profileName = localPart.replacingOccurrences(of: ".", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
            }
        }
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
            Text("\(step + 1) of \(pages.count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .accessibilityHidden(true)
            Button("Skip", action: onComplete)
                .buttonStyle(.plain)
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .padding(.horizontal, SuzzmeTheme.Spacing.small)
                .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                .accessibilityLabel("Skip setup")
        }
    }

    @ViewBuilder private var pageContent: some View {
        let page = pages[step]
        VStack(spacing: SuzzmeTheme.Spacing.large) {
            SuzzmeMascot(state: environment.presenceState, size: SuzzmeTheme.Layout.companionFace,
                animation: environment.invocation.presenceAnimation,
                isGreeting: step == 0)
                .accessibilityHidden(true)
            VStack(spacing: SuzzmeTheme.Spacing.xs) {
                Text(page.eyebrow)
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                Text(page.title)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(page.message)
                    .font(.body)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 500)
            pageDetails(page.kind)
                .padding(.top, SuzzmeTheme.Spacing.small)
        }
        .frame(maxWidth: 560)
        .padding(.vertical, SuzzmeTheme.Spacing.extraLarge)
    }

    @ViewBuilder private func pageDetails(_ kind: OnboardingPage.Kind) -> some View {
        switch kind {
        case .profile:
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                Text("What should Suzzme call you?").font(.headline)
                TextField("Your name", text: $profileName)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SuzzmeTheme.Spacing.medium)
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                    .background(SuzzmeTheme.backgroundSecondary, in: Capsule())
                    .overlay(Capsule().strokeBorder(SuzzmeTheme.separator, lineWidth: 1))
                    .textContentType(.name)
                    .submitLabel(.done)
                Label("Stored only on this device. Change it anytime in Settings.", systemImage: "lock")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            .frame(maxWidth: 420)
        case .capabilities:
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
                capability("Talk naturally", "Ask by voice or by typing.", "waveform")
                capability("Understand your day", "Your schedule and tasks, in context.", "calendar")
                capability("Remember what matters", "Keep useful details close.", "square.stack.3d.up")
                capability("Help with changes you approve", "Nothing changes without your OK.", "checkmark.shield")
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
        case .summaryTime:
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
                DatePicker("Preferred time", selection: $selectedSummaryTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .font(.headline)
                    .accessibilityHint("Choose when Suzzme prepares your Daily Summary each day")
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                #if os(macOS)
                Text("Suzzme will prepare your summary from sources you’ve enabled. Automatic preparation runs while Suzzme is open and your Mac is awake.")
                    .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                #else
                Text("This preferred time is shared with your Suzzme account. Your Mac prepares the summary; automatic preparation must be enabled there.")
                    .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                #endif
                Text("You can change this anytime in Settings → Daily Summary.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            .frame(maxWidth: 460, alignment: .leading)
        case .privacy:
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
                capability("On-device first", "Your information stays close to you.", "iphone")
                capability("Minimum necessary access", "Choose the sources Suzzme can use.", "hand.raised")
                capability("Your information, your choice", "Review memory and sources anytime.", "lock.shield")
            }
            .frame(maxWidth: 460)
        case .macCompanion:
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
                capability("Use the same account on Mac", "Sign in to connect your devices.", "desktopcomputer")
                capability("Choose your sources on Mac", "You decide what Suzzme can read.", "tray.2")
                capability("Share your Daily Summary", "Turn on iPhone sharing in Mac settings.", "arrow.triangle.2.circlepath")
                Text("This iPhone can show the prepared result without requesting the Mac’s app permissions. You can finish Mac setup later.")
                    .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            .frame(maxWidth: 500)
        case .voice:
            VStack(spacing: SuzzmeTheme.Spacing.medium) {
                #if os(iOS)
                SuzzmeStateLabel(title: "Your Mac prepares your day. This iPhone reads the shared summary aloud.", symbol: "speaker.wave.2")
                #else
                SuzzmeStateLabel(title: "Microphone and Speech access are requested when you first talk to Suzzme.", symbol: "mic")
                #endif
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
                #if os(macOS)
                HStack(spacing: SuzzmeTheme.Spacing.small) {
                    appleAppIcon(bundleID: "com.apple.mail", fallback: "envelope")
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                        Text("Apple Mail").font(.headline)
                        Text("Apple Mail access is not available yet.").font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                    Spacer()
                    Text("Unavailable").font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                }.frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                HStack(spacing: SuzzmeTheme.Spacing.small) {
                    Image(systemName: "envelope").frame(width: 32).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                        Text("Gmail").font(.headline)
                        Text("Connect Google and choose what Suzzme can read.").font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                    Spacer()
                    Button(environment.gmailAccount.isConnected ? "Manage" : "Connect") { showsGmailSetup = true }
                        .buttonStyle(.bordered)
                }.frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                #endif
                if let error = environment.sourcePermissionError {
                    Text(error).font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
            .frame(maxWidth: 500)
            .task { await environment.refreshSourcePermissions(); await environment.restoreGmailSignIn() }
        }
    }

    private func capability(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        HStack(alignment: .center, spacing: SuzzmeTheme.Spacing.medium) {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                .frame(width: SuzzmeTheme.Layout.touchTarget, height: SuzzmeTheme.Layout.touchTarget)
                .background(SuzzmeTheme.intelligenceSurface, in: RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.control))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func onboardingPermissionRow(_ source: SuzzmeContextSourceKind) -> some View {
        let state = environment.sourcePermissions[source] ?? .notDetermined
        let details = HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.small) {
            #if os(macOS)
            appleAppIcon(bundleID: source == .calendar ? "com.apple.iCal" : source == .reminders ? "com.apple.reminders" : "com.apple.AddressBook", fallback: source.symbol)
            #else
            Image(systemName: source.symbol).frame(width: 32).accessibilityHidden(true)
            #endif
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

    #if os(macOS)
    @ViewBuilder private func appleAppIcon(bundleID: String, fallback: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
        } else {
            Image(systemName: fallback).frame(width: 32, height: 32).accessibilityHidden(true)
        }
    }
    #endif

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
            HStack(spacing: SuzzmeTheme.Spacing.xs) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? SuzzmeTheme.intelligencePrimary : SuzzmeTheme.separator)
                        .frame(width: index == step ? 24 : 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Setup progress")
            .accessibilityValue("Step \(step + 1) of \(pages.count)")
            navigationButtons
        }
        .padding(.top, SuzzmeTheme.Spacing.medium)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }

    private var navigationButtons: some View {
        VStack(spacing: SuzzmeTheme.Spacing.xs) {
            Button {
                Task { @MainActor in
                    if pages[step].kind == .summaryTime { await saveSummarySchedule() }
                    if step == pages.count - 1 { onComplete() }
                    else { withAnimation(SuzzmeTheme.Motion.disclosure(reduceMotion: reduceMotion)) { step += 1 } }
                }
            } label: {
                Text(step == pages.count - 1 ? "Start using Suzzme" : "Continue")
                    .font(.headline)
                    .foregroundStyle(SuzzmeTheme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: SuzzmeTheme.Layout.touchTarget)
                    .contentShape(Capsule())
                    .suzzmeGlassControlSurface(cornerRadius: SuzzmeTheme.Layout.touchTarget / 2)
            }
            .buttonStyle(.plain)
            .controlSize(.large)
            if step > 0 {
                Button("Back") { withAnimation(SuzzmeTheme.Motion.disclosure(reduceMotion: reduceMotion)) { step -= 1 } }
                    .buttonStyle(.plain)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
            }
        }
    }

    private func saveSummarySchedule() async {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let components = calendar.dateComponents([.hour, .minute], from: selectedSummaryTime)
        var preferences = environment.proactivePreferences
        preferences.dailyBriefingEnabled = true
        preferences.briefingHour = components.hour ?? 8
        preferences.briefingMinute = components.minute ?? 0
        preferences.timeZoneIdentifier = TimeZone.current.identifier
        await environment.updateProactivePreferences(preferences)
        #if os(macOS)
        environment.scheduledBriefing.setEnabled(true)
        #endif
    }
}

private struct OnboardingPage {
    enum Kind { case profile, capabilities, availability, privacy, macCompanion, summaryTime, voice, permissions }
    let kind: Kind
    let eyebrow: LocalizedStringResource
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let symbol: String

    static var pages: [Self] {
        #if os(iOS)
        return [
            .init(kind: .profile, eyebrow: "HELLO", title: "Make it personal", message: "A name is enough to begin.", symbol: "person.crop.circle"),
            .init(kind: .macCompanion, eyebrow: "YOUR MAC", title: "Your day comes with you", message: "Your Mac prepares your schedule and what matters today. This iPhone receives and reads the result.", symbol: "desktopcomputer"),
            .init(kind: .summaryTime, eyebrow: "DAILY SUMMARY", title: "Select a preferred time for summarizing your day", message: "Pick when you’d like Suzzme to prepare your day.", symbol: "sun.horizon"),
            .init(kind: .voice, eyebrow: "VOICE", title: "Listen to your day", message: "Choose when Suzzme may read your shared summaries aloud.", symbol: "speaker.wave.2")
        ]
        #else
        var result: [Self] = [
            .init(kind: .profile, eyebrow: "HELLO", title: "Make it personal", message: "A name is enough to begin.", symbol: "person.crop.circle"),
            .init(kind: .capabilities, eyebrow: "SUZZME", title: "A little less to hold", message: "Talk naturally. Suzzme helps organize context and prepares changes for your approval.", symbol: "sparkles"),
            .init(kind: .availability, eyebrow: "INTELLIGENCE", title: "Ready for your device", message: "Suzzme checks what this device can do and makes its limits clear.", symbol: "iphone"),
            .init(kind: .privacy, eyebrow: "PRIVACY", title: "Private by design", message: "Suzzme uses only the information you allow.", symbol: "lock.shield")
        ]
        #if os(iOS)
        result.append(.init(kind: .macCompanion, eyebrow: "YOUR MAC", title: "Your day comes with you", message: "Your Mac prepares the Daily Summary. This iPhone shows what you choose to share.", symbol: "desktopcomputer"))
        #else
        result.append(.init(kind: .permissions, eyebrow: "YOUR CHOICE", title: "Connect only what helps", message: "Every source explains why it is useful before requesting access.", symbol: "hand.raised"))
        #endif
        result.append(.init(kind: .summaryTime, eyebrow: "DAILY SUMMARY", title: "Select a preferred time for summarizing your day", message: "Pick when you’d like Suzzme to prepare your day.", symbol: "sun.horizon"))
        result.append(.init(kind: .voice, eyebrow: "VOICE", title: "Talk naturally", message: "Ask a question, think out loud, or pick up where you left off.", symbol: "mic"))
        return result
        #endif
    }
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
