import Foundation

enum SuzzmeSyncPolicy: String, Codable, Sendable { case deviceLocal, syncAllowed, syncRedacted, neverSync }
enum SuzzmeSyncPayloadKind: String, Codable, Sendable { case preference, dailyContext, summaryMetadata, sourceConfiguration, memory, transcript, audio, prompt, diagnostic, actionAuthorization }

struct SuzzmeSyncDescriptor: Codable, Sendable, Equatable {
    let kind: SuzzmeSyncPayloadKind
    let sensitivity: SuzzmeContextSensitivity
    let containsRawContent: Bool
}

enum SuzzmeSyncPrivacyPolicy {
    static func policy(for descriptor: SuzzmeSyncDescriptor) -> SuzzmeSyncPolicy {
        if descriptor.sensitivity == .restricted { return .neverSync }
        switch descriptor.kind {
        case .transcript, .audio, .prompt, .actionAuthorization: return .neverSync
        case .memory, .dailyContext: return descriptor.sensitivity >= .sensitive ? .deviceLocal : .syncRedacted
        case .sourceConfiguration: return descriptor.containsRawContent ? .deviceLocal : .syncRedacted
        case .diagnostic: return descriptor.containsRawContent ? .neverSync : .syncRedacted
        case .preference, .summaryMetadata: return descriptor.sensitivity >= .sensitive ? .deviceLocal : descriptor.containsRawContent ? .syncRedacted : .syncAllowed
        }
    }
}

struct SuzzmeDeviceCapabilities: Codable, Sendable, Equatable {
    let deviceID: String
    let canPresentPresence: Bool
    let canSpeak: Bool
    let canDeliverNotifications: Bool
    let availableSources: Set<InformationSourceID>
    let isOnline: Bool
}

struct SuzzmeVersionedValue<Value: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    let value: Value
    let modifiedAt: Date
    let deviceID: String
}

enum SuzzmeCrossDevicePolicy {
    static func resolve<Value>(_ left: SuzzmeVersionedValue<Value>, _ right: SuzzmeVersionedValue<Value>) -> SuzzmeVersionedValue<Value> {
        if left.modifiedAt != right.modifiedAt { return left.modifiedAt > right.modifiedAt ? left : right }
        if left.deviceID != right.deviceID { return left.deviceID < right.deviceID ? left : right }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let a = (try? encoder.encode(left.value)) ?? Data()
        let b = (try? encoder.encode(right.value)) ?? Data()
        return a.lexicographicallyPrecedes(b) ? left : right
    }

    static func deliveryOwner(for deliveryID: String, devices: [SuzzmeDeviceCapabilities]) -> String? {
        let capable = Array(Set(devices.filter { $0.isOnline && $0.canDeliverNotifications }.map(\.deviceID))).sorted()
        guard !capable.isEmpty else { return nil }
        let hash = deliveryID.utf8.reduce(0) { (($0 &* 31) &+ Int($1)) & Int.max }
        return capable[hash % capable.count]
    }

    static func duplicateIdentity(kind: String, sourceIdentity: String, semanticKey: String) -> String {
        [kind, sourceIdentity, semanticKey].map { $0.lowercased() }.map { "\($0.utf8.count):\($0)" }.joined()
    }
}
