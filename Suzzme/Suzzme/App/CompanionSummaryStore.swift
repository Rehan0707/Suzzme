import CryptoKit
import FirebaseAuth
import FirebaseCore
import Foundation

/// Only these derived, display-ready facts leave the Mac. Source references,
/// raw records, credentials, memory, and action capabilities are excluded.
struct CompanionSummaryItem: Codable, Sendable, Equatable, Identifiable {
    let id: Int
    let title: String
    let detail: String
    let source: String
    let kind: ProactiveCandidateKind
    let effectiveAt: Date?
}

struct CompanionSummary: Codable, Sendable, Equatable {
    let version: Int
    let generatedAt: Date
    let localDay: Date
    let timeZoneIdentifier: String
    let narration: String
    let items: [CompanionSummaryItem]
    let sources: [String]
    let limitations: [String]
    var delivery: CompanionSummaryDelivery?

    var isPartial: Bool { !limitations.isEmpty }

    init(version: Int, generatedAt: Date, localDay: Date, timeZoneIdentifier: String,
         narration: String, items: [CompanionSummaryItem], sources: [String], limitations: [String], delivery: CompanionSummaryDelivery? = nil) {
        self.version = version
        self.generatedAt = generatedAt
        self.localDay = localDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.narration = narration
        self.items = items
        self.sources = sources
        self.limitations = limitations
        self.delivery = delivery
    }

    init?(snapshot: ProactiveSnapshot, preferences: ProactivePreferences? = nil) {
        guard let day = snapshot.dailyContext else { return nil }
        version = 1
        generatedAt = day.generatedAt
        localDay = day.localDay
        timeZoneIdentifier = day.timeZoneIdentifier ?? TimeZone.current.identifier
        let fallback: String
        if !day.sourceLimitations.isEmpty { fallback = "Some sources could not be checked today. Review the available updates below." }
        else if !day.activeEntries.isEmpty { fallback = "Your Mac found updates for today. Review them below." }
        else { fallback = "Nothing new needs your attention today." }
        narration = String((snapshot.briefing?.narration ?? fallback).prefix(ProactiveLimits.narrationCharacters))
        items = day.activeEntries.prefix(12).enumerated().map { index, entry in
            CompanionSummaryItem(id: index, title: String(entry.title.prefix(140)),
                detail: String(entry.summary.prefix(300)), source: Self.displaySource(entry.source),
                kind: entry.kind, effectiveAt: entry.effectiveAt)
        }
        sources = Array(Set(items.map(\.source) + (snapshot.briefing?.sourceEvidence ?? []).map(Self.displaySource))).sorted()
        limitations = Array((day.sourceLimitations + (snapshot.briefing?.healthLimitations ?? []))
            .prefix(4).map { String($0.prefix(240)) })
        delivery = preferences.map { preferences in
            let updates = preferences.timeCriticalEnabled ? snapshot.timeCriticalItems.prefix(3).map { item in
                CompanionUrgentUpdate(
                    id: SHA256.hash(data: Data(item.candidateID.utf8)).map { String(format: "%02x", $0) }.joined(),
                    text: String(item.summary.prefix(400)), createdAt: snapshot.generatedAt,
                    expiresAt: snapshot.generatedAt.addingTimeInterval(900))
            } : []
            return CompanionSummaryDelivery(schedule: CompanionSummarySchedule(
                enabled: preferences.dailyBriefingEnabled, hour: preferences.briefingHour,
                minute: preferences.briefingMinute, timeZoneIdentifier: preferences.timeZoneIdentifier),
                urgentUpdates: updates)
        }
    }

    var isValid: Bool {
        version == 1 && items.count <= 12 && sources.count <= 16 && limitations.count <= 4
            && (delivery?.isValid ?? true)
            && narration.count <= ProactiveLimits.narrationCharacters
            && items.allSatisfy { $0.title.count <= 140 && $0.detail.count <= 300 && $0.source.count <= 40 }
            && sources.allSatisfy { $0.count <= 40 }
            && limitations.allSatisfy { $0.count <= 240 }
            && TimeZone(identifier: timeZoneIdentifier) != nil
            && generatedAt <= Date.now.addingTimeInterval(300)
    }

    private static func displaySource(_ value: String) -> String {
        switch value.lowercased() {
        case "calendar": "Calendar"
        case "reminders": "Reminders"
        case "gmail": "Gmail"
        case "messages", "shared messages": "Shared messages"
        case "connectedapps", "connected apps": "Connected apps"
        case "watchedweb", "watched pages": "Watched pages"
        default: "Selected source"
        }
    }
}

/// Firebase identity is verified by Supabase before its per-user RLS policies.
/// The local cache is keyed by UID and protected by iOS file protection.
enum CompanionSummaryStore {
    static var currentUser: User? { FirebaseApp.app() == nil ? nil : Auth.auth().currentUser }

    static func load(expectedUID: String) async throws -> CompanionSummary? {
        let (url, key, user, token) = try await configuration()
        guard user.uid == expectedUID else { throw CompanionSummaryStoreError.noAccount }
        let transport = CompanionSummaryTransport(projectURL: url, publishableKey: key, uid: user.uid, token: token)
        let data = try await transport.load()
        try Task.checkCancellation()
        guard currentUser?.uid == expectedUID else { throw CompanionSummaryStoreError.noAccount }
        let rows = try decoder.decode([SummaryRow].self, from: data)
        guard rows.count <= 1 else { throw CompanionSummaryStoreError.invalidResponse }
        guard let row = rows.first else { removeCache(for: user.uid); return nil }
        guard row.firebase_uid == expectedUID, row.payload.isValid else {
            throw CompanionSummaryStoreError.invalidResponse
        }
        saveCache(row.payload, for: user.uid)
        return row.payload
    }

