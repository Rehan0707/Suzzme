import SwiftUI

struct PresenceSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage(SuzzmeMascotColor.defaultsKey) private var characterColor = SuzzmeMascotColor.blue.rawValue
    @State private var posePreview = 0
    #if os(iOS)
    @Environment(\.suzzmeApplicationRuntime) private var applicationRuntime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SuzzmeLiveActivityDesign.defaultsKey) private var liveActivityDesignRawValue = SuzzmeLiveActivityDesign.companion.rawValue
    @AppStorage(SuzzmeLiveActivityPhase.enabledDefaultsKey) private var liveActivitiesEnabled = true
    @State private var previewStep = 0
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.extraLarge) {
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                    Text("Choose your companion")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    SuzzmeMascotColorOrbit(selection: Binding(
                        get: { SuzzmeMascotColor(rawValue: characterColor) ?? .blue },
                        set: { characterColor = $0.rawValue }
                    ))
                    Text("Your companion’s color also colors Suzzme’s presence, controls, and app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
                    Text("Meet Suzzme’s poses")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Picker("Preview pose", selection: $posePreview) {
                        Text("Wave").tag(0)
                        Text("Think").tag(1)
                        Text("Rest").tag(2)
                    }
                    .pickerStyle(.segmented)
                    SuzzmeMascot(
                        state: posePreview == 1 ? .reasoning : .idle,
                        size: 144,
                        animation: environment.invocation.presenceAnimation,
                        isGreeting: posePreview == 0,
                        isSleeping: posePreview == 2,
                        characterColor: SuzzmeMascotColor(rawValue: characterColor) ?? .blue
                    )
                    .id("\(posePreview)-\(characterColor)")
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(["Suzzme waving", "Suzzme thinking", "Suzzme resting"][posePreview])
                }

                #if os(iOS)
                liveActivitySettings
                #endif

                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
                    Text("Appearance")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                #if os(macOS)
                    Toggle("Show companion near cursor", isOn: Binding(
                        get: { environment.invocation.cursorCompanionEnabled },
                        set: { environment.invocation.cursorCompanionEnabled = $0 }
                    ))
                    Text("Shows responses near your pointer. With approved screen guidance, it briefly moves beside the verified target, then returns. Reduce Motion and Minimal keep it still. It never clicks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider()
                #endif
                    Picker("Presence animation", selection: Binding(
                        get: { environment.invocation.presenceAnimation },
                        set: { environment.invocation.presenceAnimation = $0 }
                    )) {
                        ForEach(SuzzmePresenceAnimation.allCases) { animation in
                            Text(animation.title).tag(animation)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("Reduce Motion always replaces animated effects with calm state changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, SuzzmeTheme.Layout.compactInset)
            .padding(.top, SuzzmeTheme.Spacing.large)
            .padding(.bottom, SuzzmeTheme.Spacing.extraLarge)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SuzzmeTheme.pageBackground)
        .tint(SuzzmeTheme.accent)
        .navigationTitle("Suzzme Presence")
        .onChange(of: characterColor) { _, rawValue in
            let color = SuzzmeMascotColor(rawValue: rawValue) ?? .blue
            SuzzmeMascotAppearance.shared.synchronizeStoredColor(rawValue)
            #if os(macOS)
            SuzzmeAppIconController.apply(color)
            #endif
        }
        #if os(iOS)
        .onChange(of: liveActivityDesignRawValue) { _, _ in
            applicationRuntime?.updateLiveActivity(reduceMotion: reduceMotion)
        }
        .onChange(of: liveActivitiesEnabled) { _, _ in
            applicationRuntime?.updateLiveActivity(reduceMotion: reduceMotion)
            Task { await CompanionPushRegistration.shared.synchronize() }
        }
        #endif
    }

    #if os(iOS)
    private var liveActivityDesign: SuzzmeLiveActivityDesign {
        SuzzmeLiveActivityDesign(rawValue: liveActivityDesignRawValue) ?? .companion
    }

    private var previewPhase: SuzzmeLiveActivityPhase {
        switch previewStep % 3 {
        case 1: .speaking
        case 2: .summaryReady
        default: .understanding
        }
    }

    private var liveActivitySettings: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            Text("Live Activities")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Toggle("Show Live Activities", isOn: $liveActivitiesEnabled)
            Text("Shows status for active sessions on the Lock Screen and supported Dynamic Island. Your Home Screen widget keeps a separate snapshot. You can also manage Live Activities in iPhone Settings.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Live Activity design", selection: $liveActivityDesignRawValue) {
                ForEach(SuzzmeLiveActivityDesign.allCases) { design in
                    Text(design.title).tag(design.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Text(liveActivityDesign.description)
                .font(.caption).foregroundStyle(.secondary)
            SuzzmePresenceStylePreview(design: liveActivityDesign, phase: previewPhase)
            HStack {
                Button("Animate preview", systemImage: "play.fill") {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)) {
                        previewStep = (previewStep + 1) % 3
                    }
                }
                .buttonStyle(.bordered)
                Button("Reset preview", systemImage: "arrow.counterclockwise") {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        previewStep = 0
                        liveActivityDesignRawValue = SuzzmeLiveActivityDesign.companion.rawValue
                    }
                }
                .buttonStyle(.bordered)
            }
            Text("Preview uses fixed, generic states only; it does not read your accounts or start a real Live Activity. The production Island follows Suzzme’s actual assistant and summary lifecycle and never displays email or message contents.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Dynamic Island layouts appear on supported iPhone models. Live Activities may also appear on the Lock Screen, subject to iOS settings and system limits.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    #endif
}

#if os(iOS)
/// A regular app-owned style example, not a replica of system Island geometry.
private struct SuzzmePresenceStylePreview: View {
    let design: SuzzmeLiveActivityDesign
    let phase: SuzzmeLiveActivityPhase

    var body: some View {
        HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.small) {
            if design == .companion {
                SuzzmeCharacterArtwork().frame(width: 40, height: 40)
            } else {
                Image(systemName: design == .briefing ? "sun.horizon.fill" : phase.symbol)
                    .font(.title2).foregroundStyle(SuzzmeTheme.intelligencePrimary)
                    .frame(width: 40, height: 40).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                Text(phase.title).font(.headline)
                Text(phase.detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(SuzzmeTheme.Spacing.medium)
        .background(SuzzmeTheme.surface, in: RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Style example, \(design.title), \(phase.title)")
    }
}
#endif
