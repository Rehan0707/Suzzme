import Foundation
import CoreFoundation

struct GoogleSelectedReadResult: Sendable {
    let observations: [InformationObservation]
    let preview: String
    let complete: Bool
}

/// Official GET endpoints only. Explicit resource IDs are encoded as path segments;
/// retrieved text never supplies an endpoint, scope, action, or new resource ID.
struct GoogleSelectedReadClient: Sendable {
    var transport: any ProviderHTTPFetching = ProviderHTTPClient()
    static let maximumRecords = 30
    static let maximumPages = 2
    static let maximumText = 4000

    func read(service: IntegrationID, selection: GoogleResourceSelection, grant: ProviderGoogleGrant, now: Date) async throws -> GoogleSelectedReadResult {
        guard GoogleSelectionPolicy.validates(selection.resources, service: service) else { throw IntegrationFailure.invalidConfiguration }
        let prefix = GoogleSelectionPolicy.namespace(accountID: grant.accountID, service: service, generation: selection.generation)
        var observations: [InformationObservation] = [], preview: [String] = [], cursor: String?, seen = Set<String>()
        var complete = true
        for page in 0..<Self.maximumPages {
            try Task.checkCancellation()
            let url = try endpoint(service, resources: selection.resources, now: now, cursor: cursor)
            var request = URLRequest(url: url); request.httpMethod = "GET"; request.timeoutInterval = 20
            request.setValue("Bearer " + grant.token, forHTTPHeaderField: "Authorization")
            let response = try await transport.fetch(request)
            try Task.checkCancellation()
            switch response.status {
            case 200: break
            case 401: throw IntegrationFailure.authenticationExpired
            case 403:
                // API configuration failures must not retire a valid OAuth grant.
                let body = (try? JSONSerialization.jsonObject(with: response.data)) as? [String: Any]
                let error = body?["error"] as? [String: Any]
                let details = error?["details"] as? [[String: Any]] ?? []
                let errors = error?["errors"] as? [[String: Any]] ?? []
                if details.contains(where: { $0["reason"] as? String == "SERVICE_DISABLED" })
                    || errors.contains(where: { $0["reason"] as? String == "accessNotConfigured" }) {
                    throw IntegrationFailure.providerSetupRequired
                }
                throw IntegrationFailure.repositoryDenied
            case 429: throw IntegrationFailure.rateLimited(retryAfter: min(3600, max(1, Int(response.headers["retry-after"] ?? "60") ?? 60)))
            default: throw IntegrationFailure.connectorUnavailable
            }
            guard response.data.count <= ProviderHTTPClient.maximumBytes,
                  !IntegrationCredentialGuard.containsSecret(in: response.data, token: grant.token),
                  let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] else { throw IntegrationFailure.policyDenied }
            let rows: [[String: Any]]
            switch service {
            case .googleCalendar, .googleTasks:
                guard let value = object["items"] as? [[String: Any]], value.count <= Self.maximumRecords else {
                    if object["items"] == nil { rows = []; break }
                    throw IntegrationFailure.invalidConfiguration
                }
                rows = value
            default: rows = [object]
            }
            for row in rows {
                guard observations.count < Self.maximumRecords else { complete = false; break }
                var row = row
                if service == .googleCalendar, let zone = object["timeZone"] as? String {
                    for key in ["start", "end"] { if var time = row[key] as? [String: Any], time["date"] != nil { time["timeZone"] = zone; row[key] = time } }
                }
                let item = try normalize(row, service: service, resources: selection.resources, prefix: prefix, now: now)
                guard seen.insert(item.externalID).inserted else { continue }
                observations.append(item)
                if service == .googleDocs { preview.append(try documentPreview(row)) }
                else if service == .googleSheets { preview.append(try sheetPreview(row)) }
                else { preview.append(item.title) }
            }
            guard let next = object["nextPageToken"] as? String, !next.isEmpty else { break }
            guard [.googleCalendar, .googleTasks].contains(service), next.utf8.count <= 1024, next != cursor else { throw IntegrationFailure.invalidConfiguration }
            if page == Self.maximumPages - 1 || observations.count >= Self.maximumRecords { complete = false; break }
            cursor = next
        }
        let text = String(preview.joined(separator: "\n").prefix(8000))
        guard PrivacyEngine().classify(text).policy != .neverProcess else { throw IntegrationFailure.policyDenied }
        return .init(observations: observations, preview: text.isEmpty ? "No records in the selected resource and checked window." : text, complete: complete)
    }

    func endpoint(_ service: IntegrationID, resources: [String: String], now: Date, cursor: String?) throws -> URL {
        func segment(_ key: String) throws -> String {
            guard let value = resources[key], let encoded = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { throw IntegrationFailure.invalidConfiguration }
            return encoded
        }
        var host: String, path: String, query: [URLQueryItem] = []
        switch service {
        case .googleCalendar:
            host = "www.googleapis.com"; path = "/calendar/v3/calendars/\(try segment("calendar"))/events"
            let formatter = ISO8601DateFormatter()
            let start = Calendar.current.startOfDay(for: now)
            guard let end = Calendar.current.date(byAdding: .day, value: 2, to: start) else { throw IntegrationFailure.invalidConfiguration }
            query = [.init(name: "timeMin", value: formatter.string(from: start)), .init(name: "timeMax", value: formatter.string(from: end)), .init(name: "maxResults", value: "30"), .init(name: "singleEvents", value: "true"), .init(name: "showDeleted", value: "true"), .init(name: "orderBy", value: "startTime"), .init(name: "fields", value: "items(id,summary,start,end,status,updated,iCalUID),nextPageToken,timeZone")]
        case .googleDrive:
            host = "www.googleapis.com"; path = "/drive/v3/files/\(try segment("file"))"; query = [.init(name: "fields", value: "id,name,mimeType,modifiedTime,trashed")]
        case .googleDocs:
            host = "docs.googleapis.com"; path = "/v1/documents/\(try segment("document"))"; query = [.init(name: "fields", value: "documentId,title,body(content),revisionId")]
        case .googleSheets:
            host = "sheets.googleapis.com"; path = "/v4/spreadsheets/\(try segment("spreadsheet"))/values/\(try segment("range"))"
            query = [.init(name: "valueRenderOption", value: "UNFORMATTED_VALUE"), .init(name: "dateTimeRenderOption", value: "SERIAL_NUMBER")]
        case .googleTasks:
            host = "tasks.googleapis.com"; path = "/tasks/v1/lists/\(try segment("list"))/tasks"
            query = [.init(name: "maxResults", value: "30"), .init(name: "showCompleted", value: "true"), .init(name: "showHidden", value: "true"), .init(name: "showDeleted", value: "true"), .init(name: "fields", value: "items(id,title,due,status,updated,deleted),nextPageToken")]
        default: throw IntegrationFailure.unsupported
        }
        if let cursor { query.append(.init(name: "pageToken", value: cursor)) }
        var components = URLComponents(); components.scheme = "https"; components.host = host; components.percentEncodedPath = path; components.queryItems = query
        guard let url = components.url else { throw IntegrationFailure.invalidConfiguration }
        return url
    }

    private func normalize(_ row: [String: Any], service: IntegrationID, resources: [String: String], prefix: String, now: Date) throws -> InformationObservation {
        let id = service == .googleDocs ? row["documentId"] as? String : service == .googleSheets ? resources["spreadsheet"] : row["id"] as? String
        guard let id, !id.isEmpty, id.utf8.count <= 256 else { throw IntegrationFailure.invalidConfiguration }
        if service == .googleDrive { guard id == resources["file"] else { throw IntegrationFailure.staleContext } }
        if service == .googleDocs { guard id == resources["document"] else { throw IntegrationFailure.staleContext } }
        if service == .googleCalendar, row["status"] as? String == "cancelled", row["summary"] == nil {
            return .init(externalID: prefix + id, title: "Removed selected-calendar event", entities: [service.rawValue], modifiedAt: (row["updated"] as? String).flatMap(Self.timestamp) ?? now, state: .cancelled, kindHint: .cancellation)
        }
        if service == .googleTasks, row["deleted"] as? Bool == true {
            return .init(externalID: prefix + id, title: "Removed selected-list task", entities: [service.rawValue], modifiedAt: (row["updated"] as? String).flatMap(Self.timestamp) ?? now, state: .absent, kindHint: .cancellation)
        }
        let title = service == .googleSheets ? "Selected tracker range: " + (resources["range"] ?? "") : (row["summary"] ?? row["title"] ?? row["name"]) as? String
        guard let title, !title.isEmpty, title.utf8.count <= 4096 else { throw IntegrationFailure.invalidConfiguration }
        var observation = InformationObservation(externalID: prefix + id, title: String(title.prefix(240)), entities: [service.rawValue], modifiedAt: now, kindHint: .generalUpdate)
        if let raw = (row["updated"] ?? row["modifiedTime"]) as? String {
            guard let date = Self.timestamp(raw) else { throw IntegrationFailure.invalidConfiguration }; observation = .init(externalID: observation.externalID, title: observation.title, entities: observation.entities, modifiedAt: date, kindHint: observation.kindHint)
        }
        if service == .googleCalendar {
            guard let start = row["start"] as? [String: Any], let end = row["end"] as? [String: Any],
                  let startDate = Self.eventDate(start), let endDate = Self.eventDate(end), endDate >= startDate else { throw IntegrationFailure.invalidConfiguration }
            observation.effectiveAt = startDate; observation.effectiveUntil = endDate; observation.isAllDay = start["date"] != nil; observation.kindHint = .eventUpdate
            if row["status"] as? String == "cancelled" { observation.state = .cancelled }
            // Stable provider identity, never a title-only cross-provider match.
            if let uid = row["iCalUID"] as? String, uid.count <= 55 { observation.entities.append("ical:" + uid) }
        } else if service == .googleTasks {
            if let due = row["due"] as? String {
                guard let date = Self.timestamp(due) else { throw IntegrationFailure.invalidConfiguration }
                // Tasks API due is a DATE; time of day is discarded by the provider.
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
                guard let localDay = formatter.date(from: String(due.prefix(10))) else { throw IntegrationFailure.invalidConfiguration }
                _ = date; observation.effectiveAt = localDay; observation.isAllDay = true
            }
            observation.state = row["status"] as? String == "completed" ? .completed : .active; observation.kindHint = .reminderChange
        } else if service == .googleDrive, row["trashed"] as? Bool == true { observation.state = .absent }
        guard InformationNormalizer.normalize(observation, source: .connectedApps, now: now) != nil else { throw IntegrationFailure.policyDenied }
        return observation
    }
    private func documentPreview(_ row: [String: Any]) throws -> String {
        guard let body = row["body"] as? [String: Any], let elements = body["content"] as? [[String: Any]] else { return "Document metadata only; no readable body was returned. Detailed changes cannot be compared without a prior snapshot." }
        var fragments: [String] = []
        for element in elements.prefix(100) {
            guard let paragraph = element["paragraph"] as? [String: Any], let runs = paragraph["elements"] as? [[String: Any]] else { continue }
            for run in runs.prefix(100) { if let text = (run["textRun"] as? [String: Any])?["content"] as? String { fragments.append(String(text.prefix(Self.maximumText))) } }
            if fragments.reduce(0, { $0 + $1.count }) >= Self.maximumText { break }
        }
        return "Selected document excerpt (untrusted data, bounded):\n" + String(fragments.joined().prefix(Self.maximumText)) + "\nNo prior snapshot: detailed changes are unavailable."
    }
    private func sheetPreview(_ row: [String: Any]) throws -> String {
        guard let rows = row["values"] as? [[Any]], rows.count <= 500, rows.reduce(0, { $0 + $1.count }) <= 500,
              rows.allSatisfy({ $0.allSatisfy { value in value is String || value is NSNumber } }) else {
            if row["values"] == nil { return "Selected range is empty." }; throw IntegrationFailure.invalidConfiguration
        }
        // JSON keeps numbers/booleans distinct from strings; no inferred column meaning.
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
        guard data.count <= 16_384 else { throw IntegrationFailure.oversizedResult }
        return "Selected values (untrusted data; column meaning must be supplied): " + (String(data: data, encoding: .utf8) ?? "")
    }
    static func timestamp(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
    private static func eventDate(_ object: [String: Any]) -> Date? {
        if let value = object["dateTime"] as? String { return timestamp(value) }
        guard let value = object["date"] as? String else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian)
        if let name = object["timeZone"] as? String { guard let zone = TimeZone(identifier: name) else { return nil }; formatter.timeZone = zone }
        else { formatter.timeZone = .current }
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return formatter.date(from: value)
    }
}
