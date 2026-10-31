import Foundation

/// Linear access is restricted to two fixed GraphQL query shapes. The token is
/// never exposed to the model, UI state, logs, or provider-controlled redirects.
struct LinearIntegrationClient: LinearIntegrationServing {
    private static let issueQuery = """
    query SuzzmeIssue($id: String!) {
      issue(id: $id) {
        id identifier title description url updatedAt
        state { name }
        team { name }
        assignee { name }
      }
    }
    """
    private static let viewerQuery = "query SuzzmeViewer { viewer { id name email } }"
    private static let endpoint = URL(string: "https://api.linear.app/graphql")!
    private static let responseLimit = 96 * 1024
    private static let descriptionLimit = 24 * 1024

    func verify(token: String, allowedIssueIDs: [String]) async throws -> LinearIntegrationIdentity {
        guard validToken(token), !allowedIssueIDs.isEmpty,
              allowedIssueIDs.count <= IntegrationLinearIssuePolicy.maximumIssues,
              allowedIssueIDs.allSatisfy({ IntegrationLinearIssuePolicy.normalized($0) == $0 }) else {
            throw IntegrationFailure.invalidConfiguration
        }
        let identity = try await viewer(token: token)
        for issueID in allowedIssueIDs {
            let issue = try await fetchIssue(token: token, identifier: issueID)
            guard issue.identifier == issueID else { throw IntegrationFailure.repositoryDenied }
        }
        return identity
    }

    func read(token: String, issueID: String, expectedProviderID: String) async throws -> String {
        guard validToken(token), let normalized = IntegrationLinearIssuePolicy.normalized(issueID),
              normalized == issueID, !expectedProviderID.isEmpty else { throw IntegrationFailure.invalidConfiguration }
        let identity = try await viewer(token: token)
        guard identity.id == expectedProviderID else { throw IntegrationFailure.staleContext }
        let issue = try await fetchIssue(token: token, identifier: normalized)
        guard issue.identifier == normalized else { throw IntegrationFailure.repositoryDenied }
        var lines = [
            "Linear issue: \(issue.identifier) · \(issue.title)",
            "URL: \(issue.url)"
        ]
        if let team = issue.teamName { lines.append("Team: \(team)") }
        if let state = issue.stateName { lines.append("Status: \(state)") }
        if let assignee = issue.assigneeName { lines.append("Assignee: \(assignee)") }
        if let updatedAt = issue.updatedAt { lines.append("Updated: \(updatedAt)") }
        if let description = issue.description, !description.isEmpty {
            let bounded = String(decoding: description.utf8.prefix(Self.descriptionLimit), as: UTF8.self)
            lines.append("Description:\n\(bounded)")
            if description.utf8.count > Self.descriptionLimit { lines.append("Description excerpt is partial.") }
        }
        let result = lines.joined(separator: "\n")
        guard result.utf8.count <= 32_768, !IntegrationCredentialGuard.containsSecret(in: result, token: token) else {
            throw IntegrationFailure.oversizedResult
        }
        return result
    }

    private func viewer(token: String) async throws -> LinearIntegrationIdentity {
        let root = try await execute(query: Self.viewerQuery, variables: [:], token: token, issueRequest: false)
        guard let data = root["data"] as? [String: Any],
              let viewer = data["viewer"] as? [String: Any],
              let id = boundedString(viewer["id"], maximum: 100),
              let name = boundedString(viewer["name"], maximum: 100), !id.isEmpty, !name.isEmpty else {
            throw IntegrationFailure.connectorUnavailable
        }
        let email = boundedString(viewer["email"], maximum: 254)
        return .init(id: id, name: name, email: email)
    }

    private func fetchIssue(token: String, identifier: String) async throws -> LinearIntegrationIssue {
        guard IntegrationLinearIssuePolicy.normalized(identifier) == identifier else { throw IntegrationFailure.invalidConfiguration }
        let root = try await execute(query: Self.issueQuery, variables: ["id": identifier], token: token, issueRequest: true)
        guard let data = root["data"] as? [String: Any],
              let value = data["issue"] as? [String: Any],
              let id = boundedString(value["id"], maximum: 100), !id.isEmpty,
              let actualIdentifier = boundedString(value["identifier"], maximum: 32),
              let normalizedIdentifier = IntegrationLinearIssuePolicy.normalized(actualIdentifier),
              normalizedIdentifier == identifier,
              let title = boundedString(value["title"], maximum: 2_048),
              let rawURL = boundedString(value["url"], maximum: 2_048),
              let url = URL(string: rawURL), url.scheme == "https", url.host == "linear.app",
              IntegrationResourceResolver.resolve(url: rawURL)?.attributes.linearIssueID == identifier else {
            throw IntegrationFailure.repositoryDenied
        }
        let state = value["state"] as? [String: Any]
        let team = value["team"] as? [String: Any]
        let assignee = value["assignee"] as? [String: Any]
        return .init(id: id, identifier: identifier, title: title,
                     description: boundedString(value["description"], maximum: Self.responseLimit),
                     url: url.absoluteString,
                     updatedAt: boundedString(value["updatedAt"], maximum: 64),
                     stateName: boundedString(state?["name"], maximum: 200),
                     teamName: boundedString(team?["name"], maximum: 200),
                     assigneeName: boundedString(assignee?["name"], maximum: 200))
    }

    private func execute(query: String, variables: [String: String], token: String,
                        issueRequest: Bool) async throws -> [String: Any] {
        guard validToken(token), query.hasPrefix("query "), !query.localizedCaseInsensitiveContains("mutation"),
              let body = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              body.count <= 8_192 else { throw IntegrationFailure.invalidConfiguration }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 20
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: IntegrationRedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard response.url == Self.endpoint, let http = response as? HTTPURLResponse,
                  !(300...399).contains(http.statusCode),
                  response.expectedContentLength <= Int64(Self.responseLimit) else {
                throw IntegrationFailure.connectorUnavailable
            }
            switch http.statusCode {
            case 200...299: break
            case 401: throw IntegrationFailure.authenticationExpired
            case 403: throw IntegrationFailure.repositoryDenied
            default: throw IntegrationFailure.connectorUnavailable
            }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < Self.responseLimit else { throw IntegrationFailure.oversizedResult }
                data.append(byte)
            }
            guard !IntegrationCredentialGuard.containsSecret(in: data, token: token),
                  validJSONDepth(data),
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  !IntegrationCredentialGuard.containsSecret(in: root, token: token),
                  root["errors"] == nil else {
                if issueRequest { throw IntegrationFailure.repositoryDenied }
                throw IntegrationFailure.connectorUnavailable
            }
            return root
        } catch is CancellationError { throw CancellationError() }
        catch let failure as IntegrationFailure { throw failure }
        catch { throw IntegrationFailure.connectorUnavailable }
    }

    private func validToken(_ token: String) -> Bool {
        !token.isEmpty && token.utf8.count <= 1_024 && !token.contains(where: \.isWhitespace)
    }

    private func boundedString(_ value: Any?, maximum: Int) -> String? {
        guard let value = value as? String, value.utf8.count <= maximum,
              !value.contains("\0") else { return nil }
        return value
    }

    private func validJSONDepth(_ data: Data) -> Bool {
        var depth = 0
        var quoted = false
        var escaped = false
        for byte in data {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 123 || byte == 91 {
                depth += 1
                if depth > 24 { return false }
            } else if byte == 125 || byte == 93 {
                depth -= 1
                if depth < 0 { return false }
            }
        }
        return depth == 0 && !quoted
    }
}
