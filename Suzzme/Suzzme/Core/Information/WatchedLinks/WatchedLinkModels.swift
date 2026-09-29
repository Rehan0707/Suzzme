import Foundation

enum WatchedLinkLimits {
    static let links = 12
    static let responseBytes = 512 * 1_024
    static let extractedCharacters = 24_000
    static let sections = 32
    static let redirects = 3
    static let timeout: TimeInterval = 15
    static let minimumRefreshInterval: TimeInterval = 15 * 60
    static let maximumBackoff: TimeInterval = 24 * 3_600
    static let changeRetention: TimeInterval = 30 * 86_400
}

enum WatchedLinkState: String, Codable, Sendable {
    case ready, disabled, refreshing, unchanged, changed, stale, offline, unavailable, blocked, error
}

enum WatchedLinkChangeKind: String, Codable, Sendable {
    case timetable, deadline, cancellation, locationChange, correction, general
}

struct WatchedLinkChange: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let kind: WatchedLinkChangeKind
    let title: String
    let detail: String
    let effectiveAt: Date?
    let effectiveUntil: Date?
    let location: String?
    let observedAt: Date
}

struct WatchedLinkRecord: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    let canonicalURL: URL
    var enabled: Bool
    var state: WatchedLinkState
    var etag: String?
    var lastModifiedHeader: String?
    var fingerprint: String?
    var lastAttempt: Date?
    var lastSuccess: Date?
    var lastMeaningfulChange: Date?
    var consecutiveFailures: Int
    var nextEligibleRefresh: Date?
    var pageTitle: String?
    var changes: [WatchedLinkChange]

    var sourceIdentity: String { "web:\(canonicalURL.absoluteString)" }
}

struct WatchedLinkFetchRequest: Sendable {
    let url: URL
    let etag: String?
    let lastModified: String?
}

struct WatchedLinkFetchResponse: Sendable {
    let finalURL: URL
    let statusCode: Int
    let mimeType: String?
    let data: Data
    let etag: String?
    let lastModified: String?
}

enum WatchedLinkError: LocalizedError, Sendable, Equatable {
    case invalidURL, unsupportedScheme, blockedHost, redirectLimit, responseTooLarge
    case unsupportedContent, malformedContent, timeout, unavailable, notFound, serverError
    case staleRefresh, disabled, limitExceeded, persistence, restrictedContent

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a complete HTTPS page address."
        case .unsupportedScheme: "Watched Links support HTTPS pages only."
        case .blockedHost: "That address points to a local or private network and cannot be watched."
        case .redirectLimit: "That page redirected too many times."
        case .responseTooLarge: "That page is larger than Suzzme’s safe reading limit."
        case .unsupportedContent: "That page does not provide supported text or HTML."
        case .malformedContent: "Suzzme could not read useful text from that page."
        case .timeout: "The page took too long to respond."
        case .unavailable: "The page is unavailable right now."
        case .notFound: "The page could not be found."
        case .serverError: "The website reported a temporary problem."
        case .staleRefresh: "A newer refresh replaced this one."
        case .disabled: "That Watched Link is turned off."
        case .limitExceeded: "You have reached the Watched Links limit."
        case .restrictedContent: "That page contains private credentials and cannot be retained."
        case .persistence: "Watched Links could not be saved on this device."
        }
    }
}

struct WatchedLinkRefresh: Sendable {
    let generation: UUID
    let record: WatchedLinkRecord
}

protocol WatchedLinkFetching: Sendable {
    func fetch(_ request: WatchedLinkFetchRequest) async throws -> WatchedLinkFetchResponse
}
