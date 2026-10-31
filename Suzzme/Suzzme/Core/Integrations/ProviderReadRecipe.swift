import Foundation

/// Reviewed native reads, not model-supplied URLs, methods, scopes or tools.
/// These recipes describe schema projections; networking and account ownership
/// remain in the existing IntegrationGateway.
struct ProviderReadRecipe: Sendable, Identifiable {
    enum Authentication: Sendable { case bearer, raw, header(String), basic }
    struct Field: Sendable { let label: String; let path: String }
    struct Scope: Sendable { let key: String; let label: String }
    enum Pagination: Sendable { case none, cursor(path: String, parameter: String), page(parameter: String, first: Int) }
    let id: IntegrationID
    let name: String
    let origin: String
    let identityPath: String
    let identityID: String
    let identityName: String
    let readPath: String
    let itemsPath: String
    let fields: [Field]
    let scopes: [Scope]
    let permissions: String
    let documentation: String
    var authentication: Authentication = .bearer
    var headers: [String: String] = [:]
    var pagination: Pagination = .none
    var googleScope: String? = nil
    var identityOrigin: String? = nil

    func validates(_ scope: [String: String]) -> Bool {
        Set(scope.keys) == Set(scopes.map(\.key)) && scope.values.allSatisfy {
            !$0.isEmpty && $0.utf8.count <= 128 && $0.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 95].contains($0)
            }
        }
    }

    func url(path: String, scope: [String: String]) throws -> URL {
        guard validates(scope) else { throw IntegrationFailure.invalidConfiguration }
        var resolved = path
        for (key, value) in scope { resolved = resolved.replacingOccurrences(of: "{\(key)}", with: value) }
        let effectiveOrigin = path == identityPath ? identityOrigin ?? origin : origin
        guard !resolved.contains("{"), resolved.hasPrefix("/"), !resolved.hasPrefix("//"),
              let base = URLComponents(string: effectiveOrigin), let url = URL(string: effectiveOrigin + resolved),
              url.scheme == "https", url.host == base.host, url.user == nil, url.password == nil, url.port == nil else {
            throw IntegrationFailure.invalidConfiguration
        }
        return url
    }

    static func find(_ id: IntegrationID) -> Self? { catalog.first { $0.id == id } }

    static let catalog: [Self] = personalCatalog + googleCatalog
    static let personalCatalog: [Self] = [
        .init(id: .asana, name: "Asana", origin: "https://app.asana.com", identityPath: "/api/1.0/users/me", identityID: "data.gid", identityName: "data.name", readPath: "/api/1.0/tasks?assignee=me&workspace={workspace}&completed_since=now&limit=25&opt_fields=gid,name,due_on,due_at,completed", itemsPath: "data", fields: [.init(label: "Task", path: "name"), .init(label: "Due", path: "due_on"), .init(label: "Due time", path: "due_at"), .init(label: "Completed", path: "completed")], scopes: [.init(key: "workspace", label: "Workspace GID")], permissions: "Use a dedicated personal access token. Asana PATs inherit your account permissions; Suzzme sends read requests only. Workspace scope is limited to tasks assigned to you.", documentation: "https://developers.asana.com/docs/quick-start", pagination: .cursor(path: "next_page.offset", parameter: "offset")),
        .init(id: .airtable, name: "Airtable", origin: "https://api.airtable.com", identityPath: "/v0/meta/whoami", identityID: "id", identityName: "id", readPath: "/v0/{base}/{table}?pageSize=25", itemsPath: "records", fields: [.init(label: "Record", path: "id"), .init(label: "Fields", path: "fields")], scopes: [.init(key: "base", label: "Allowed base ID"), .init(key: "table", label: "Allowed table ID")], permissions: "Create a PAT with data.records:read and access only to this base. No record creation or schema changes.", documentation: "https://airtable.com/developers/web/api/list-records", pagination: .cursor(path: "offset", parameter: "offset")),
        .init(id: .clickUp, name: "ClickUp", origin: "https://api.clickup.com", identityPath: "/api/v2/user", identityID: "user.id", identityName: "user.username", readPath: "/api/v2/list/{list}/task?include_closed=false&page=0", itemsPath: "tasks", fields: [.init(label: "Task", path: "name"), .init(label: "Status", path: "status.status"), .init(label: "Due", path: "due_date")], scopes: [.init(key: "list", label: "Allowed list ID")], permissions: "Use a personal token for your own account. Restrict account access to the selected list where possible. Tokens may allow writes; Suzzme never dispatches them.", documentation: "https://developer.clickup.com/reference/gettasks", authentication: .raw, pagination: .page(parameter: "page", first: 0)),
        .init(id: .gitlab, name: "GitLab", origin: "https://gitlab.com", identityPath: "/api/v4/user", identityID: "id", identityName: "username", readPath: "/api/v4/projects/{project}/issues?per_page=25&state=opened&scope=assigned_to_me", itemsPath: "", fields: [.init(label: "Issue", path: "title"), .init(label: "State", path: "state"), .init(label: "Due", path: "due_date"), .init(label: "URL", path: "web_url")], scopes: [.init(key: "project", label: "Allowed numeric project ID")], permissions: "Use a GitLab.com PAT with read_api and read_user only. Self-hosted GitLab origins are not accepted.", documentation: "https://docs.gitlab.com/api/issues/", authentication: .header("PRIVATE-TOKEN"), pagination: .page(parameter: "page", first: 1)),
        .init(id: .figma, name: "Figma", origin: "https://api.figma.com", identityPath: "/v1/me", identityID: "id", identityName: "handle", readPath: "/v1/files/{file}?depth=1", itemsPath: "$object", fields: [.init(label: "File", path: "name"), .init(label: "Modified", path: "lastModified"), .init(label: "Version", path: "version")], scopes: [.init(key: "file", label: "Allowed file key")], permissions: "Create an expiring PAT with current_user:read and file_content:read. Only the selected file’s metadata is retrieved; no images or remote assets are downloaded.", documentation: "https://developers.figma.com/docs/rest-api/authentication/", authentication: .header("X-Figma-Token")),
        .init(id: .todoist, name: "Todoist", origin: "https://api.todoist.com", identityPath: "/api/v1/user", identityID: "id", identityName: "full_name", readPath: "/api/v1/tasks?limit=25", itemsPath: "results", fields: [.init(label: "Task", path: "content"), .init(label: "Due", path: "due.date"), .init(label: "Priority", path: "priority"), .init(label: "Completed", path: "is_completed")], scopes: [], permissions: "Personal API token for your own account. OAuth data:read is preferred for distribution; app registration is required. Suzzme reads active tasks only.", documentation: "https://developer.todoist.com/api/v1/", pagination: .cursor(path: "next_cursor", parameter: "cursor")),
        .init(id: .typeform, name: "Typeform", origin: "https://api.typeform.com", identityPath: "/me", identityID: "email", identityName: "alias", readPath: "/forms?page_size=25", itemsPath: "items", fields: [.init(label: "Form", path: "title"), .init(label: "Created", path: "created_at"), .init(label: "Updated", path: "last_updated_at")], scopes: [], permissions: "Create a personal token with accounts:read and forms:read only. Respondent answers are not retrieved.", documentation: "https://www.typeform.com/developers/create/reference/retrieve-forms/", pagination: .page(parameter: "page", first: 1)),
        .init(id: .pushbullet, name: "Pushbullet", origin: "https://api.pushbullet.com", identityPath: "/v2/users/me", identityID: "iden", identityName: "name", readPath: "/v2/pushes?limit=25&active=true", itemsPath: "pushes", fields: [.init(label: "Title", path: "title"), .init(label: "Type", path: "type"), .init(label: "Created", path: "created")], scopes: [], permissions: "Personal access token for your own account. Reads push titles and types only, never SMS, contacts or mirrored notifications.", documentation: "https://docs.pushbullet.com/v7/", authentication: .header("Access-Token"), pagination: .cursor(path: "cursor", parameter: "cursor")),
        .init(id: .harvest, name: "Harvest", origin: "https://api.harvestapp.com", identityPath: "/v2/users/me", identityID: "id", identityName: "first_name", readPath: "/v2/time_entries?user_id={user}&per_page=25", itemsPath: "time_entries", fields: [.init(label: "Project", path: "project.name"), .init(label: "Task", path: "task.name"), .init(label: "Date", path: "spent_date"), .init(label: "Hours", path: "hours")], scopes: [.init(key: "account", label: "Harvest account ID"), .init(key: "user", label: "Your Harvest user ID")], permissions: "Dedicated personal token and account ID. Harvest PATs inherit account permissions. Reads only the selected user’s time entries.", documentation: "https://help.getharvest.com/api-v2/time-tracking-api/time-entries/time-entries/", headers: ["Harvest-Account-ID": "{account}"], pagination: .page(parameter: "page", first: 1)),
        .init(id: .wakatime, name: "WakaTime", origin: "https://wakatime.com", identityPath: "/api/v1/users/current", identityID: "data.id", identityName: "data.display_name", readPath: "/api/v1/users/current/stats/last_7_days", itemsPath: "$dataObject", fields: [.init(label: "Period", path: "human_readable_range"), .init(label: "Coding time", path: "human_readable_total"), .init(label: "Daily average", path: "human_readable_daily_average")], scopes: [], permissions: "Personal WakaTime API key for your own account. Only aggregate seven-day statistics, never file names or source code.", documentation: "https://wakatime.com/developers/", authentication: .basic),
        .init(id: .ynab, name: "YNAB", origin: "https://api.ynab.com", identityPath: "/v1/user", identityID: "data.user.id", identityName: "data.user.id", readPath: "/v1/plans", itemsPath: "data.plans", fields: [.init(label: "Plan", path: "name"), .init(label: "Modified", path: "last_modified_on")], scopes: [], permissions: "Personal token for your own account. Reads plan names and modification dates only; no transactions or balances.", documentation: "https://api.ynab.com/"),
        .init(id: .contentful, name: "Contentful", origin: "https://api.contentful.com", identityPath: "/users/me", identityID: "sys.id", identityName: "firstName", readPath: "/spaces/{space}/environments/{environment}/entries?limit=25", itemsPath: "items", fields: [.init(label: "Entry", path: "sys.id"), .init(label: "Updated", path: "sys.updatedAt"), .init(label: "Content type", path: "sys.contentType.sys.id")], scopes: [.init(key: "space", label: "Allowed space ID"), .init(key: "environment", label: "Allowed environment ID")], permissions: "Use a content_management_read PAT and a role limited to this space/environment. Reads entry metadata, not full content.", documentation: "https://www.contentful.com/developers/docs/references/content-management-api/", pagination: .page(parameter: "skip", first: 0)),
        .init(id: .eventbrite, name: "Eventbrite", origin: "https://www.eventbriteapi.com", identityPath: "/v3/users/me/", identityID: "id", identityName: "name", readPath: "/v3/organizations/{organization}/events/?page_size=25&status=live", itemsPath: "events", fields: [.init(label: "Event", path: "name.text"), .init(label: "Start", path: "start.local"), .init(label: "Time zone", path: "start.timezone"), .init(label: "Status", path: "status")], scopes: [.init(key: "organization", label: "Allowed organization ID")], permissions: "Personal token for events you organize. Public event search, attendees and orders are not read.", documentation: "https://www.eventbrite.com/platform/api", pagination: .page(parameter: "page", first: 1))
    ]
}