    static func publish(_ summary: CompanionSummary, expectedUID: String) async throws {
        guard summary.isValid else { throw CompanionSummaryStoreError.invalidResponse }
        let (url, key, user, token) = try await configuration()
        guard user.uid == expectedUID else { throw CompanionSummaryStoreError.noAccount }
        // A restored Firebase session may predate account storage setup. Ensure
        // the parent row exists before the summary's foreign-key upsert.
        try await SupabaseAccountStore.save(user)
        guard currentUser?.uid == expectedUID else { throw CompanionSummaryStoreError.noAccount }
        try await CompanionSummaryTransport(projectURL: url, publishableKey: key, uid: user.uid, token: token)
            .publish(summary)
        // Only report a shared summary after the same account can read back
        // the exact published payload through the phone's authenticated path.
        let expected = try decoder.decode(CompanionSummary.self, from: encoder.encode(summary))
        guard let received = try await load(expectedUID: expectedUID), received == expected else {
            throw CompanionSummaryStoreError.invalidResponse
        }
    }

    static func removeSharedSummary(expectedUID: String) async throws {
        let (url, key, user, token) = try await configuration()
        guard user.uid == expectedUID else { throw CompanionSummaryStoreError.noAccount }
        try await CompanionSummaryTransport(projectURL: url, publishableKey: key, uid: user.uid, token: token)
            .remove()
        removeCache(for: user.uid)
    }

    static func cached(for uid: String) -> CompanionSummary? {
        guard let data = try? Data(contentsOf: cacheURL(for: uid)),
              let summary = try? decoder.decode(CompanionSummary.self, from: data), summary.isValid else { return nil }
        return summary
    }

    /// These are summaries previously received by this device for this account.
    static func cachedDays(for uid: String) -> [CompanionSummary] {
        guard let data = try? Data(contentsOf: historyURL(for: uid)),
              let summaries = try? decoder.decode([CompanionSummary].self, from: data) else { return [] }
        return summaries.filter { $0.isValid && Date.now.timeIntervalSince($0.generatedAt) < 7 * 86_400 }
    }

    static func removeCache(for uid: String) {
        try? FileManager.default.removeItem(at: cacheURL(for: uid))
        try? FileManager.default.removeItem(at: historyURL(for: uid))
    }

    private static func saveCache(_ summary: CompanionSummary, for uid: String) {
        guard let data = try? encoder.encode(summary) else { return }
        let url = cacheURL(for: uid)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: summary.timeZoneIdentifier) ?? .current
        var history = cachedDays(for: uid).filter { !calendar.isDate($0.localDay, inSameDayAs: summary.localDay) }
        history.insert(summary, at: 0)
        if let historyData = try? encoder.encode(Array(history.prefix(7))) {
            #if os(iOS)
            try? historyData.write(to: historyURL(for: uid), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try? historyData.write(to: historyURL(for: uid), options: .atomic)
            #endif
        }
        #if os(iOS)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: url, options: .atomic)
        #endif
    }

    private static func historyURL(for uid: String) -> URL {
        cacheURL(for: uid).deletingPathExtension().appendingPathExtension("history.json")
    }

    private static func cacheURL(for uid: String) -> URL {
        let digest = SHA256.hash(data: Data(uid.utf8)).map { String(format: "%02x", $0) }.joined()
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appending(path: "Suzzme/CompanionSummaries/\(digest).json")
    }

    static func configuration() async throws -> (URL, String, User, String) {
        guard let rawURL = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              let url = URL(string: rawURL), url.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String,
              !key.isEmpty, !key.contains("$(") else { throw CompanionSummaryStoreError.configuration }
        guard let user = currentUser else { throw CompanionSummaryStoreError.noAccount }
        let token = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            user.getIDToken { token, error in
                if let error { continuation.resume(throwing: error) }
                else if let token { continuation.resume(returning: token) }
                else { continuation.resume(throwing: CompanionSummaryStoreError.unavailable) }
            }
        }
        try Task.checkCancellation()
        guard currentUser?.uid == user.uid else { throw CompanionSummaryStoreError.noAccount }
        return (url, key, user, token)
    }

    private static var encoder: JSONEncoder {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        return value
    }
    private static var decoder: JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }

    private struct SummaryRow: Decodable {
        let firebase_uid: String
        let payload: CompanionSummary
    }
}

#if os(macOS)
enum CompanionSummarySharing {
    static func isEnabled(for uid: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: uid))
    }
    static func setEnabled(_ enabled: Bool, for uid: String) {
        UserDefaults.standard.set(enabled, forKey: key(for: uid))
    }
    static func needsRemoval(for uid: String) -> Bool {
        UserDefaults.standard.bool(forKey: removalKey(for: uid))
    }
    static func setNeedsRemoval(_ needed: Bool, for uid: String) {
        UserDefaults.standard.set(needed, forKey: removalKey(for: uid))
    }
    private static func key(for uid: String) -> String { "suzzme.companion.share.\(uid)" }
    private static func removalKey(for uid: String) -> String { "suzzme.companion.remove.\(uid)" }
}
#endif
