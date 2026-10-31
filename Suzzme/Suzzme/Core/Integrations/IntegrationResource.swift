import Foundation
import CryptoKit

enum IntegrationSummaryPolicy {
    static let maximumResourcesPerAccount = 4
    static let maximumReadsPerCycle = 8
    static func externalID(accountID: UUID, generation: UUID? = nil, url: String) -> String {
        "integration:" + accountID.uuidString + ":" + (generation.map { $0.uuidString + ":" } ?? "")
            + SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func permits(_ url: String, account: IntegrationAccount) -> Bool {
        guard url.utf8.count <= 2_048, let resource = IntegrationResourceResolver.resolve(url: url),
              resource.serviceID == account.service, resource.canonicalURL.absoluteString == url else { return false }
        switch resource.kind {
        case .githubIssue, .githubPullRequest:
            guard let owner = resource.attributes.owner, let repository = resource.attributes.repository else { return false }
            return IntegrationRepositoryPolicy.permits(repo: owner + "/" + repository, account: account)
        case .notionPage:
            return resource.attributes.notionPageID.map { IntegrationNotionPagePolicy.permits(pageID: $0, account: account) } ?? false
        case .linearIssue:
            return resource.attributes.linearIssueID.map { IntegrationLinearIssuePolicy.permits(issueID: $0, account: account) } ?? false
        default: return false
        }
    }
}

/// Perception identifies a target; it grants neither account access nor execution authority.
enum IntegrationResourceKind: String, Codable, Sendable {
    case githubRepository, githubIssue, githubPullRequest, githubFile
    case linkedInProfile, linkedInPost, linkedInPage
    case notionPage, linearIssue
}

enum IntegrationResourceProvenance: String, Codable, Sendable {
    case explicitURL, browserURL, structuredContext, visualInference
}

struct IntegrationResourceAttributes: Codable, Sendable, Equatable {
    var owner: String? = nil
    var repository: String? = nil
    var number: Int? = nil
    var ref: String? = nil
    var file: String? = nil
    /// A branch name can contain slashes. URL parsing cannot safely infer its boundary.
    var unresolvedReferenceAndPath: [String]? = nil
    var linkedInIdentifier: String? = nil
    var notionPageID: String? = nil
    var linearIssueID: String? = nil
}

struct IntegrationResolvedResource: Codable, Sendable, Equatable {
    let serviceID: IntegrationID
    let kind: IntegrationResourceKind
    let canonicalID: String
    let canonicalURL: URL
    let attributes: IntegrationResourceAttributes
    let provenance: IntegrationResourceProvenance
    let confidence: Double
    let capturedAt: Date
    let contextID: UUID
    let contextVersion: UInt64

    func hasSameTarget(as other: Self) -> Bool {
        serviceID == other.serviceID && canonicalID == other.canonicalID
    }
}

/// Codable is solely a wire boundary. Raw browser content stays in request memory,
/// never a Source, watched link, memory candidate, diagnostics record, or approval grant.
/// The wire uses Unix seconds for capturedAt; configure JSONDecoder accordingly.
struct IntegrationBrowserContext: Codable, Sendable, Equatable {
    static let maximumAgeSeconds: TimeInterval = 30
    static let maximumURLBytes = 4_096
    static let maximumTitleBytes = 512
    static let maximumSelectionBytes = 8_192
    static let maximumPageContextBytes = 16_384
    static let maximumVersion: UInt64 = 9_007_199_254_740_991

    let contextID: UUID
    let contextVersion: UInt64
    let capturedAt: Date
    let browser: String
    let browserInstallationID: UUID
    let tabID: Int
    let windowID: Int
    let documentID: String?
    let url: String
    let title: String
    let selectedText: String?
    let boundedPageContext: String?

