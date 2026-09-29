import Foundation
import os

enum SuzzmeSettingsCapabilityID: String, Codable, Sendable, CaseIterable {
    case dailySummary, timeCriticalIntelligence, preparedAssistance, presenceTheme, presenceAnimation
}

enum SuzzmeSettingsOperation: String, Codable, Sendable { case read, update }

enum SuzzmeSettingsValue: Codable, Sendable, Equatable {
    case enabled(Bool)
    case summaryTime(hour: Int, minute: Int, timeZoneIdentifier: String)
    case presenceTheme(String)
    case presenceAnimation(String)
}

struct SuzzmeSettingsPlan: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let requestID: UUID
    let capability: SuzzmeSettingsCapabilityID
    let operation: SuzzmeSettingsOperation
    let value: SuzzmeSettingsValue?
    let createdAt: Date

    var risk: SuzzmeCapabilityRisk { operation == .read ? .readOnly : .lowImpactWrite }
    var requiresConfirmation: Bool { false }
}

struct SuzzmeSettingsEvidence: Sendable, Equatable {
    let planID: UUID
    let requestID: UUID
    let capability: SuzzmeSettingsCapabilityID
    let operation: SuzzmeSettingsOperation
    let verifiedValue: SuzzmeSettingsValue?
    let verifiedAt: Date
}

struct SuzzmeSettingsResult: Sendable, Equatable {
    let planID: UUID
    let verified: Bool
    let message: String
    let evidence: SuzzmeSettingsEvidence
}

enum SuzzmeSettingsCapabilityError: LocalizedError, Sendable {
    case ambiguousTime, ambiguousSetting, malformed, staleRequest, verificationFailed
    var errorDescription: String? {
        switch self {
        case .ambiguousSetting: "Which setting do you want to change? Nothing was changed."
        case .ambiguousTime: "Should that be AM or PM? I haven’t changed your Daily Summary time."
        case .malformed: "I couldn’t identify one supported setting to change. Nothing was changed."
        case .staleRequest: "That settings request is no longer active."
        case .verificationFailed: "I couldn’t verify that setting. Please check Settings before trying again."
        }
    }
}

struct SuzzmeSettingsPlanner: Sendable {
    func plan(for text: String, requestID: UUID, now: Date = .now, timeZone: TimeZone = .current, previousCapability: SuzzmeSettingsCapabilityID? = nil) throws -> SuzzmeSettingsPlan? {
        var normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasSuffix(".") { normalized.removeLast() }
        let timeFollowUp = normalized.hasPrefix("change it to ") || normalized.hasPrefix("set it to ")
        let toggleFollowUp = ["turn it back on", "turn it on", "turn it off"].contains(normalized)
        if timeFollowUp || toggleFollowUp {
            guard let previousCapability else { throw SuzzmeSettingsCapabilityError.ambiguousSetting }
            switch previousCapability {
            case .dailySummary:
                normalized = normalized.replacingOccurrences(of: "it back", with: "daily summary")
                    .replacingOccurrences(of: "it ", with: "daily summary ")
            case .timeCriticalIntelligence, .preparedAssistance:
                guard toggleFollowUp else { throw SuzzmeSettingsCapabilityError.malformed }
                let name = previousCapability == .timeCriticalIntelligence ? "time-critical intelligence" : "prepared assistance"
                normalized = normalized.replacingOccurrences(of: "it back", with: name).replacingOccurrences(of: "it ", with: name + " ")
            default: throw SuzzmeSettingsCapabilityError.ambiguousSetting
            }
        }
        let relevant = ["daily summary", "daily briefing", "time-critical", "time critical", "prepared assistance", "presence", "animation"].contains { normalized.contains($0) } || normalized.hasPrefix("use ")
        if relevant && ["do not", "don't", "don’t", "never ", "ignore ", "pretend ", "\"", "“", ";", " and ", " or "].contains(where: normalized.contains) {
            throw SuzzmeSettingsCapabilityError.malformed
        }
        let isRead = normalized.hasPrefix("what ") || normalized.hasPrefix("when ") || normalized.hasPrefix("is ")
        if relevant && !isRead && !["set ", "change ", "turn ", "enable ", "disable ", "use "].contains(where: normalized.hasPrefix) {
            throw SuzzmeSettingsCapabilityError.malformed
        }
        if normalized.contains("daily summary") || normalized.contains("daily briefing") {
            if isRead { return make(requestID, .dailySummary, .read, nil, now) }
            if let enabled = toggle(in: normalized) { return make(requestID, .dailySummary, .update, .enabled(enabled), now) }
            if normalized.contains(" at ") || normalized.contains(" time ") || normalized.contains(" to ") {
                let time = try summaryTime(in: normalized, timeZone: timeZone)
                return make(requestID, .dailySummary, .update, .summaryTime(hour: time.hour, minute: time.minute, timeZoneIdentifier: timeZone.identifier), now)
            }
        }
        if normalized.contains("time-critical") || normalized.contains("time critical") {
            if isRead { return make(requestID, .timeCriticalIntelligence, .read, nil, now) }
            if let enabled = toggle(in: normalized) { return make(requestID, .timeCriticalIntelligence, .update, .enabled(enabled), now) }
        }
        if normalized.contains("prepared assistance") {
            if isRead { return make(requestID, .preparedAssistance, .read, nil, now) }
            if let enabled = toggle(in: normalized) { return make(requestID, .preparedAssistance, .update, .enabled(enabled), now) }
        }
        if (normalized.contains("presence") && normalized.contains("theme")) || normalized.hasPrefix("use ") && !normalized.contains("animation") {
            if isRead { return make(requestID, .presenceTheme, .read, nil, now) }
            let supported = SuzzmePresenceTheme.allCases.first { normalized.contains($0.title.lowercased()) || normalized.contains($0.rawValue.lowercased()) }
            guard let supported else { return nil }
            return make(requestID, .presenceTheme, .update, .presenceTheme(supported.rawValue), now)
        }
        if normalized.contains("animation") {
            if isRead { return make(requestID, .presenceAnimation, .read, nil, now) }
            guard let supported = SuzzmePresenceAnimation.allCases.first(where: { normalized.contains($0.rawValue) }) else { throw SuzzmeSettingsCapabilityError.malformed }
            return make(requestID, .presenceAnimation, .update, .presenceAnimation(supported.rawValue), now)
        }
        return nil
    }

