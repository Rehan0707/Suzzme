import Foundation

/// Strict app links used by browser handoffs. They carry only a service
/// identifier and, when a user explicitly requested it, a canonical GitHub
/// repository slug. They never carry page text or credentials.
struct BrowserIntegrationRoute: Equatable, Sendable {
    enum Action: Equatable, Sendable { case requestConnection, openConnectionSetup }
    let action: Action
    let service: IntegrationID
    let repository: String?

    init(action: Action, repository: String) {
        self.action = action
        self.service = .github
        self.repository = repository
    }

    init(action: Action, service: IntegrationID, repository: String? = nil) {
        self.action = action
        self.service = service
        self.repository = repository
    }

    static let browserConnectableServices: Set<IntegrationID> = [.github, .linkedin, .notion, .slack]

    static func parse(_ url: URL) -> Self? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "suzzme", components.user == nil,
              components.password == nil, components.port == nil, components.fragment == nil,
              components.queryItems?.allSatisfy({ $0.value != nil }) == true else { return nil }
        let action: Action
        switch components.host?.lowercased() {
        case "browser": action = .requestConnection
        case "integrations": action = .openConnectionSetup
        default: return nil
        }
        let rawService = String(components.path.dropFirst()).lowercased()
        guard components.path == "/" + rawService,
              let service = IntegrationID(rawValue: rawService),
              browserConnectableServices.contains(service) else { return nil }
        if service == .github, let queryItems = components.queryItems, !queryItems.isEmpty {
            guard queryItems.count == 1,
                  queryItems.first?.name == "repository",
                  let rawRepository = queryItems.first?.value,
                  rawRepository.utf8.count <= 220,
                  let resource = IntegrationResourceResolver.resolve(url: "https://github.com/" + rawRepository),
                  resource.serviceID == .github, resource.kind == .githubRepository,
                  let owner = resource.attributes.owner, let name = resource.attributes.repository,
                  repository(in: "https://github.com/" + rawRepository) == owner + "/" + name,
                  rawRepository.caseInsensitiveCompare(owner + "/" + name) == .orderedSame else { return nil }
            return .init(action: action, service: service, repository: owner + "/" + name)
        }
        if service != .github, components.queryItems?.isEmpty == false { return nil }
        return .init(action: action, service: service)
    }

    static func url(for action: Action, repository: String) -> URL? {
        url(for: action, service: .github, repository: repository)
    }

    static func url(for action: Action, service: IntegrationID, repository: String? = nil) -> URL? {
        guard browserConnectableServices.contains(service) else { return nil }
        if service == .github, let repository {
            guard
                  let resource = IntegrationResourceResolver.resolve(url: "https://github.com/" + repository),
                  resource.kind == .githubRepository,
                  let owner = resource.attributes.owner, let name = resource.attributes.repository,
                  Self.repository(in: "https://github.com/" + repository) == owner + "/" + name,
                  repository.caseInsensitiveCompare(owner + "/" + name) == .orderedSame else { return nil }
        } else if service != .github && repository != nil { return nil }
        var components = URLComponents()
        components.scheme = "suzzme"
        components.host = action == .requestConnection ? "browser" : "integrations"
        components.path = "/" + service.rawValue
        if let repository { components.queryItems = [URLQueryItem(name: "repository", value: repository)] }
        return components.url
    }

    static func repository(in browserURL: String) -> String? {
        IntegrationResourceResolver.repositoryForConnection(url: browserURL)
    }
}

/// A request-local invitation to review access, never authentication or an
/// action approval. Only a validated service and optional GitHub slug are used.
struct IntegrationConnectionSuggestion: Equatable, Sendable {
    let repository: String
    let resourceURL: String
    let hasSavedAccount: Bool

    static func make(question: String, accounts: [IntegrationAccount]) -> Self? {
        guard question.utf8.count <= 4_096 else { return nil }
        let words = question.lowercased().split(whereSeparator: { !$0.isLetter })
        let consequential = ["create", "delete", "publish", "send", "merge", "update", "edit", "close", "reopen", "write", "remember", "save"]
        guard !consequential.contains(where: { words.contains(Substring($0)) }) else { return nil }
        let urls = question.split(whereSeparator: \.isWhitespace).filter { $0.hasPrefix("https://") }
        guard urls.count == 1, let raw = urls.first,
              let resource = IntegrationResourceResolver.resolve(url: String(raw)), resource.serviceID == .github,
              resource.kind == .githubIssue,
              let owner = resource.attributes.owner, let name = resource.attributes.repository else { return nil }
        if let selected = try? IntegrationAccountResolver.resolve(accounts: accounts, selected: nil),
           IntegrationRepositoryPolicy.permits(repo: owner + "/" + name, account: selected) { return nil }
        return .init(repository: owner + "/" + name, resourceURL: resource.canonicalURL.absoluteString,
                     hasSavedAccount: accounts.contains { $0.service == .github })
    }
}

