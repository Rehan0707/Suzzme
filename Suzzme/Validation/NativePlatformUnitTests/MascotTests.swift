import Testing
@testable import Suzzme

struct MascotTests {
    @Test func cancelledColorLoadCannotEvictCurrentAnimation() async throws {
        let cache = SuzzmeMascotAnimationCache()
        let initial = await cache.frames(named: SuzzmeMascotColor.blue.animationName)
        let blue = try #require(initial)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await cache.frames(named: SuzzmeMascotColor.pink.animationName)
        }
        let discarded = await cancelled.value
        #expect(discarded == nil)
        let retained = await cache.frames(named: SuzzmeMascotColor.blue.animationName)
        let sameBlue = try #require(retained)
        #expect(blue.images.first === sameBlue.images.first)
    }

    @Test func suppliedSpeakingResourcesDecodeAndRespectFrameTiming() async throws {
        for color in SuzzmeMascotColor.allCases {
            let decoded = await SuzzmeMascotAnimationCache.shared.frames(named: color.animationName)
            let frames = try #require(decoded, "Missing packaged animation: \(color.title)")
            #expect(frames.images.count == 16)
            #expect(abs(frames.duration - 1.44) < 0.001)
            #expect(frames.index(at: 0) == 0)
            #expect(frames.index(at: frames.duration - 0.01) == 15)
            #expect(frames.index(at: frames.duration) == 0)
            #expect(frames.index(at: .infinity) == 0)
            #expect(frames.index(at: -.infinity) == 0)
        }
    }

    @Test(arguments: SuzzmeAssistantState.allCases)
    func activeWorkOverridesWelcomeAndRest(_ state: SuzzmeAssistantState) {
        let pose = SuzzmeMascotPose(state: state, isGreeting: true, isSleeping: true)
        if state == .idle {
            #expect(pose.sleeps)
            #expect(!pose.greets)
            #expect(pose.status == "Suzzme resting")
        } else {
            #expect(!pose.sleeps)
            #expect(!pose.greets)
            #expect(pose.status == SuzzmeAssistantPresentation.make(for: state).systemStatus)
        }
    }

    @Test func suspendedPresentationNeverAnimates() {
        let pose = SuzzmeMascotPose(state: .listening)
        #expect(pose.allowsMotion(isAnimated: true, animation: .gentle,
                                  reduceMotion: false, isActive: true, isVisible: true))
        #expect(!pose.allowsMotion(isAnimated: false, animation: .gentle,
                                   reduceMotion: false, isActive: true, isVisible: true))
        #expect(!pose.allowsMotion(isAnimated: true, animation: .minimal,
                                   reduceMotion: false, isActive: true, isVisible: true))
        #expect(!pose.allowsMotion(isAnimated: true, animation: .gentle,
                                   reduceMotion: true, isActive: true, isVisible: true))
        #expect(!pose.allowsMotion(isAnimated: true, animation: .gentle,
                                   reduceMotion: false, isActive: false, isVisible: true))
        #expect(!pose.allowsMotion(isAnimated: true, animation: .gentle,
                                   reduceMotion: false, isActive: true, isVisible: false))
    }

    @Test func malformedAudioCannotCorruptGeometry() {
        #expect(SuzzmeMascotPose.bounded(.nan) == 0)
        #expect(SuzzmeMascotPose.bounded(.infinity) == 0)
        #expect(SuzzmeMascotPose.bounded(-1) == 0)
        #expect(SuzzmeMascotPose.bounded(2) == 1)
        #expect(SuzzmeMascotPose.bounded(0.4) == 0.4)
    }
}