    private func make(_ requestID: UUID, _ capability: SuzzmeSettingsCapabilityID, _ operation: SuzzmeSettingsOperation, _ value: SuzzmeSettingsValue?, _ now: Date) -> SuzzmeSettingsPlan {
        .init(id: UUID(), requestID: requestID, capability: capability, operation: operation, value: value, createdAt: now)
    }

    private func toggle(in text: String) -> Bool? {
        if text.contains("turn on") || text.contains("enable") || text.hasSuffix(" on") { return true }
        if text.contains("turn off") || text.contains("disable") || text.hasSuffix(" off") { return false }
        return nil
    }

    private func summaryTime(in text: String, timeZone: TimeZone) throws -> (hour: Int, minute: Int) {
        let pattern = #"(?<![\w:])([0-9]{1,2})(?::([0-9]{2}))?\s*(am|pm)?(?![\w:])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) == 1,
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hourRange = Range(match.range(at: 1), in: text), var hour = Int(text[hourRange]) else { throw SuzzmeSettingsCapabilityError.malformed }
        let minute = match.range(at: 2).location == NSNotFound ? 0 : Range(match.range(at: 2), in: text).flatMap { Int(text[$0]) } ?? 0
        let marker = match.range(at: 3).location == NSNotFound ? nil : Range(match.range(at: 3), in: text).map { String(text[$0]) }
        if marker == nil, match.range(at: 2).location == NSNotFound, hour <= 12 { throw SuzzmeSettingsCapabilityError.ambiguousTime }
        guard hour <= 23, minute <= 59, marker == nil || (1...12).contains(hour) else { throw SuzzmeSettingsCapabilityError.malformed }
        if marker == "pm", hour < 12 { hour += 12 }
        if marker == "am", hour == 12 { hour = 0 }
        guard TimeZone(identifier: timeZone.identifier) != nil else { throw SuzzmeSettingsCapabilityError.malformed }
        return (hour, minute)
    }
}

