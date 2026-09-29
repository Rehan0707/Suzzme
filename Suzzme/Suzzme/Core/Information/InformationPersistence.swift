import SwiftData

/// A separate local store leaves the validated Steps 1–8 schema untouched.
/// Opening failure is surfaced; no destructive reset or in-memory substitution.
enum InformationPersistence {
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([StoredInformationEvent.self, StoredInformationSource.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration("SuzzmeInformation", schema: schema, cloudKitDatabase: .none)
        ])
    }
}
