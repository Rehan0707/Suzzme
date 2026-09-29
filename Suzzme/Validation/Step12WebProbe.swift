import Foundation

/// Opt-in public-page smoke probe. No personal data or HTML is saved.
@main struct Step12WebProbe {
    static func main() async {
        for address in ["https://www.w3.org/TR/html401/struct/tables.html", "https://registrar.mit.edu/calendar", "https://www.cambridgestudents.cam.ac.uk/term-dates-and-calendars"] {
            let start = ContinuousClock.now
            do {
                let response = try await BoundedWatchedLinkFetcher().fetch(.init(url: URL(string: address)!, etag: nil, lastModified: nil))
                let result = try WebContentExtractor.extract(data: response.data, mimeType: response.mimeType, now: .now)
                print("PUBLIC PAGE \(address): HTTP \(response.statusCode), \(response.data.count) bytes, \(result.changes.count) sections, \(start.duration(to: .now))")
                let repeated = try await BoundedWatchedLinkFetcher().fetch(.init(url: URL(string: address)!, etag: response.etag, lastModified: response.lastModified))
                print("CONDITIONAL REFRESH: HTTP \(repeated.statusCode), \(repeated.data.count) bytes")
            } catch {
                print("PUBLIC PAGE \(address): safely unavailable (\(String(describing: type(of: error)))), \(start.duration(to: .now))")
            }
        }
    }
}
