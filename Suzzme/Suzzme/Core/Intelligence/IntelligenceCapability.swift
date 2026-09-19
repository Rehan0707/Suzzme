import Foundation

enum IntelligenceCapability: Sendable, Equatable {
    case available
    case unsupportedOS
    case unsupportedDevice
    case appleIntelligenceDisabled
    case modelNotReady

    var usesFoundationModels: Bool { self == .available }

    var displayDescription: String {
        switch self {
        case .available: "Apple Intelligence is ready on this device."
        case .unsupportedOS: "This version of the operating system does not include Apple’s on-device language model."
        case .unsupportedDevice: "This device is not eligible for Apple Intelligence."
        case .appleIntelligenceDisabled: "Apple Intelligence is not enabled on this device."
        case .modelNotReady: "The on-device language model is still preparing."
        }
    }
}
