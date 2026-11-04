import Foundation
@main struct BrowserAppCatalogChecks {
    static func main() throws {
        var count = 0
        func check(_ condition: Bool, _ message: String) { precondition(condition, message); count += 1 }
        let ids = Set(BrowserAppCatalog.entries.compactMap { IntegrationID(rawValue: $0.service) })
        check(ids == BrowserIntegrationRoute.browserConnectableServices, "Every available integration has a detection domain")
        for entry in BrowserAppCatalog.entries {
            check(BrowserAppCatalog.service(for: "https://" + entry.host + entry.path) == entry.service, "native host/path recognition")
            check(BrowserAppCatalog.service(for: "https://" + entry.host + ".attacker.test" + entry.path) == nil, "host suffix spoof rejected")
            let service = IntegrationID(rawValue: entry.service)!
            let url = BrowserIntegrationRoute.url(for: .requestConnection, service: service)!
            check(BrowserIntegrationRoute.parse(url)?.service == service, "mixed-case provider route roundtrips")
        }
        for raw in ["http://mail.google.com/", "https://user:password@mail.google.com/", "https://mail.google.com:444/", "https://evil.test/?url=https://mail.google.com/", "https://mail.google.com\\@evil.test/"] {
            check(BrowserAppCatalog.service(for: raw) == nil, "unsafe input rejected")
        }
        print("Native app catalog: \(count) passed; \(ids.count) available integrations covered")
    }
}