    init(contextID: UUID = UUID(), contextVersion: UInt64, capturedAt: Date = .now,
         browser: String = "chrome", browserInstallationID: UUID = UUID(), tabID: Int,
         windowID: Int, documentID: String? = nil, url: String, title: String,
         selectedText: String? = nil, boundedPageContext: String? = nil) {
        self.contextID = contextID; self.contextVersion = contextVersion; self.capturedAt = capturedAt
        self.browser = browser; self.browserInstallationID = browserInstallationID
        self.tabID = tabID; self.windowID = windowID; self.documentID = documentID
        self.url = url; self.title = title; self.selectedText = selectedText
        self.boundedPageContext = boundedPageContext
    }

    func isCurrent(now: Date = .now) -> Bool {
        let age = now.timeIntervalSince(capturedAt)
        return age.isFinite && age >= 0 && age <= Self.maximumAgeSeconds
            && contextVersion > 0 && contextVersion <= Self.maximumVersion
            && ["chrome", "chromium"].contains(browser)
            && tabID >= 0 && windowID >= 0
            && !url.isEmpty && url.utf8.count <= Self.maximumURLBytes
            && title.utf8.count <= Self.maximumTitleBytes
            && (selectedText?.utf8.count ?? 0) <= Self.maximumSelectionBytes
            && (boundedPageContext?.utf8.count ?? 0) <= Self.maximumPageContextBytes
            && (documentID?.utf8.count ?? 0) <= 128
            && !url.unicodeScalars.contains(where: Self.isForbiddenURLScalar)
            && !title.contains("\0") && !(selectedText?.contains("\0") ?? false)
            && !(boundedPageContext?.contains("\0") ?? false)
    }

    private static func isForbiddenURLScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value <= 0x20 || scalar.value == 0x7f || scalar.value == 0x5c
    }
}

enum IntegrationResourceResolution: Sendable, Equatable {
    case resolved(IntegrationResolvedResource)
    case ambiguous(explicit: IntegrationResolvedResource, browser: IntegrationResolvedResource)
    case unavailable
}

enum IntegrationResourceResolver {
    /// Connection recognition only. Repository tabs do not become executable
    /// resource targets, and query/fragment/page-path data never leave this API.
    static func repositoryForConnection(url: String) -> String? {
        guard !url.isEmpty, url.utf8.count <= 4_096,
              !url.unicodeScalars.contains(where: { $0.value <= 0x20 || $0.value == 0x7f || $0.value == 0x5c }),
              let components = URLComponents(string: url), components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "github.com", components.user == nil, components.password == nil,
              components.port == nil, let parts = decodedPath(components.percentEncodedPath), parts.count >= 2,
              validOwner(parts[0]), validRepository(parts[1]) else { return nil }
        let reserved = ["about", "account", "apps", "collections", "contact", "customer-stories", "enterprise", "events", "explore", "features", "issues", "login", "logout", "marketplace", "new", "notifications", "organizations", "orgs", "pricing", "pulls", "search", "security", "settings", "site", "sponsors", "topics", "trending", "users"]
        guard !reserved.contains(parts[0].lowercased()) else { return nil }
        let slug = parts[0].lowercased() + "/" + parts[1].lowercased()
        guard resolve(url: "https://github.com/" + slug)?.kind == .githubRepository else { return nil }
        if parts.count == 2 || resolve(url: url)?.serviceID == .github { return slug }
        let sections = ["issues", "pulls", "actions", "releases", "tags", "branches", "commits", "discussions", "projects", "wiki", "security", "settings"]
        if parts.count == 3 && sections.contains(parts[2]) { return slug }
        if parts.count >= 4 && parts[2] == "tree" { return slug }
        if parts.count == 4 && parts[2] == "releases" && parts[3] == "latest" { return slug }
        if parts.count == 5 && parts[2] == "releases" && parts[3] == "tag" { return slug }
        return nil
    }

