import Foundation

enum SuzzmeContextIntent: String, Codable, Sendable, CaseIterable {
    case information, event, task, deadline, reminder, question, action
}

enum SuzzmeContextSensitivity: String, Codable, Sendable, CaseIterable, Comparable {
    case `public`, personal, sensitive, restricted
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
    private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

enum SuzzmeContextDisposition: String, Codable, Sendable { case temporary, memoryCandidate, discard }

struct SuzzmeContextItem: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let sourceIdentifier: String
    let content: String
    let timestamp: Date
    let entities: [String]
    let intent: SuzzmeContextIntent
    let importance: SuzzmeItem.Priority
    let sensitivity: SuzzmeContextSensitivity
    let metadata: [String: String]
    let expiration: Date?
    let confidence: Double

    init(id: UUID = UUID(), sourceIdentifier: String, content: String, timestamp: Date = .now,
         entities: [String] = [], intent: SuzzmeContextIntent = .information,
         importance: SuzzmeItem.Priority = .normal,
         sensitivity: SuzzmeContextSensitivity = .personal,
         metadata: [String: String] = [:], expiration: Date? = nil, confidence: Double = 1) {
        self.id = id; self.sourceIdentifier = sourceIdentifier; self.content = content
        self.timestamp = timestamp; self.entities = entities; self.intent = intent
        self.importance = importance; self.sensitivity = sensitivity; self.metadata = metadata
        self.expiration = expiration; self.confidence = confidence
    }

    var isExpired: Bool { expiration.map { $0 <= .now } ?? false }
}

struct SuzzmeContextRequest: Sendable {
    let referenceDate: Date
    let query: SuzzmeContextQuery
    var limit: Int { query.limit }
    init(referenceDate: Date = .now, query: SuzzmeContextQuery = .init()) {
        self.referenceDate = referenceDate; self.query = query
    }
}

protocol ContextSource: Sendable {
    var identifier: String { get }
    func fetchContext(for request: SuzzmeContextRequest) async throws -> [SuzzmeContextItem]
}

enum SuzzmeContextError: LocalizedError, Sendable {
    case sourceUnavailable(String), cancelled
    var errorDescription: String? {
        switch self { case .sourceUnavailable: "That context source is not available right now."; case .cancelled: "Context collection was cancelled." }
    }
}

/// Adapter for existing local Suzzme items. Future native connectors conform to
/// `ContextSource`; they do not need special cases in the intelligence layer.
struct SuzzmeItemContextSource: ContextSource {
    let identifier = "suzzme-items"
    let items: [SuzzmeItem]
    func fetchContext(for request: SuzzmeContextRequest) async throws -> [SuzzmeContextItem] {
        try Task.checkCancellation()
        return items.prefix(request.limit).map { item in
            SuzzmeContextItem(sourceIdentifier: item.source.rawValue, content: "\(item.title). \(item.summary)", timestamp: item.createdAt, entities: [item.title], intent: Self.intent(for: item.category), importance: item.priority, sensitivity: .personal, metadata: ["itemID": item.id.uuidString], expiration: item.dueDate, confidence: item.confidence)
        }
    }
    private static func intent(for category: SuzzmeItem.Category) -> SuzzmeContextIntent {
        switch category { case .event: .event; case .task: .task; case .deadline: .deadline; case .reminder: .reminder; default: .information }
    }
}
