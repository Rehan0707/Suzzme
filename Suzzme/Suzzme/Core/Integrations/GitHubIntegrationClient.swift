import Foundation
import MCP

private final class GitHubIdentityRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// REST is used only to bind the credential to its verified durable account ID.
/// All resource reads use the reviewed, read-only official MCP endpoint.
struct GitHubIntegrationClient: GitHubIntegrationServing {
    func verify(token: String) async throws -> GitHubIntegrationVerification {
        let identity = try await authenticatedIdentity(token: token)
        let tools: [GitHubMCPDiscoveredTool]
        do { tools = try await GitHubMCPClient().connectAndDiscover(token: token) }
        catch { throw mapped(error) }
        let digests = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0.schemaDigest) })
        guard !digests.isEmpty else { throw IntegrationFailure.connectorUnavailable }
        return .init(identity: identity, toolDigests: digests)
    }

    func read(token: String, resource: IntegrationResolvedResource, toolDigests: [String: String]) async throws -> String {
        guard resource.serviceID == .github,
              let owner = resource.attributes.owner, let repo = resource.attributes.repository else { throw IntegrationFailure.unsupported }
        var arguments: [String: MCP.Value] = ["owner": .string(owner), "repo": .string(repo)]
        let tool: String
        switch resource.kind {
        case .githubIssue:
            guard let number = resource.attributes.number else { throw IntegrationFailure.unsupported }
            tool = "issue_read"; arguments["method"] = .string("get"); arguments["issue_number"] = .int(number)
        case .githubPullRequest:
            guard let number = resource.attributes.number else { throw IntegrationFailure.unsupported }
            tool = "pull_request_read"; arguments["method"] = .string("get"); arguments["pullNumber"] = .int(number)
        case .githubRepository:
            // The official tool defaults an omitted path to the repository root.
            tool = "get_file_contents"
        case .githubFile:
            guard let file = resource.attributes.file, let ref = resource.attributes.ref else { throw IntegrationFailure.unsupported }
            tool = "get_file_contents"; arguments["path"] = .string(file); arguments["ref"] = .string(ref)
        default: throw IntegrationFailure.unsupported
        }
        guard let digest = toolDigests[tool] else { throw IntegrationFailure.schemaChanged }
        do { return try await GitHubMCPClient().read(token: token, tool: tool, arguments: arguments, expectedSchemaDigest: digest) }
        catch { throw mapped(error) }
    }

    private func mapped(_ error: Error) -> any Error {
        if error is CancellationError { return CancellationError() }
        guard let error = error as? GitHubMCPClientError else { return IntegrationFailure.connectorUnavailable }
        switch error {
        case .authenticationExpired, .accessDenied: return IntegrationFailure.authenticationExpired
        case .schemaChanged: return IntegrationFailure.schemaChanged
        case .responseTooLarge: return IntegrationFailure.oversizedResult
        case .credentialLeak: return IntegrationFailure.policyDenied
        case .cancelled: return CancellationError()
        default: return IntegrationFailure.connectorUnavailable
        }
    }

    private func authenticatedIdentity(token: String) async throws -> GitHubIntegrationIdentity {
        guard let endpoint = URL(string: "https://api.github.com/user") else { throw IntegrationFailure.connectorUnavailable }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCache = nil; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration, delegate: GitHubIdentityRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.url == endpoint else { throw IntegrationFailure.connectorUnavailable }
        guard http.statusCode != 401 && http.statusCode != 403 else { throw IntegrationFailure.authenticationExpired }
        guard http.statusCode == 200 else { throw IntegrationFailure.connectorUnavailable }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 32_768 else { throw IntegrationFailure.oversizedResult }
            data.append(byte)
        }
        let identity = try JSONDecoder().decode(GitHubIntegrationIdentity.self, from: data)
        guard identity.id > 0, !identity.login.isEmpty, identity.login.utf8.count <= 100 else { throw IntegrationFailure.connectorUnavailable }
        return identity
    }
}