    /// Invalid explicit targets fail closed; an unrelated browser target cannot replace them.
    static func resolve(explicitURL: String?, browser: IntegrationBrowserContext?, consequential: Bool,
                        now: Date = .now) -> IntegrationResourceResolution {
        let freshBrowser = browser.flatMap { context -> IntegrationResolvedResource? in
            guard context.isCurrent(now: now) else { return nil }
            return resolve(url: context.url, provenance: .browserURL, contextID: context.contextID,
                           contextVersion: context.contextVersion, capturedAt: context.capturedAt)
        }
        if let explicitURL {
            guard let explicit = resolve(url: explicitURL, provenance: .explicitURL, capturedAt: now) else {
                return .unavailable
            }
            if consequential, let freshBrowser, !explicit.hasSameTarget(as: freshBrowser) {
                return .ambiguous(explicit: explicit, browser: freshBrowser)
            }
            return .resolved(explicit)
        }
        return freshBrowser.map(IntegrationResourceResolution.resolved) ?? .unavailable
    }

    static func resolve(url: String, provenance: IntegrationResourceProvenance = .explicitURL,
                        contextID: UUID = UUID(), contextVersion: UInt64 = 1,
                        capturedAt: Date = .now) -> IntegrationResolvedResource? {
        guard !url.isEmpty, url.utf8.count <= IntegrationBrowserContext.maximumURLBytes,
              contextVersion > 0 && contextVersion <= IntegrationBrowserContext.maximumVersion,
              capturedAt.timeIntervalSince1970.isFinite,
              !url.unicodeScalars.contains(where: { $0.value <= 0x20 || $0.value == 0x7f || $0.value == 0x5c }),
              let components = URLComponents(string: url), components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(),
              ["github.com", "linkedin.com", "www.linkedin.com", "notion.so", "www.notion.so", "app.notion.com", "linear.app", "www.linear.app"].contains(host),
              let parts = decodedPath(components.percentEncodedPath) else { return nil }

        let service: IntegrationID
        let kind: IntegrationResourceKind
        let path: [String]
        let attributes: IntegrationResourceAttributes
        if host == "github.com" {
            guard parts.count >= 2, validOwner(parts[0]), validRepository(parts[1]) else { return nil }
            let owner = parts[0].lowercased(), repository = parts[1].lowercased()
            service = .github
            if parts.count == 2 {
                kind = .githubRepository
                path = [owner, repository]
                attributes = .init(owner: owner, repository: repository)
            } else if parts.count == 4, ["issues", "pull"].contains(parts[2]),
                      let number = positiveInteger(parts[3]) {
                kind = parts[2] == "issues" ? .githubIssue : .githubPullRequest
                path = [owner, repository, parts[2], String(number)]
                attributes = .init(owner: owner, repository: repository, number: number)
            } else if parts.count >= 5, parts[2] == "blob" {
                kind = .githubFile
                if isCommit(parts[3]) {
                    path = [owner, repository, "blob", parts[3].lowercased()] + parts.dropFirst(4)
                    attributes = .init(owner: owner, repository: repository, ref: parts[3].lowercased(),
                                       file: parts.dropFirst(4).joined(separator: "/"))
                } else {
                    path = [owner, repository] + parts.dropFirst(2)
                    attributes = .init(owner: owner, repository: repository,
                                       unresolvedReferenceAndPath: Array(parts.dropFirst(3)))
                }
            } else { return nil }
        } else if ["notion.so", "www.notion.so", "app.notion.com"].contains(host) {
            let pageID: String?
            if host == "app.notion.com" {
                guard parts.count == 2, parts[0] == "p" else { return nil }
                pageID = IntegrationNotionPagePolicy.normalizedID(parts[1])
            } else {
                guard (1...2).contains(parts.count), let tail = parts.last else { return nil }
                pageID = IntegrationNotionPagePolicy.normalizedID(tail)
                    ?? IntegrationNotionPagePolicy.normalizedID(String(tail.suffix(32)))
            }
            guard let pageID else { return nil }
            service = .notion; kind = .notionPage
            path = ["p", pageID]
            attributes = .init(notionPageID: pageID)
        } else if host == "linear.app" || host == "www.linear.app" {
            let identifier: String
            if parts.count >= 3, parts[1] == "issue", let normalized = IntegrationLinearIssuePolicy.normalized(parts[2]),
               validLinkedInSlug(parts[0]) {
                identifier = normalized
                path = [parts[0], "issue", identifier]
            } else if parts.count >= 2, parts[0] == "issue", let normalized = IntegrationLinearIssuePolicy.normalized(parts[1]) {
                identifier = normalized
                path = ["issue", identifier]
            } else { return nil }
            service = .linear; kind = .linearIssue
            attributes = .init(linearIssueID: identifier)
        } else {
            service = .linkedin
            guard let first = parts.first else { return nil }
            if parts.count == 2, first == "in", validLinkedInSlug(parts[1]) {
                kind = .linkedInProfile
            } else if parts.count == 2, ["company", "school", "showcase"].contains(first),
                      validLinkedInSlug(parts[1]) {
                kind = .linkedInPage
            } else if parts.count == 2, first == "posts", validLinkedInSlug(parts[1]) {
                kind = .linkedInPost
            } else if parts.count == 3, parts[0] == "feed", parts[1] == "update",
                      validLinkedInActivity(parts[2]) {
                kind = .linkedInPost
            } else { return nil }
            path = parts
            attributes = .init(linkedInIdentifier: parts.last)
        }
        var canonical = URLComponents()
        canonical.scheme = "https"
        switch service {
        case .github: canonical.host = "github.com"
        case .notion: canonical.host = "app.notion.com"
        case .linear: canonical.host = "linear.app"
        default: canonical.host = "www.linkedin.com"
        }
        canonical.path = "/" + path.joined(separator: "/")
        guard let canonicalURL = canonical.url else { return nil }
        let namespace = service.rawValue
        let confidence: Double
        switch provenance {
        case .explicitURL, .browserURL: confidence = 1
        case .structuredContext: confidence = 0.9
        case .visualInference: confidence = 0.5
        }
        return .init(serviceID: service, kind: kind, canonicalID: namespace + ":" + path.joined(separator: "/"),
                     canonicalURL: canonicalURL, attributes: attributes, provenance: provenance,
                     confidence: confidence, capturedAt: capturedAt, contextID: contextID, contextVersion: contextVersion)
    }

