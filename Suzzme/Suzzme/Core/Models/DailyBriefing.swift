import Foundation

struct DailyBriefing: Codable, Sendable {
    var date: Date
    var greeting: String
    var summary: String
    var importantItems: [SuzzmeItem]
    var upcomingItems: [SuzzmeItem]
    var carriedOverItems: [SuzzmeItem]
    var completedItems: [SuzzmeItem]

    var attentionCount: Int {
        Set((importantItems + upcomingItems + carriedOverItems).map(\.id)).count
    }
}
