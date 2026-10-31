import SwiftUI

struct PresenceSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage(SuzzmeMascotColor.defaultsKey) private var characterColor = SuzzmeMascotColor.blue.rawValue
    @State private var posePreview = 0
    #if os(iOS)
    @Environment(\.suzzmeApplicationRuntime) private var applicationRuntime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SuzzmeLiveActivityDesign.defaultsKey) private var liveActivityDesignRawValue = SuzzmeLiveActivityDesign.companion.rawValue
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
                dynamicIslandSettings
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

    private var dynamicIslandSettings: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            Text("Dynamic Island")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Picker("Live Activity design", selection: $liveActivityDesignRawValue) {
                ForEach(SuzzmeLiveActivityDesign.allCases) { design in
                    Text(design.title).tag(design.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Text(liveActivityDesign.description)
                .font(.caption).foregroundStyle(.secondary)
            SuzzmeDynamicIslandDesignPreview(design: liveActivityDesign, phase: previewPhase)
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
private struct SuzzmeDynamicIslandDesignPreview: View {
    let design: SuzzmeLiveActivityDesign
    let phase: SuzzmeLiveActivityPhase

    private var leadingSymbol: String {
        switch design {
        case .companion: "face.smiling.fill"
        case .briefing: "sun.horizon.fill"
        case .focus: phase.symbol
        }
    }
    private var trailingText: String {
        design == .briefing ? phase.compactLabel : "Suzzme"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
            Label("Design preview only", systemImage: "eye")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: SuzzmeTheme.Spacing.small) {
                Text("Minimal").font(.caption2).frame(width: 54, alignment: .leading)
                Image(systemName: design == .briefing ? "sun.horizon.fill" : design == .companion ? "face.smiling.fill" : phase.symbol)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(.black, in: Circle())
                    .accessibilityLabel("Minimal Dynamic Island preview")
                Text("Compact").font(.caption2).frame(width: 56, alignment: .leading)
                HStack(spacing: 9) {
                    Image(systemName: leadingSymbol).font(.system(size: 15, weight: .semibold))
                    Text(trailingText).font(.caption2.weight(.semibold)).lineLimit(1)
                }
                .foregroundStyle(.white).padding(.horizontal, 12).frame(height: 40)
                .background(.black, in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Compact Dynamic Island preview, \(design.title)")
            }
            HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.small) {
                Text("Expanded").font(.caption2).frame(width: 54, alignment: .leading).padding(.top, 14)
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: leadingSymbol).font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                        .frame(width: 32, height: 32).background(.white.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(design == .briefing ? "Daily briefing" : "Suzzme")
                            .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.72))
                        Text(phase.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Text(phase.detail).font(.caption2).foregroundStyle(.white.opacity(0.72)).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Expanded Dynamic Island preview, \(design.title), \(phase.title)")
            }
        }
        .padding(SuzzmeTheme.Spacing.medium)
        .background(SuzzmeTheme.surface, in: RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.largeSurface))
    }
}
#endif
