import SwiftUI

/// Presentation of the existing assistant lifecycle. Greeting and rest are
/// local poses only; they cannot start capture, speech, or assistant work.
struct SuzzmeMascotPose: Equatable {
    let state: SuzzmeAssistantState
    var isGreeting = false
    var isSleeping = false

    var greets: Bool { state == .idle && isGreeting && !isSleeping }
    var sleeps: Bool { state == .idle && isSleeping }
    var thinks: Bool {
        switch state {
        case .transcribing, .understanding, .gatheringContext, .reasoning, .planning, .acting: true
        default: false
        }
    }
    var status: String {
        if sleeps { return "Suzzme resting" }
        if greets { return "Suzzme says hello" }
        return SuzzmeAssistantPresentation.make(for: state).systemStatus
    }

    func allowsMotion(isAnimated: Bool, animation: SuzzmePresenceAnimation,
                      reduceMotion: Bool, isActive: Bool, isVisible: Bool) -> Bool {
        isAnimated && animation != .minimal && !reduceMotion && isActive && isVisible
    }

    static func bounded(_ value: Double) -> CGFloat {
        value.isFinite ? CGFloat(min(max(value, 0), 1)) : 0
    }
}

/// The supplied cloud artwork is shared unchanged by iPhone, iPad and Mac.
/// Native eyelids and mouth articulation keep the original character rather
/// than swapping in an unrelated expression asset. No timer drives AI state.
struct SuzzmeMascot: View {
    var state: SuzzmeAssistantState = .idle
    var size: CGFloat = 96
    var isAnimated = true
    var animation: SuzzmePresenceAnimation = .gentle
    /// Real capture RMS, used only while listening.
    var audioLevel: Double = 0
    /// Real utterance word progress; never treated as synthesized audio RMS.
    var speechProgress: Double = 0
    var isGreeting = false
    var isSleeping = false
    var accessibilityLabel: String? = nil
    var onTap: (() -> Void)? = nil
    var characterColor: SuzzmeMascotColor? = nil

    @AppStorage(SuzzmeMascotColor.defaultsKey) private var selectedColor = SuzzmeMascotColor.blue.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var breath: CGFloat = 0
    @State private var blink: CGFloat = 0
    @State private var entrance: CGFloat = 0
    @State private var wave: Double = 0
    @State private var speechPulse: CGFloat = 0
    @State private var greetingFinished = false
    @State private var speakingFrames: SuzzmeMascotFrames?
    @State private var poseStill: SuzzmeMascotFrames?
    @State private var poseAnimation: SuzzmeMascotFrames?

    private var artworkColor: SuzzmeMascotColor {
        characterColor ?? SuzzmeMascotColor(rawValue: selectedColor) ?? .blue
    }
    private var showsSpeakingArtwork: Bool { state == .speaking && motionEnabled && speakingFrames != nil }
    private var poseArtworkName: String? {
        if pose.greets { return "wave_\(artworkColor.rawValue)" }
        if pose.thinks { return "think_\(artworkColor.rawValue)" }
        if pose.sleeps { return "sleep_\(artworkColor.rawValue)" }
        return nil
    }
    private var showsPoseArtwork: Bool { poseArtworkName != nil && poseStill != nil }

    private var pose: SuzzmeMascotPose {
        .init(state: state, isGreeting: isGreeting && !greetingFinished, isSleeping: isSleeping)
    }
    private var motionEnabled: Bool {
        pose.allowsMotion(isAnimated: isAnimated, animation: animation,
                          reduceMotion: reduceMotion, isActive: scenePhase == .active, isVisible: isVisible)
    }
    private var displaySize: CGFloat { size.isFinite ? min(max(size, 16), 320) : 96 }
    // The reference includes transparent margins. Crop only those margins in
    // the view, leaving the original PNG and its alpha channel intact.
    private var artSize: CGFloat { displaySize * 1.22 }
    private var energy: CGFloat {
        state == .listening && motionEnabled ? SuzzmeMascotPose.bounded(audioLevel) : 0
    }
    private var eyesClosed: CGFloat { pose.sleeps ? 1 : blink }
    private var lift: CGFloat {
        guard motionEnabled else { return 0 }
        return (pose.thinks ? -breath * 0.018 : -breath * 0.004) * displaySize
            - entrance * (state == .success ? 0.025 : 0.012) * displaySize
    }

