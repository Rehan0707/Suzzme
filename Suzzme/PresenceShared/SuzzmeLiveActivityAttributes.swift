#if os(iOS)
import ActivityKit
import Foundation

/// Public-surface data only: no transcript, response, contact, or action details.
struct SuzzmeLiveActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        let phase: Phase
        var appearance: SuzzmeLiveActivityAppearance = .blue
        var motionEnabled = true
        var design: SuzzmeLiveActivityDesign = .companion

        private enum CodingKeys: String, CodingKey { case phase, appearance, motionEnabled, design }

        init(phase: Phase, appearance: SuzzmeLiveActivityAppearance = .blue,
             motionEnabled: Bool = true, design: SuzzmeLiveActivityDesign = .companion) {
            self.phase = phase
            self.appearance = appearance
            self.motionEnabled = motionEnabled
            self.design = design
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            phase = try values.decode(Phase.self, forKey: .phase)
            appearance = try values.decodeIfPresent(SuzzmeLiveActivityAppearance.self, forKey: .appearance) ?? .blue
            motionEnabled = try values.decodeIfPresent(Bool.self, forKey: .motionEnabled) ?? true
            design = try values.decodeIfPresent(SuzzmeLiveActivityDesign.self, forKey: .design) ?? .companion
        }
    }

    var startedAt: Date = .now
    typealias Phase = SuzzmeLiveActivityPhase
}
#endif