enum SuzzmeSettingsPolicy {
    static func validate(_ plan: SuzzmeSettingsPlan, now: Date = .now) throws {
        guard now.timeIntervalSince(plan.createdAt) <= 120, plan.createdAt <= now.addingTimeInterval(5) else { throw SuzzmeSettingsCapabilityError.staleRequest }
        if plan.operation == .read { guard plan.value == nil else { throw SuzzmeSettingsCapabilityError.malformed }; return }
        switch (plan.capability, plan.value) {
        case (.dailySummary, .enabled), (.timeCriticalIntelligence, .enabled), (.preparedAssistance, .enabled): break
        case let (.dailySummary, .summaryTime(hour, minute, identifier)):
            guard 0...23 ~= hour, 0...59 ~= minute, TimeZone(identifier: identifier) != nil else { throw SuzzmeSettingsCapabilityError.malformed }
        case let (.presenceTheme, .presenceTheme(value)):
            guard SuzzmePresenceTheme(rawValue: value) != nil else { throw SuzzmeSettingsCapabilityError.malformed }
        case let (.presenceAnimation, .presenceAnimation(value)):
            guard SuzzmePresenceAnimation(rawValue: value) != nil else { throw SuzzmeSettingsCapabilityError.malformed }
        default: throw SuzzmeSettingsCapabilityError.malformed
        }
    }
}

/// Revocation and the synchronous disk mutation share one critical section.
/// No suspension, callbacks, or UI work is permitted inside this grant.
final class SuzzmeSettingsAuthorization: Sendable {
    private struct Grant {
        var owner: UUID?
        var plan: SuzzmeSettingsPlan?
        var deadline: ContinuousClock.Instant?
    }
    private let owner = OSAllocatedUnfairLock(initialState: Grant())
    func begin(_ id: UUID) { owner.withLock { $0 = Grant(owner: id) } }
    func cancel(_ id: UUID) { owner.withLock { if $0.owner == id { $0 = Grant() } } }
    func authorize(_ plan: SuzzmeSettingsPlan, now: Date) throws {
        try SuzzmeSettingsPolicy.validate(plan, now: now)
        try owner.withLock {
            guard $0.owner == plan.requestID else { throw SuzzmeSettingsCapabilityError.staleRequest }
            $0.plan = plan
            $0.deadline = ContinuousClock.now.advanced(by: .seconds(max(0, 120 - now.timeIntervalSince(plan.createdAt))))
        }
    }
    func commit<T>(_ plan: SuzzmeSettingsPlan, body: () throws -> T) throws -> T {
        // The closure stays synchronous on its caller's executor. Only the
        // grant is shared; actor-owned storage never crosses an executor.
        try owner.withLockUnchecked { grant in
            try Task.checkCancellation()
            guard grant.owner == plan.requestID, grant.plan == plan,
                  let deadline = grant.deadline, ContinuousClock.now < deadline else {
                throw SuzzmeSettingsCapabilityError.staleRequest
            }
            // Consume before mutation. Failure does not permit implicit replay.
            grant.plan = nil; grant.deadline = nil
            return try body()
        }
    }
}

