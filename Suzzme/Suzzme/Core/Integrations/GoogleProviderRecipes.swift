import Foundation

struct ProviderGoogleGrant: Sendable {
    let token: String
    let accountID: String
    let generation: UUID
}
struct GoogleSummaryScope: Sendable {
    let service: IntegrationID
    let accountID: UUID
    let generation: UUID
    let prefix: String
    let resources: [String: String]
}
protocol GoogleIntegrationAuthorizing: Sendable {
    func googleGrant(service: IntegrationID) async throws -> ProviderGoogleGrant
    func validateGoogleIdentity(accountID: String, generation: UUID, service: IntegrationID) async -> Bool
    func selectedGoogleRead(service: IntegrationID, resources: [String: String], grant: ProviderGoogleGrant) async throws -> String?
    func validateGoogleSelection(service: IntegrationID, resources: [String: String], accountID: String) async -> Bool
    func invalidateGoogle(service: IntegrationID, grant: ProviderGoogleGrant) async
    func googleIdentity() async -> String?
    func googleSummaryScopes() async -> [GoogleSummaryScope]
    func googleSelectionVersion(service: IntegrationID, resources: [String: String], accountID: String) async -> String?

}

extension GoogleIntegrationAuthorizing {
    func selectedGoogleRead(service: IntegrationID, resources: [String: String], grant: ProviderGoogleGrant) async throws -> String? { nil }
    func validateGoogleSelection(service: IntegrationID, resources: [String: String], accountID: String) async -> Bool { true }
    func invalidateGoogle(service: IntegrationID, grant: ProviderGoogleGrant) async { }
    func googleIdentity() async -> String? { nil }
    func googleSummaryScopes() async -> [GoogleSummaryScope] { [] }
    func googleSelectionVersion(service: IntegrationID, resources: [String: String], accountID: String) async -> String? { "legacy" }
}
extension ProviderReadRecipe {
    private static func google(_ id: IntegrationID, _ name: String, _ host: String, _ path: String,
                               _ items: String, _ fields: [(String, String)], scope: String,
                               resources: [(String, String)] = [], documentation: String) -> Self {
        .init(id: id, name: name, origin: "https://" + host,
              identityPath: "/oauth2/v3/userinfo", identityID: "sub", identityName: "name", readPath: path,
              itemsPath: items, fields: fields.map { .init(label: $0.0, path: $0.1) },
              scopes: resources.map { .init(key: $0.0, label: $0.1) },
              permissions: "Google sign-in asks only for \(scope) when you connect this service. Suzzme retrieves bounded read-only information; it never changes the provider.",
              documentation: documentation, pagination: .cursor(path: "nextPageToken", parameter: "pageToken"),
              googleScope: "https://www.googleapis.com/auth/" + scope, identityOrigin: "https://www.googleapis.com")
    }
    static let googleCatalog: [Self] = [
        google(.googleDrive, "Google Drive", "www.googleapis.com", "/drive/v3/files?pageSize=25&q=trashed%3Dfalse&fields=files(id,name,mimeType,modifiedTime),nextPageToken", "files", [("File", "name"), ("Type", "mimeType"), ("Modified", "modifiedTime")], scope: "drive.metadata.readonly", documentation: "https://developers.google.com/drive/api/reference/rest/v3/files/list"),
        google(.googleCalendar, "Google Calendar", "www.googleapis.com", "/calendar/v3/calendars/primary/events?maxResults=25&singleEvents=true&orderBy=startTime", "items", [("Event", "summary"), ("Start", "start.dateTime"), ("All-day start", "start.date"), ("End", "end.dateTime"), ("Status", "status")], scope: "calendar.events.readonly", documentation: "https://developers.google.com/workspace/calendar/api/v3/reference/events/list"),
        google(.googleDocs, "Google Docs", "docs.googleapis.com", "/v1/documents/{document}?fields=documentId,title,revisionId", "$object", [("Document", "title"), ("Revision", "revisionId")], scope: "documents.readonly", resources: [("document", "Allowed document ID")], documentation: "https://developers.google.com/workspace/docs/api/reference/rest/v1/documents/get"),
        google(.googleSheets, "Google Sheets", "sheets.googleapis.com", "/v4/spreadsheets/{spreadsheet}?fields=spreadsheetId,properties(title,locale,timeZone)", "$object", [("Spreadsheet", "properties.title"), ("Locale", "properties.locale"), ("Time zone", "properties.timeZone")], scope: "spreadsheets.readonly", resources: [("spreadsheet", "Allowed spreadsheet ID")], documentation: "https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/get"),
        google(.googleSlides, "Google Slides", "slides.googleapis.com", "/v1/presentations/{presentation}?fields=presentationId,title,revisionId", "$object", [("Presentation", "title"), ("Revision", "revisionId")], scope: "presentations.readonly", resources: [("presentation", "Allowed presentation ID")], documentation: "https://developers.google.com/workspace/slides/api/reference/rest/v1/presentations/get"),
        google(.googleTasks, "Google Tasks", "tasks.googleapis.com", "/tasks/v1/lists/{list}/tasks?maxResults=25&showCompleted=false&showHidden=false", "items", [("Task", "title"), ("Due", "due"), ("Status", "status"), ("Updated", "updated")], scope: "tasks.readonly", resources: [("list", "Allowed task list ID")], documentation: "https://developers.google.com/workspace/tasks/reference/rest/v1/tasks/list"),
        google(.googleClassroom, "Google Classroom", "classroom.googleapis.com", "/v1/courses?pageSize=25&courseStates=ACTIVE", "courses", [("Course", "name"), ("Section", "section"), ("Room", "room"), ("Status", "courseState")], scope: "classroom.courses.readonly", documentation: "https://developers.google.com/workspace/classroom/reference/rest/v1/courses/list"),
        google(.googleMeet, "Google Meet", "meet.googleapis.com", "/v2/conferenceRecords?pageSize=25", "conferenceRecords", [("Conference", "name"), ("Start", "startTime"), ("End", "endTime")], scope: "meetings.space.readonly", documentation: "https://developers.google.com/workspace/meet/api/reference/rest/v2/conferenceRecords/list"),
        google(.googleAnalytics, "Google Analytics", "analyticsadmin.googleapis.com", "/v1alpha/accounts?pageSize=25", "accounts", [("Account", "displayName"), ("Resource", "name"), ("Updated", "updateTime")], scope: "analytics.readonly", documentation: "https://developers.google.com/analytics/devguides/config/admin/v1/rest/v1alpha/accounts/list"),
        google(.googleSearchConsole, "Google Search Console", "www.googleapis.com", "/webmasters/v3/sites", "siteEntry", [("Site", "siteUrl"), ("Permission", "permissionLevel")], scope: "webmasters.readonly", documentation: "https://developers.google.com/webmaster-tools/v1/sites/list"),
        google(.googleBigQuery, "Google BigQuery", "bigquery.googleapis.com", "/bigquery/v2/projects/{project}/datasets?maxResults=25", "datasets", [("Dataset", "datasetReference.datasetId"), ("Project", "datasetReference.projectId"), ("Location", "location")], scope: "bigquery.readonly", resources: [("project", "Allowed Google Cloud project ID")], documentation: "https://cloud.google.com/bigquery/docs/reference/rest/v2/datasets/list")
    ]
}