    @ViewBuilder var body: some View {
        if let onTap {
            Button(action: onTap) { visibilityAwareCharacter }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(accessibilityLabel ?? "Open Suzzme")
                .accessibilityValue(pose.status)
        } else {
            visibilityAwareCharacter
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel ?? "Suzzme companion")
                .accessibilityValue(pose.status)
        }
    }

    @ViewBuilder private var visibilityAwareCharacter: some View {
        if #available(iOS 18, macOS 15, *) {
            character.onScrollVisibilityChange(threshold: 0.1) { isVisible = $0 }
        } else {
            // Geometry observation is back-deployed to iOS 16 / macOS 13.
            // An eager ScrollView keeps children mounted after scrolling away.
            character.onGeometryChange(for: Bool.self) { proxy in
                guard let viewport = proxy.bounds(of: .scrollView) else { return true }
                return viewport.intersects(CGRect(origin: .zero, size: proxy.size))
            } action: { isVisible = $0 }
        }
    }

    private var character: some View {
        ZStack {
            if showsSpeakingArtwork, let speakingFrames {
                SuzzmeSpeakingArtwork(frames: speakingFrames, maskAsset: artworkColor.assetName)
            } else if showsPoseArtwork, let poseStill, let firstFrame = poseStill.images.first {
                if motionEnabled, let poseAnimation {
                    SuzzmeAnimatedPoseArtwork(frames: poseAnimation, loops: pose.thinks)
                } else {
                    Image(decorative: firstFrame, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                }
            } else {
                Image(artworkColor.assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
            if eyesClosed > 0, !showsSpeakingArtwork, !showsPoseArtwork {
                eyelid(center: CGPoint(x: 0.395, y: 0.494), right: false)
                eyelid(center: CGPoint(x: 0.622, y: 0.479), right: true)
            }
            if speechPulse > 0, state == .speaking, !showsSpeakingArtwork {
                // A small opening inside the original smile, driven only by
                // actual word callbacks. Natural speech without word timing
                // retains the smile and the existing truthful progress field.
                Ellipse()
                    .fill(Color(red: 0.13, green: 0.09, blue: 0.07))
                    .frame(width: artSize * 0.035, height: artSize * 0.016 * speechPulse)
                    .position(x: artSize * 0.509, y: artSize * 0.552)
            }
            if wave != 0, !showsPoseArtwork {
                // A clipped copy of the supplied hand creates a tiny flutter;
                // the neutral hand remains underneath so no body pixels vanish.
                Image(artworkColor.assetName)
                    .resizable().scaledToFit()
                    .mask {
                        Ellipse().frame(width: artSize * 0.135, height: artSize * 0.15)
                            .rotationEffect(.degrees(-30))
                            .position(x: artSize * 0.705, y: artSize * 0.645)
                    }
                    .rotationEffect(.degrees(wave), anchor: UnitPoint(x: 0.70, y: 0.70))
            }
        }
        .frame(width: showsPoseArtwork ? displaySize : artSize,
               height: showsPoseArtwork ? displaySize : artSize)
        .scaleEffect(motionEnabled ? 1 + breath * (pose.sleeps ? 0.006 : 0.009) + energy * 0.018 + entrance * 0.012 : 1)
        .offset(y: lift - (showsPoseArtwork ? 0 : displaySize * 0.022))
        .rotationEffect(.degrees(motionEnabled ? (pose.greets ? entrance * -1.5 : state == .error ? -1 : 0) : 0))
        .frame(width: displaySize, height: displaySize)
        .clipped()
        .animation(motionEnabled ? .easeOut(duration: SuzzmeTheme.Motion.quick) : nil, value: energy)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: "\(motionEnabled)-\(pose.sleeps)") { await breatheAndBlink() }
        .task(id: "\(state.rawValue)-\(isGreeting)-\(isSleeping)-\(motionEnabled)") { await enterPose() }
        .task(id: "\(state.rawValue)-\(speechProgress)-\(motionEnabled)") { await articulateWord() }
        .task(id: "\(state.rawValue)-\(artworkColor.rawValue)-\(motionEnabled)") {
            guard !Task.isCancelled else { return }
            speakingFrames = nil
            guard state == .speaking, motionEnabled else { return }
            let frames = await SuzzmeMascotAnimationCache.shared.frames(named: artworkColor.animationName)
            guard !Task.isCancelled else { return }
            speakingFrames = frames
        }
        .task(id: "\(poseArtworkName ?? "idle")-\(motionEnabled)") {
            poseStill = nil
            poseAnimation = nil
            guard let name = poseArtworkName, !Task.isCancelled else { return }
            let still = await SuzzmeMascotAnimationCache.shared.frames(named: name, fileExtension: "png")
            guard !Task.isCancelled else { return }
            poseStill = still
            guard motionEnabled else { return }
            let animated = await SuzzmeMascotAnimationCache.shared.frames(named: name)
            guard !Task.isCancelled else { return }
            poseAnimation = animated
        }
    }

    private func eyelid(center: CGPoint, right: Bool) -> some View {
        ZStack {
            // Colors sampled from the supplied blue body, confined to the
            // original eyes. The rest of the artwork is never tinted by theme.
            Ellipse().fill(LinearGradient(
                colors: [artworkColor.eyelid, artworkColor.eyelid.opacity(0.98)],
                startPoint: .top, endPoint: .bottom))
                .blur(radius: artSize * 0.002)
            Path { path in
                path.move(to: CGPoint(x: artSize * 0.028, y: artSize * 0.080))
                path.addQuadCurve(to: CGPoint(x: artSize * 0.126, y: artSize * 0.080),
                                  control: CGPoint(x: artSize * 0.077, y: artSize * 0.108))
            }
            .stroke(Color(red: 0.12, green: 0.19, blue: 0.25), style: .init(lineWidth: artSize * 0.006, lineCap: .round))
        }
        .frame(width: artSize * 0.154, height: artSize * 0.169)
        .rotationEffect(.degrees(right ? 4 : -7))
        .position(x: artSize * center.x, y: artSize * center.y)
        .opacity(eyesClosed)
    }

    private func resetBreathing() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { breath = 0; blink = 0 }
    }

    private func breatheAndBlink() async {
        resetBreathing()
        guard motionEnabled, !pose.sleeps else { return }
        do {
            // Sleep between native interpolations. No display-link polling or
            // subscriptions survive disappearance, inactive scenes or Minimal.
            while !Task.isCancelled {
                let duration = pose.sleeps ? 3.8 : 2.8
                withAnimation(.easeInOut(duration: duration)) { breath = 1 }
                try await Task.sleep(for: .seconds(duration))
                withAnimation(.easeInOut(duration: duration)) { breath = 0 }
                try await Task.sleep(for: .seconds(duration))
                guard !pose.sleeps else { continue }
                withAnimation(.easeOut(duration: 0.08)) { blink = 1 }
                try await Task.sleep(for: .milliseconds(110))
                withAnimation(.easeIn(duration: 0.12)) { blink = 0 }
            }
        } catch { /* SwiftUI cancelled this presentation's task. */ }
    }

    private func enterPose() async {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { entrance = 0; wave = 0 }
        if !isGreeting { greetingFinished = false }
        guard pose.greets || state == .success else { return }
        guard motionEnabled else {
            if pose.greets {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard !Task.isCancelled else { return }
                greetingFinished = true
            }
            return
        }
        withAnimation(.easeOut(duration: SuzzmeTheme.Motion.standard)) { entrance = 1 }
        do {
            if pose.greets {
                for _ in 0..<2 {
                    withAnimation(.easeInOut(duration: 0.22)) { wave = -5 }
                    try await Task.sleep(for: .milliseconds(220))
                    withAnimation(.easeInOut(duration: 0.22)) { wave = 0 }
                    try await Task.sleep(for: .milliseconds(220))
                }
                // Give the supplied wave sequence time to finish before
                // returning to the neutral idle artwork.
                try await Task.sleep(for: .seconds(max((poseAnimation?.duration ?? 3.24) - 0.88, 0)))
                greetingFinished = true
            } else {
                try await Task.sleep(for: .milliseconds(400))
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: SuzzmeTheme.Motion.calm)) { entrance = 0 }
        } catch { /* A newer state owns the pose. */ }
    }

    private func articulateWord() async {
        speechPulse = 0
        guard motionEnabled, state == .speaking, speechProgress.isFinite,
              speechProgress > 0, speechProgress < 1 else { return }
        withAnimation(.easeOut(duration: 0.06)) { speechPulse = 1 }
        do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.1)) { speechPulse = 0 }
    }
}

#Preview("Cloud companion") {
    HStack {
        SuzzmeMascot(size: 128, isGreeting: true)
        SuzzmeMascot(state: .listening, size: 80, audioLevel: 0.4)
        SuzzmeMascot(size: 80, isSleeping: true)
    }.padding()
}
