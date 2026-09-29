import Foundation

/// Owns pending approval and exactly-once execution. It does not parse text,
/// render UI, or own EventKit; it simply gates structured plans to capabilities.
actor SuzzmeActionExecutionCoordinator {
    private let registry: SuzzmeCapabilityRegistry
    private let now: @Sendable () -> Date
    private var pending: SuzzmeActionPlan?
    private var activeRequestID: UUID?
    private var retiredRequests: Set<UUID> = []
    private var executed: Set<UUID> = []
    private var committing: SuzzmeActionPlan?
    private var commitConsumed = false
    private var proposalRevision = 0
    private var evidence: [SuzzmeActionEvidence] = []

    init(registry: SuzzmeCapabilityRegistry, now: @escaping @Sendable () -> Date = { .now }) {
        self.registry = registry
        self.now = now
    }

    func begin(requestID: UUID) {
        guard !retiredRequests.contains(requestID), retiredRequests.count < 2048 else { return }
        if activeRequestID != requestID {
            if let previous = activeRequestID { retiredRequests.insert(previous) }
            pending = nil; proposalRevision += 1
        }
        activeRequestID = requestID
    }

    func authorizeCommit(_ plan: SuzzmeActionPlan) throws {
        try Task.checkCancellation()
        guard activeRequestID == plan.requestID, committing == plan, !commitConsumed else { throw SuzzmeCapabilityError.staleRequest }
        try SuzzmeActionPolicy.validate(plan)
        try validateAge(plan)
        commitConsumed = true
    }
    func cancel(requestID: UUID) {
        guard activeRequestID == requestID || pending?.requestID == requestID else { return }
        proposalRevision += 1
        if activeRequestID == requestID { activeRequestID = nil; retiredRequests.insert(requestID) }
        if pending?.requestID == requestID { pending = nil }
    }

    func propose(_ plan: SuzzmeActionPlan) async throws -> SuzzmeActionPlan {
        guard activeRequestID == plan.requestID else { throw SuzzmeCapabilityError.staleRequest }
        try SuzzmeActionPolicy.validate(plan)
        try validateAge(plan)
        guard executed.count < 512, !executed.contains(plan.id) else { throw SuzzmeCapabilityError.limitExceeded }
        proposalRevision += 1
        let revision = proposalRevision
        pending = nil
        guard await registry.availability(for: plan.capability) != .unavailable else { throw SuzzmeCapabilityError.unsupported }
        let resolved = try await registry.resolve(plan)
        guard activeRequestID == plan.requestID, revision == proposalRevision, !Task.isCancelled else { throw SuzzmeCapabilityError.staleRequest }
        try SuzzmeActionPolicy.validate(resolved)
        guard resolved.id == plan.id, resolved.requestID == plan.requestID,
              resolved.capability == plan.capability, resolved.operation == plan.operation,
              resolved.risk == plan.risk, resolved.createdAt == plan.createdAt else { throw SuzzmeCapabilityError.malformedPlan }
        pending = resolved
        return resolved
    }

    func pendingPlan() -> SuzzmeActionPlan? { pending }

    func cancelPending() -> SuzzmeActionPlan? {
        defer { pending = nil; proposalRevision += 1 }
        return pending
    }

    func confirm(actionID: UUID, requestID: UUID) async throws -> SuzzmeCapabilityResult {
        if executed.contains(actionID) { return .init(actionID: actionID, status: .duplicate, message: "That action was already handled.", evidence: nil) }
        guard let plan = pending, plan.id == actionID else { throw SuzzmeCapabilityError.staleRequest }
        guard activeRequestID == plan.requestID, requestID == plan.requestID else { throw SuzzmeCapabilityError.staleRequest }
        guard !executed.contains(plan.id) else { return .init(actionID: plan.id, status: .duplicate, message: "That action was already handled.", evidence: nil) }
        try validateAge(plan)
        // Consume before awaiting EventKit so a repeated callback cannot cross
        // the commit boundary while the first one is executing.
        pending = nil
        executed.insert(plan.id)
        let availability = await registry.availability(for: plan.capability)
        switch availability {
        case .available: break
        case .writeOnly: throw SuzzmeCapabilityError.fullAccessRequired
        case .authorizationRequired: throw SuzzmeCapabilityError.authorizationRequired
        case .denied, .restricted: throw SuzzmeCapabilityError.authorizationDenied
        case .unavailable: throw SuzzmeCapabilityError.unsupported
        }
        guard activeRequestID == plan.requestID, requestID == plan.requestID, !Task.isCancelled else { throw SuzzmeCapabilityError.staleRequest }
        committing = plan
        commitConsumed = false
        defer { if committing?.id == plan.id { committing = nil } }
        let result = try await registry.execute(plan, authorization: self)
        guard activeRequestID == plan.requestID, requestID == plan.requestID, !Task.isCancelled else { throw SuzzmeCapabilityError.staleRequest }
        if result.status == .success {
            guard committing == plan, commitConsumed, result.actionID == plan.id, let proof = result.evidence,
                  proof.actionID == plan.id, proof.requestID == plan.requestID,
                  proof.capability == plan.capability, proof.operation == plan.operation,
                  proof.verification == .verified else { throw SuzzmeCapabilityError.verificationFailed }
        }
        if let evidence = result.evidence { self.evidence.append(evidence) }
        if evidence.count > 64 { evidence.removeFirst(evidence.count - 64) }
        return result
    }

    private func validateAge(_ plan: SuzzmeActionPlan) throws {
        let age = now().timeIntervalSince(plan.createdAt)
        guard age.isFinite, age >= -5, age <= 300 else { throw SuzzmeCapabilityError.staleRequest }
    }

    func evidenceSnapshot() -> [SuzzmeActionEvidence] { evidence }
}

enum SuzzmeActionConfirmation {
    static func isAffirmative(_ text: String) -> Bool {
        ["yes", "yeah", "do it", "confirm", "go ahead"].contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func isCancellation(_ text: String) -> Bool {
        ["no", "cancel", "never mind", "don't"].contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