    private static func decodedPath(_ raw: String) -> [String]? {
        guard raw.hasPrefix("/"), !raw.contains("//") else { return nil }
        let encodedParts = raw.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        var result: [String] = []
        for (index, piece) in encodedParts.enumerated() {
            if piece.isEmpty {
                guard index == encodedParts.count - 1 else { return nil }
                continue
            }
            let encoded = String(piece)
            // Reject separator smuggling, escaped percents/double encoding, and dot segments.
            guard let decoded = encoded.removingPercentEncoding, !decoded.isEmpty,
                  decoded != ".", decoded != "..",
                  !decoded.contains("/"), !decoded.contains("\\"), !decoded.contains("%"),
                  !decoded.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) else { return nil }
            result.append(decoded)
        }
        return result
    }

    private static func validOwner(_ value: String) -> Bool {
        (1...39).contains(value.utf8.count) && value.first != "-" && value.last != "-"
            && value.utf8.allSatisfy { isASCIIAlphanumeric($0) || $0 == 45 }
    }

    private static func validRepository(_ value: String) -> Bool {
        (1...100).contains(value.utf8.count) && value != "." && value != ".."
            && value.utf8.allSatisfy { isASCIIAlphanumeric($0) || [45, 46, 95].contains($0) }
    }

    private static func positiveInteger(_ value: String) -> Int? {
        guard !value.isEmpty, value.utf8.count <= 19,
              value.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(value), number > 0 else { return nil }
        return number
    }

    private static func isCommit(_ value: String) -> Bool {
        value.utf8.count == 40 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    private static func validLinkedInSlug(_ value: String) -> Bool {
        (1...200).contains(value.utf8.count)
            && value.utf8.allSatisfy { isASCIIAlphanumeric($0) || [45, 95].contains($0) }
    }

    private static func validLinkedInActivity(_ value: String) -> Bool {
        let prefix = "urn:li:activity:"
        return value.hasPrefix(prefix) && positiveInteger(String(value.dropFirst(prefix.count))) != nil
    }

    private static func isASCIIAlphanumeric(_ value: UInt8) -> Bool {
        (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value)
    }
}
