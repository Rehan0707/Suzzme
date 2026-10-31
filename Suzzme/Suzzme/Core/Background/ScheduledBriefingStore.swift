import Foundation

/// The app owns one store. Synchronous main-actor transactions make the
/// durable claim and enable/disable authority indivisible before a runner starts.
@MainActor final class ScheduledBriefingStore {
    static let maximumReceipts = 32
    static let maximumAttempts = 3
    static let retryDelay: TimeInterval = 60
    private let fileURL: URL
    private let write: (Data, URL) throws -> Void
    private var state = ScheduledBriefingStoredState()
    private var loaded = false

    init(fileURL: URL = ScheduledBriefingStore.defaultURL(),
         write: @escaping (Data, URL) throws -> Void = { try RecoverableJSONFile.write($0, to: $1) }) {
        self.fileURL = fileURL
        self.write = write
    }

    static func defaultURL() -> URL {
        let manager = FileManager.default
        return (manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? manager.temporaryDirectory)
            .appendingPathComponent("Suzzme", isDirectory: true).appendingPathComponent("scheduled-briefings-v1.json")
    }

    func load(now: Date) throws -> ScheduledBriefingStoredState {
        if !loaded {
            let decoded = try RecoverableJSONFile.read(from: fileURL, validate: { _ = try Self.decode($0) })
                .map { try Self.decode($0) } ?? ScheduledBriefingStoredState()
            var recovered = decoded
            for index in recovered.receipts.indices where recovered.receipts[index].state == .running {
                recovered.receipts[index].state = .interrupted
                recovered.receipts[index].finishedAt = now
                recovered.receipts[index].retryAt = now.addingTimeInterval(Self.retryDelay)
            }
            if recovered != decoded { try persist(recovered) }
            else { state = recovered; loaded = true }
        }
        return state
    }

    func setEnabled(_ enabled: Bool, now: Date) throws -> ScheduledBriefingStoredState {
        var candidate = try load(now: now)
        candidate.enabled = enabled
        try persist(candidate)
        return state
    }

    func claim(_ slot: ScheduledBriefingSlot, now: Date) throws -> ScheduledBriefingReceipt? {
        var candidate = try load(now: now)
        guard candidate.enabled || slot.manualRequestID != nil else { return nil }
        let prior = candidate.receipts.first { $0.slot.key == slot.key }
        guard prior?.state != .completed, prior?.state != .running,
              (prior?.attempt ?? 0) < Self.maximumAttempts,
              prior?.retryAt.map({ $0 <= now }) ?? true,
              prior?.state != .failed, prior?.state != .cancelled else { return nil }
        if slot.manualRequestID == nil, prior == nil {
            let automatic = candidate.receipts.filter { $0.slot.manualRequestID == nil }
            if automatic.count >= 24 {
                // Schedule churn must not evict a completed slot that still
                // belongs to today, then let that same slot execute twice.
                guard let expired = automatic.last(where: {
                    !$0.slot.schedule.calendar.isDate($0.slot.localDay, inSameDayAs: now)
                }) else { return nil }
                candidate.receipts.removeAll { $0.id == expired.id }
            }
        }
        let receipt = ScheduledBriefingReceipt(id: UUID(), slot: slot, attempt: (prior?.attempt ?? 0) + 1,
            startedAt: now, state: .running)
        candidate.receipts.removeAll { $0.slot.key == slot.key }
        candidate.receipts.insert(receipt, at: 0)
        // Repeated manual checks must not evict the scheduled completion and
        // accidentally make the current day's automatic slot eligible again.
        let automatic = Array(candidate.receipts.filter { $0.slot.manualRequestID == nil }.prefix(24))
        let manual = Array(candidate.receipts.filter { $0.slot.manualRequestID != nil }.prefix(8))
        let retainedIDs = Set((automatic + manual).map(\.id))
        candidate.receipts = candidate.receipts.filter { retainedIDs.contains($0.id) }
        try persist(candidate)
        return receipt
    }

    @discardableResult
    func finish(id: UUID, state status: ScheduledBriefingReceiptState, now: Date,
                output: ScheduledBriefingOutput? = nil) throws -> ScheduledBriefingStoredState {
        var candidate = try load(now: now)
        guard let index = candidate.receipts.firstIndex(where: { $0.id == id && $0.state == .running }) else { return candidate }
        guard status != .running, status != .completed || ((candidate.enabled || candidate.receipts[index].slot.manualRequestID != nil) && output != nil) else {
            throw ScheduledBriefingStorageError.invalid
        }
        candidate.receipts[index].state = status == .deferred && candidate.receipts[index].attempt >= Self.maximumAttempts ? .failed : status
        candidate.receipts[index].finishedAt = now
        candidate.receipts[index].output = status == .completed ? output : nil
        candidate.receipts[index].retryAt = [.deferred, .interrupted].contains(status)
            && candidate.receipts[index].attempt < Self.maximumAttempts ? now.addingTimeInterval(Self.retryDelay) : nil
        try persist(candidate)
        return state
    }

    private func persist(_ candidate: ScheduledBriefingStoredState) throws {
        do {
            let data = try JSONEncoder().encode(candidate)
            _ = try Self.decode(data)
            try write(data, fileURL)
            state = candidate
            loaded = true
        } catch {
            // A write may have reached its atomic disk commit. Re-read before
            // any subsequent claim rather than trusting an assumed rollback.
            loaded = false
            throw error
        }
    }

    private static func decode(_ data: Data) throws -> ScheduledBriefingStoredState {
        let value = try JSONDecoder().decode(ScheduledBriefingStoredState.self, from: data)
        guard value.schemaVersion == 1, value.receipts.count <= maximumReceipts,
              Set(value.receipts.map(\.slot.key)).count == value.receipts.count,
              Set(value.receipts.map(\.id)).count == value.receipts.count else { throw ScheduledBriefingStorageError.invalid }
        for receipt in value.receipts {
            let schedule = receipt.slot.schedule
            let base = schedule.slot(on: receipt.slot.localDay)
            let expectedKey = base.key + (receipt.slot.manualRequestID.map { "|manual:" + $0.uuidString } ?? "")
            guard (0...23).contains(schedule.hour), (0...59).contains(schedule.minute),
                  TimeZone(identifier: schedule.timeZoneIdentifier) != nil,
                  receipt.slot.key == expectedKey, receipt.slot.localDay == base.localDay,
                  receipt.slot.scheduledAt == base.scheduledAt,
                  (1...maximumAttempts).contains(receipt.attempt),
                  receipt.startedAt.timeIntervalSince1970.isFinite,
                  receipt.finishedAt?.timeIntervalSince1970.isFinite ?? true,
                  receipt.retryAt?.timeIntervalSince1970.isFinite ?? true,
                  (receipt.state == .running) == (receipt.finishedAt == nil),
                  (receipt.state == .completed) == (receipt.output != nil),
                  receipt.output.map({ (0...100).contains($0.itemCount) && (0...100).contains($0.sourceCount)
                      && (0...100).contains($0.limitationCount)
                      && $0.generatedAt.timeIntervalSince1970.isFinite }) ?? true else { throw ScheduledBriefingStorageError.invalid }
        }
        return value
    }
}
