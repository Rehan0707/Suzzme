import Foundation

enum LaunchPhase: Equatable { case splash, authentication, mascotSelection, onboarding, app }

enum AccountWelcomeProgress {
    static func colorChosenKey(for uid: String) -> String { "suzzme.account.\(uid).colorChosen" }
    static func onboardingCompleteKey(for uid: String) -> String { "suzzme.account.\(uid).onboardingComplete" }
    static func colorKey(for uid: String) -> String { "suzzme.account.\(uid).mascotColor" }

    // Guest access is an explicit choice for this launch, never a substitute
    // for restoring a signed-in account on the next launch.
    static func launchPhase(uid: String?, defaults: UserDefaults) -> LaunchPhase {
        phase(uid: uid, guest: false, defaults: defaults)
    }

    static func phase(uid: String?, guest: Bool, defaults: UserDefaults) -> LaunchPhase {
        if let uid {
            if !defaults.bool(forKey: colorChosenKey(for: uid)) { return .mascotSelection }
            return defaults.bool(forKey: onboardingCompleteKey(for: uid)) ? .app : .onboarding
        }
        guard guest else { return .authentication }
        guard defaults.bool(forKey: "suzzme.mascot.didChooseColor") else { return .mascotSelection }
        return defaults.bool(forKey: "hasCompletedWelcome") ? .app : .onboarding
    }
}