/// One ephemeral handoff in the existing connection controller. It contains
/// no page contents, credentials, or authorization decisions.
struct BrowserIntegrationHandoff: Sendable {
    struct Request: Identifiable, Equatable, Sendable {
        let id: UUID
        let route: BrowserIntegrationRoute
        let createdAt: Date
        var service: IntegrationID { route.service }
        var repository: String? { route.repository }
        var displayName: String {
            switch service {
            case .github: "GitHub"
            case .linkedin: "LinkedIn"
            case .notion: "Notion"
            case .linear: "Linear"
            case .slack: "Slack"
            case .googleDocs: "Google Docs"
            case .googleCalendar: "Google Calendar"
            case .customMCP: "Custom MCP"
            default: service.rawValue
            }
        }
        func isCurrent(now: Date = .now) -> Bool {
            let age = now.timeIntervalSince(createdAt)
            return age >= 0 && age < 180
        }
    }
    enum Phase: Equatable, Sendable { case queued, review, alreadyAllowed, setup }
    private(set) var request: Request?
    private(set) var phase: Phase = .queued
    private var recent: [(route: BrowserIntegrationRoute, date: Date)] = []
    private var dismissedUntil: [IntegrationID: Date] = [:]

    @discardableResult mutating func receive(_ url: URL, now: Date = .now) -> Bool {
        guard let route = BrowserIntegrationRoute.parse(url) else { clear(); return false }
        dismissedUntil = dismissedUntil.filter { $0.value > now }
        guard dismissedUntil[route.service] == nil else { return false }
        recent.removeAll { entry in
            let lifetime: TimeInterval = entry.route.service == .github && entry.route.repository != nil ? 60 : 86_400
            return now.timeIntervalSince(entry.date) >= lifetime || now < entry.date
        }
        if let request, request.isCurrent(now: now), request.route == route { return false }
        guard !recent.contains(where: { $0.route == route }) else { return false }
        recent.append((route, now)); recent = Array(recent.suffix(16))
        request = .init(id: UUID(), route: route, createdAt: now); phase = .queued
        return true
    }
    mutating func resolve(id: UUID, accounts: [IntegrationAccount], now: Date = .now) {
        guard let request, request.id == id else { return }
        guard request.isCurrent(now: now) else { clear(); return }
        guard phase == .queued else { return }
        guard request.service == .github, let repository = request.repository else { phase = .review; return }
        let allowed = (try? IntegrationAccountResolver.resolve(accounts: accounts, selected: nil, service: .github)).map { account in
            guard let date = account.lastVerifiedAt else { return false }
            let age = now.timeIntervalSince(date)
            return age >= 0 && age <= 30 && IntegrationRepositoryPolicy.permits(repo: repository, account: account)
        } ?? false
        phase = allowed ? .alreadyAllowed : request.route.action == .openConnectionSetup ? .setup : .review
    }
    enum Decision: Sendable { case no, later, yes }
    @discardableResult mutating func decide(id: UUID, decision: Decision, now: Date = .now) -> Bool {
        guard let request, request.id == id else { return false }
        guard request.isCurrent(now: now) else { clear(); return false }
        guard phase == .review || phase == .alreadyAllowed else { return false }
        switch decision {
        case .no:
            dismissedUntil[request.service] = now.addingTimeInterval(30 * 86_400)
            clear()
        case .later:
            dismissedUntil[request.service] = now.addingTimeInterval(3_600)
            clear()
        case .yes:
            dismissedUntil[request.service] = now.addingTimeInterval(86_400)
            if phase == .review { phase = .setup } else { clear() }
        }
        return true
    }
    @discardableResult mutating func decide(id: UUID, openSetup: Bool, now: Date = .now) -> Bool {
        decide(id: id, decision: openSetup ? .yes : .later, now: now)
    }
    mutating func takeSetup(now: Date = .now) -> Request? {
        guard phase == .setup, let request else { return nil }
        guard request.isCurrent(now: now) else { clear(); return nil }
        clear(); return request
    }
    mutating func expire(id: UUID, now: Date = .now) {
        if let request, request.id == id, !request.isCurrent(now: now) { clear() }
    }
    mutating func clear() { request = nil; phase = .queued }
}

typealias BrowserGitHubHandoff = BrowserIntegrationHandoff