actor SuzzmeSettingsCapabilityCoordinator {
    private let proactive: ProactiveIntelligenceEngine
    private let defaults: UserDefaults
    private var activeRequestID: UUID?
    private var completed: [UUID: (SuzzmeSettingsPlan, SuzzmeSettingsResult)] = [:]
    private var consumed = Set<UUID>()
    private let authorization = SuzzmeSettingsAuthorization()

    init(proactive: ProactiveIntelligenceEngine, defaultsSuiteName: String? = nil) {
        self.proactive = proactive
        self.defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    func begin(requestID: UUID) { activeRequestID = requestID; authorization.begin(requestID) }
    func cancel(requestID: UUID) { authorization.cancel(requestID); if activeRequestID == requestID { activeRequestID = nil } }

    func execute(_ plan: SuzzmeSettingsPlan, requestID: UUID, now: Date = .now) async throws -> SuzzmeSettingsResult {
        guard activeRequestID == requestID, plan.requestID == requestID else { throw SuzzmeSettingsCapabilityError.staleRequest }
        try Task.checkCancellation()
        if let (original, result) = completed[plan.id] {
            guard original == plan else { throw SuzzmeSettingsCapabilityError.malformed }
            return result
        }
        guard consumed.count < 512, consumed.insert(plan.id).inserted else { throw SuzzmeSettingsCapabilityError.staleRequest }
        try SuzzmeSettingsPolicy.validate(plan, now: now)
        let message: String
        if plan.operation == .read { message = try await read(plan.capability) }
        else {
            try authorization.authorize(plan, now: now)
            try await mutate(plan)
            guard activeRequestID == requestID else { throw SuzzmeSettingsCapabilityError.staleRequest }
            message = try await verify(plan)
        }
        try Task.checkCancellation()
        guard activeRequestID == requestID else { throw SuzzmeSettingsCapabilityError.staleRequest }
        let evidence = SuzzmeSettingsEvidence(
            planID: plan.id,
            requestID: requestID,
            capability: plan.capability,
            operation: plan.operation,
            verifiedValue: plan.value,
            verifiedAt: now
        )
        let result = SuzzmeSettingsResult(planID: plan.id, verified: true, message: message, evidence: evidence)
        completed[plan.id] = (plan, result)
        if completed.count > 64, let oldest = completed.keys.sorted(by: { $0.uuidString < $1.uuidString }).first { completed.removeValue(forKey: oldest) }
        return result
    }

    private func mutate(_ plan: SuzzmeSettingsPlan) async throws {
        if [.dailySummary, .timeCriticalIntelligence, .preparedAssistance].contains(plan.capability) {
            try await proactive.applySettings(plan, authorization: authorization)
        } else {
            try authorization.commit(plan) {
                switch (plan.capability, plan.value) {
                case let (.presenceTheme, .presenceTheme(value)): defaults.set(value, forKey: InvocationCoordinator.presenceThemeKey)
                case let (.presenceAnimation, .presenceAnimation(value)): defaults.set(value, forKey: InvocationCoordinator.presenceAnimationKey)
                default: throw SuzzmeSettingsCapabilityError.malformed
                }
            }
        }
    }

    private func verify(_ plan: SuzzmeSettingsPlan) async throws -> String {
        let preferences = try await proactive.preferences()
        switch (plan.capability, plan.value) {
        case let (.dailySummary, .enabled(value)) where preferences.dailyBriefingEnabled == value: return "Daily Summary is now \(value ? "on" : "off")."
        case let (.dailySummary, .summaryTime(hour, minute, identifier)) where preferences.briefingHour == hour && preferences.briefingMinute == minute && preferences.timeZoneIdentifier == identifier:
            return String(format: "Daily Summary time is now %02d:%02d in %@.", hour, minute, identifier)
        case let (.timeCriticalIntelligence, .enabled(value)) where preferences.timeCriticalEnabled == value: return "Time-Critical Intelligence is now \(value ? "on" : "off")."
        case let (.preparedAssistance, .enabled(value)) where preferences.preparedAssistanceEnabled == value: return "Prepared Assistance is now \(value ? "on" : "off")."
        case let (.presenceTheme, .presenceTheme(value)) where defaults.string(forKey: InvocationCoordinator.presenceThemeKey) == value:
            return "Presence theme is now \(SuzzmePresenceTheme(rawValue: value)?.title ?? value)."
        case let (.presenceAnimation, .presenceAnimation(value)) where defaults.string(forKey: InvocationCoordinator.presenceAnimationKey) == value:
            return "Presence animation is now \(SuzzmePresenceAnimation(rawValue: value)?.title ?? value)."
        default: throw SuzzmeSettingsCapabilityError.verificationFailed
        }
    }

    private func read(_ capability: SuzzmeSettingsCapabilityID) async throws -> String {
        let preferences = try await proactive.preferences()
        switch capability {
        case .dailySummary: return String(format: "Daily Summary is %@ at %02d:%02d in %@.", preferences.dailyBriefingEnabled ? "on" : "off", preferences.briefingHour, preferences.briefingMinute, preferences.timeZoneIdentifier)
        case .timeCriticalIntelligence: return "Time-Critical Intelligence is \(preferences.timeCriticalEnabled ? "on" : "off")."
        case .preparedAssistance: return "Prepared Assistance is \(preferences.preparedAssistanceEnabled ? "on" : "off")."
        case .presenceTheme: return "Presence theme is \((defaults.string(forKey: InvocationCoordinator.presenceThemeKey).flatMap(SuzzmePresenceTheme.init(rawValue:)) ?? .suzzmePurple).title)."
        case .presenceAnimation: return "Presence animation is \((defaults.string(forKey: InvocationCoordinator.presenceAnimationKey).flatMap(SuzzmePresenceAnimation.init(rawValue:)) ?? .gentle).title)."
        }
    }
}
