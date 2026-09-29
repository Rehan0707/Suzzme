import Foundation
import CryptoKit

actor ProactiveIntelligenceEngine {
    private let store: ProactiveIntelligenceStore
    private let information: InformationEngine?
    private let memoryStore: LongTermMemoryStore?
    private let contextEngine: ContextEngine
    private let privacy: PrivacyEngine
    private var preparationRevision: UInt64 = 0

    init(
        store: ProactiveIntelligenceStore,
        information: InformationEngine? = nil,
        memoryStore: LongTermMemoryStore? = nil,
        contextEngine: ContextEngine = ContextEngine(),
        privacy: PrivacyEngine = PrivacyEngine()
    ) {
        self.store = store
        self.information = information
        self.memoryStore = memoryStore
        self.contextEngine = contextEngine
        self.privacy = privacy
    }

    func preferences() async throws -> ProactivePreferences {
        try await store.preferences()
    }

    func updatePreferences(_ value: ProactivePreferences) async throws {
        try await store.updatePreferences(value)
    }

    func applySettings(_ plan: SuzzmeSettingsPlan, authorization: SuzzmeSettingsAuthorization) async throws {
        try await store.applySettings(plan, authorization: authorization)
    }

    func cancel() async {
        preparationRevision &+= 1
        await store.cancelGeneration()
    }

    func current(now: Date = .now) async throws -> ProactiveSnapshot {
        try await store.current(now: now)
    }

    func prepare(
        from sources: [any ContextSource],
        now: Date = .now,
        calendar: Calendar = .current,
        profileName: String? = nil
    ) async throws -> ProactiveSnapshot {
        preparationRevision &+= 1
        let owner = preparationRevision
        async let informationResult = informationInput(now: now)
        async let liveResult = liveInput(from: sources, now: now, calendar: calendar)
        async let memoryResult = memoryInput(now: now)
        let (informationValues, liveValues, memories) = try await (informationResult, liveResult, memoryResult)
        try Task.checkCancellation()
        guard owner == preparationRevision else { throw CancellationError() }
        let input = ProactiveInput(
            candidates: informationValues.candidates + liveValues.candidates,
            memories: memories,
            healthLimitations: informationValues.limitations + liveValues.limitations,
            generatedAt: now
        )
        return try await prepare(input: input, now: now, calendar: calendar, profileName: profileName)
    }

    func prepare(input: ProactiveInput, now: Date? = nil, calendar: Calendar = .current, profileName: String? = nil) async throws -> ProactiveSnapshot {
        preparationRevision &+= 1
        let owner = preparationRevision
        let reference = now ?? input.generatedAt
        let (generation, preferences) = try await store.beginGeneration()
        guard owner == preparationRevision else { throw CancellationError() }
        guard preferences.dailyBriefingEnabled || preferences.timeCriticalEnabled || preferences.preparedAssistanceEnabled else {
            await store.cancelGeneration()
            throw ProactiveError.disabled
        }
        try Task.checkCancellation()
        let nextBriefing = Self.nextBriefing(after: reference, preferences: preferences, calendar: calendar)
        let candidates = Self.consolidate(input.candidates, privacy: privacy, now: reference)
        var evaluated: [(ProactiveCandidate, RelevanceDecision, TemporalUsefulness, ProactiveDeliveryClassification)] = []
        for candidate in candidates {
            let relevance = Self.relevance(for: candidate, memories: input.memories, now: reference)
            let temporal = Self.temporalUsefulness(for: candidate, now: reference, nextBriefing: nextBriefing)
            let delivery = try await classification(
                candidate: candidate,
                relevance: relevance,
                temporal: temporal,
                preferences: preferences,
                now: reference
            )
            evaluated.append((candidate, relevance, temporal, delivery))
        }
        try Task.checkCancellation()
        let briefing = preferences.dailyBriefingEnabled
            ? Self.makeBriefing(from: evaluated, input: input, now: reference, nextBriefing: nextBriefing, profileName: profileName)
            : nil
        let opportunities = Self.makeOpportunities(
            from: evaluated,
            memories: input.memories,
            preferences: preferences,
            now: reference
        )
        let timeCritical = briefing?.items.filter { $0.delivery == .timeCritical } ?? []
        let dailyContext = Self.makeDailyContext(
            from: evaluated,
            limitations: input.healthLimitations,
            now: reference,
            calendar: calendar
        )
        let snapshot = ProactiveSnapshot(
            generatedAt: reference,
            briefing: briefing,
            opportunities: opportunities,
            timeCriticalItems: timeCritical,
            dailyContext: dailyContext
        )
        try Task.checkCancellation()
        guard owner == preparationRevision else { throw CancellationError() }
        try await store.commit(snapshot, generation: generation, now: reference)
        let current = try await store.current(now: reference)
        guard owner == preparationRevision else { throw CancellationError() }
        return current
    }

    func dismissOpportunity(id: UUID) async throws {
        try await store.dismissOpportunity(id: id)
    }

    func markDelivered(candidateID: String, at date: Date = .now) async throws {
        try await store.markDelivered(key: candidateID, at: date)
    }

    func markBriefingDelivered(id: UUID, partial: Bool) async throws {
        try await store.markBriefingDelivered(id: id, partial: partial)
    }

    func reset() async throws {
        preparationRevision &+= 1
        try await store.reset()
    }

    func clearProactiveContent() async throws {
        preparationRevision &+= 1
        try await store.clearProactiveContent()
    }

    private func informationInput(now: Date) async throws -> (candidates: [ProactiveCandidate], limitations: [ProactiveHealthLimitation]) {
        guard let information else { return ([], []) }
        let events: [InformationEvent]
        let health: [InformationHealth]
        do {
            events = try await information.retrieve(.init(limit: ProactiveLimits.informationCandidates), now: now)
            health = try await information.health(now: now)
        } catch {
            return ([], [.init(source: "information", message: "Recent source information could not be checked. This summary may be incomplete.")])
        }
        let healthy = Dictionary(uniqueKeysWithValues: health.map { ($0.source, $0.state == .healthy) })
        let candidates = events.prefix(ProactiveLimits.informationCandidates).map {
            Self.candidate(from: $0, sourceHealthy: healthy[$0.source] == true, now: now)
        }
        let limitations = health.compactMap { value -> ProactiveHealthLimitation? in
            guard value.enabled, value.state != .healthy else { return nil }
            return .init(source: value.source.rawValue, message: "I couldn’t check your \(value.source.title.lowercased()), so this briefing may be incomplete.")
        }
        return (candidates, limitations)
    }

    private func liveInput(from sources: [any ContextSource], now: Date, calendar: Calendar) async throws -> (candidates: [ProactiveCandidate], limitations: [ProactiveHealthLimitation]) {
        guard !sources.isEmpty else { return ([], []) }
        let startOfToday = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? now.addingTimeInterval(-7 * 86_400)
        let end = calendar.date(byAdding: .day, value: 2, to: startOfToday) ?? now.addingTimeInterval(2 * 86_400)
        let query = SuzzmeContextQuery(sources: [.calendar, .reminders], dateRange: DateInterval(start: start, end: end), limit: ProactiveLimits.liveContextCandidates)
        let result = try await contextEngine.collectWithHealth(from: sources, request: .init(referenceDate: now, query: query))
        let limitations = result.unavailableSources.map { id in
            ProactiveHealthLimitation(source: id, message: "A live source could not be checked. This summary may be incomplete.")
        }
        return (result.items.prefix(ProactiveLimits.liveContextCandidates).map { Self.candidate(from: $0, now: now) }, limitations)
    }

    private func memoryInput(now: Date) async throws -> [SuzzmeMemoryRecord] {
        guard let memoryStore else { return [] }
        return Array(try await memoryStore.memories(limit: ProactiveLimits.memoryEvidence, now: now).prefix(ProactiveLimits.memoryEvidence))
    }

    private func classification(
        candidate: ProactiveCandidate,
        relevance: RelevanceDecision,
        temporal: TemporalUsefulness,
        preferences: ProactivePreferences,
        now: Date
    ) async throws -> ProactiveDeliveryClassification {
        guard relevance.relevance != .irrelevant,
              candidate.sourceHealthy,
              !candidate.isCompleted,
              candidate.freshness == .current || candidate.freshness == .future,
              temporal != .obsolete else { return .ignore }
        let materiallyTimeSensitive = [.deadline, .reminder, .scheduleChange, .cancellation].contains(candidate.kind)
        let deliveryAvailable = try await store.canDeliver(key: candidate.id, now: now)
        let mayInterrupt = preferences.timeCriticalEnabled
            && materiallyTimeSensitive
            && relevance.evidence.count >= 2
            && (temporal == .immediate || temporal == .beforeNextBriefing)
            && deliveryAvailable
        return mayInterrupt ? .timeCritical : .brief
    }

    static func nextBriefing(after now: Date, preferences: ProactivePreferences, calendar base: Calendar = .current) -> Date {
        let preferences = preferences.validated()
        var calendar = base
        calendar.timeZone = TimeZone(identifier: preferences.timeZoneIdentifier) ?? base.timeZone
        let components = DateComponents(hour: preferences.briefingHour, minute: preferences.briefingMinute)
        return calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? now.addingTimeInterval(86_400)
    }

    static func makeDailyContext(
        from evaluated: [(ProactiveCandidate, RelevanceDecision, TemporalUsefulness, ProactiveDeliveryClassification)],
        limitations: [ProactiveHealthLimitation],
        now: Date,
        calendar: Calendar
    ) -> DailyContextSnapshot {
        let day = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        let entries = evaluated
            .filter { candidate, relevance, temporal, _ in
                guard candidate.freshness != .expired else { return false }
                let effective = candidate.effectiveAt ?? now
                let withinToday = effective >= day && effective < end
                if candidate.isCompleted { return withinToday }
                guard temporal != .obsolete else { return false }
                let futureCommitment = effective >= end && [.deadline, .reminder, .commitment, .schedule].contains(candidate.kind)
                return withinToday || futureCommitment || relevance.relevance != .irrelevant
            }
            .sorted { lhs, rhs in
                func priority(_ candidate: ProactiveCandidate) -> Int {
                    if candidate.kind == .cancellation { return 0 }
                    if candidate.kind == .scheduleChange { return 1 }
                    if [.deadline, .reminder, .commitment].contains(candidate.kind) { return 2 }
                    if candidate.isCompleted { return 3 }
                    return candidate.kind == .schedule ? 4 : 5
                }
                let leftPriority = priority(lhs.0), rightPriority = priority(rhs.0)
                if leftPriority != rightPriority { return leftPriority < rightPriority }
                let left = lhs.0.effectiveAt ?? .distantFuture
                let right = rhs.0.effectiveAt ?? .distantFuture
                if left != right { return left < right }
                return lhs.0.id < rhs.0.id
            }
            .prefix(ProactiveLimits.dailyContextItems)
            .map { candidate, relevance, _, _ in
                let state: DailyContextEntryState = if candidate.isCompleted { .completed }
                else if candidate.kind == .cancellation { .cancelled }
                else if candidate.freshness == .superseded { .superseded }
                else if candidate.kind == .scheduleChange { .corrected }
                else { .active }
                return DailyContextEntry(
                    id: candidate.id,
                    kind: candidate.kind,
                    title: candidate.title,
                    summary: candidate.summary,
                    source: candidate.source,
                    sourceReference: candidate.sourceReference,
                    effectiveAt: candidate.effectiveAt,
                    effectiveUntil: candidate.effectiveUntil,
                    entities: Array(candidate.entities.prefix(5)),
                    sensitivity: candidate.sensitivity,
                    freshness: candidate.freshness,
                    state: state,
                    confidence: candidate.confidence,
                    mayBeDurableCandidate: relevance.relevance == .strong
                        && candidate.confidence >= 0.8
                        && candidate.sensitivity != .restricted
                        && [.commitment, .deadline].contains(candidate.kind)
                )
            }
        return .init(
            localDay: day,
            generatedAt: now,
            entries: Array(entries),
            sourceLimitations: Array(limitations.prefix(ProactiveLimits.dailyContextLimitations).map(\.message)),
            timeZoneIdentifier: calendar.timeZone.identifier
        )
    }

    static func relevance(for candidate: ProactiveCandidate, memories: [SuzzmeMemoryRecord], now: Date) -> RelevanceDecision {
        var evidence: [RelevanceEvidence] = []
        func add(_ kind: RelevanceEvidenceKind, _ explanation: String, _ reference: String) {
            guard evidence.count < ProactiveLimits.evidencePerItem,
                  !evidence.contains(where: { $0.kind == kind && $0.reference == reference }) else { return }
            evidence.append(.init(id: "\(kind.rawValue):\(reference)", kind: kind, explanation: explanation, reference: reference))
        }
        if candidate.sourceHealthy { add(.sourceReliability, "It comes from a source Suzzme could check.", candidate.source) }
        switch candidate.kind {
        case .schedule, .scheduleChange, .cancellation:
            add(.schedule, "It affects your current schedule.", candidate.sourceReference)
        case .reminder, .deadline:
            add(.reminder, "It is tied to an unfinished commitment.", candidate.sourceReference)
        case .commitment:
            add(.commitment, "It matches a commitment you asked Suzzme to remember.", candidate.sourceReference)
        case .information:
            break
        }
        if let date = candidate.effectiveAt, date >= now, date.timeIntervalSince(now) <= 48 * 3_600 {
            add(.temporal, "Its timing makes it useful soon.", candidate.sourceReference)
        }
        let candidateTerms = Self.terms([candidate.title, candidate.summary] + candidate.entities)
        for memory in memories.prefix(ProactiveLimits.memoryEvidence) {
            let memoryTerms = Self.terms([memory.name, memory.detail])
            guard !candidateTerms.intersection(memoryTerms).isEmpty else { continue }
            let kind: RelevanceEvidenceKind = switch memory.type {
            case .preference: .explicitPreference
            case .project: .project
            case .commitment, .task: .commitment
            case .person, .organization: .person
            default: .commitment
            }
            let explanation: String = switch kind {
            case .explicitPreference: "It matches an explicit preference."
            case .project: "It relates to an active project."
            case .commitment: "It relates to something you committed to."
            case .person: "It involves someone or a group already in your context."
            default: "It has supporting context."
            }
            add(kind, explanation, memory.id.uuidString)
        }
        let relevance: PersonalRelevance = evidence.count >= 3 ? .strong : evidence.count >= 2 ? .useful : .irrelevant
        return .init(candidateID: candidate.id, relevance: relevance, evidence: evidence)
    }

    static func temporalUsefulness(for candidate: ProactiveCandidate, now: Date, nextBriefing: Date) -> TemporalUsefulness {
        if candidate.freshness == .expired || candidate.freshness == .superseded || candidate.freshness == .stale || candidate.isCompleted {
            return .obsolete
        }
        if let end = candidate.effectiveUntil, end <= now { return .obsolete }
        guard let date = candidate.effectiveAt else { return .canWait }
        if date < now.addingTimeInterval(-30 * 60) {
            // An unfinished due item remains useful after its due time. Past
            // calendar events age out, while overdue work stays actionable.
            if [.reminder, .commitment].contains(candidate.kind), !candidate.isCompleted {
                return .immediate
            }
            return .obsolete
        }
        let interval = date.timeIntervalSince(now)
        if interval <= 3 * 3_600 { return .immediate }
        if date < nextBriefing, interval <= 12 * 3_600 { return .beforeNextBriefing }
        return .canWait
    }

    private static func consolidate(_ values: [ProactiveCandidate], privacy: PrivacyEngine, now: Date) -> [ProactiveCandidate] {
        var result: [String: ProactiveCandidate] = [:]
        for candidate in values.prefix(ProactiveLimits.informationCandidates + ProactiveLimits.liveContextCandidates) {
            guard candidate.sensitivity != .restricted,
                  privacy.classify(([candidate.title, candidate.summary, candidate.sourceReference] + candidate.entities).joined(separator: " ")).policy != .neverProcess,
                  candidate.confidence >= 0.5 else { continue }
            let key = candidate.source + ":" + candidate.sourceReference
            if let prior = result[key] {
                let priorDate = prior.effectiveAt ?? .distantPast
                let newDate = candidate.effectiveAt ?? .distantPast
                if newDate >= priorDate { result[key] = candidate }
            } else {
                result[key] = candidate
            }
        }
        return result.values.sorted {
            ($0.effectiveAt ?? .distantFuture, $0.title) < ($1.effectiveAt ?? .distantFuture, $1.title)
        }
    }

    private static func makeBriefing(
        from values: [(ProactiveCandidate, RelevanceDecision, TemporalUsefulness, ProactiveDeliveryClassification)],
        input: ProactiveInput,
        now: Date,
        nextBriefing: Date,
        profileName: String?
    ) -> ProactiveBriefing? {
        let selected = values.filter { $0.3 != .ignore }.prefix(ProactiveLimits.briefingItems)
        let items = selected.map { candidate, relevance, _, delivery in
            ProactiveBriefingItem(
                id: stableUUID(candidate.id),
                candidateID: candidate.id,
                kind: candidate.kind,
                summary: String(candidate.summary.prefix(240)),
                whyRelevant: String(relevance.explanation.prefix(300)),
                effectiveTime: candidate.effectiveAt,
                sourceEvidence: Array(relevance.evidence.map(\.reference).prefix(ProactiveLimits.evidencePerItem)),
                relatedEntities: Array(candidate.entities.prefix(5)),
                freshness: candidate.freshness,
                confidence: candidate.confidence,
                sensitivity: candidate.sensitivity,
                delivery: delivery
            )
        }
        let limitations = input.healthLimitations.map(\.message)
        guard !items.isEmpty || !limitations.isEmpty else { return nil }
        var buckets: [ProactiveBriefingSectionKind: [ProactiveBriefingItem]] = [:]
        for item in items {
            let section: ProactiveBriefingSectionKind
            if item.delivery == .timeCritical || item.kind == .deadline || item.kind == .reminder { section = .needsAttention }
            else if [.scheduleChange, .cancellation].contains(item.kind) { section = .changes }
            else if let date = item.effectiveTime, date <= now.addingTimeInterval(24 * 3_600) { section = .today }
            else { section = .later }
            buckets[section, default: []].append(item)
        }
        let sections = ProactiveBriefingSectionKind.allCases.compactMap { kind -> ProactiveBriefingSection? in
            guard kind != .opening, let values = buckets[kind], !values.isEmpty else { return nil }
            return .init(kind: kind, items: values)
        }
        let narration = makeNarration(items: items, limitations: limitations, now: now, profileName: profileName)
        let sources = Array(Set(selected.map { $0.0.source })).sorted()
        let live = Array(Set(selected.filter { $0.0.source == "calendar" || $0.0.source == "reminders" }.map { $0.0.sourceReference })).prefix(8).map { $0 }
        let memory = Array(Set(selected.flatMap { $0.1.evidence.filter { [.project, .commitment, .person, .explicitPreference].contains($0.kind) }.map(\.reference) })).prefix(ProactiveLimits.memoryEvidence).map { $0 }
        return .init(
            id: UUID(), createdAt: now,
            coverageWindow: .init(start: now, end: max(nextBriefing, now.addingTimeInterval(24 * 3_600))),
            informationCutoff: input.generatedAt,
            sections: sections,
            sourceEvidence: sources,
            liveContextEvidence: live,
            memoryEvidence: memory,
            healthLimitations: limitations,
            narration: narration,
            deliveryState: limitations.isEmpty ? .ready : .partiallyDelivered
        )
    }

    private static func makeNarration(items: [ProactiveBriefingItem], limitations: [String], now: Date, profileName: String?) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        let greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let name = profileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let opening = name.isEmpty ? "\(greeting)." : "\(greeting), \(name)."
        var parts = [opening]
        if items.isEmpty {
            parts.append(limitations.isEmpty
                ? "There isn’t anything new that needs your attention."
                : "I couldn’t confirm everything in your day because a source was unavailable.")
        } else {
            let formatter = DateFormatter(); formatter.dateStyle = .none; formatter.timeStyle = .short
            parts.append(contentsOf: items.prefix(5).map { item in
                guard let time = item.effectiveTime else { return item.summary }
                switch item.kind {
                case .schedule, .scheduleChange:
                    return "At \(formatter.string(from: time)), \(item.summary)"
                case .deadline, .reminder, .commitment:
                    return "By \(formatter.string(from: time)), \(item.summary)"
                case .cancellation, .information:
                    return item.summary
                }
            })
        }
        if let limitation = limitations.first { parts.append(limitation) }
        return String(parts.joined(separator: " ").prefix(ProactiveLimits.narrationCharacters))
    }

    private static func makeOpportunities(
        from values: [(ProactiveCandidate, RelevanceDecision, TemporalUsefulness, ProactiveDeliveryClassification)],
        memories: [SuzzmeMemoryRecord],
        preferences: ProactivePreferences,
        now: Date
    ) -> [SuzzmeOpportunity] {
        var opportunities: [SuzzmeOpportunity] = []
        let useful = values.filter { $0.1.relevance == .strong && $0.2 != .obsolete && $0.3 != .ignore }
        for (candidate, relevance, temporal, _) in useful {
            guard opportunities.count < ProactiveLimits.opportunities else { break }
            let kind: SuzzmeOpportunityKind?
            if [.deadline, .reminder].contains(candidate.kind), temporal == .immediate || temporal == .beforeNextBriefing { kind = .deadline }
            else if [.scheduleChange, .cancellation].contains(candidate.kind) { kind = .meaningfulChange }
            else { kind = nil }
            guard let kind else { continue }
            let expiry = max(now.addingTimeInterval(30 * 60), candidate.effectiveUntil ?? candidate.effectiveAt ?? now.addingTimeInterval(24 * 3_600))
            let capability: ProactiveCapabilityPreview = [.deadline, .reminder].contains(candidate.kind) ? .reminders : .calendar
            let proposal = preferences.preparedAssistanceEnabled ? PreparedAssistanceProposal(
                id: stableUUID(candidate.id + ":proposal"),
                summary: "Suzzme can help you review a possible change.",
                suggestedRequest: "Help me review \(candidate.title)",
                requiredCapabilities: [capability],
                risk: .reviewOnly,
                expiresAt: expiry
            ) : nil
            opportunities.append(.init(
                id: stableUUID(candidate.id + ":opportunity"), key: candidate.id, kind: kind,
                createdAt: now, expiresAt: expiry,
                summary: candidate.summary, reason: relevance.explanation,
                supportingInformation: candidate.source == "information" ? [candidate.sourceReference] : [],
                supportingMemory: Array(relevance.evidence.filter { [.project, .commitment, .person, .explicitPreference].contains($0.kind) }.map(\.reference).prefix(ProactiveLimits.memoryEvidence)),
                supportingLiveContext: candidate.source == "calendar" || candidate.source == "reminders" ? [candidate.sourceReference] : [],
                possibleAssistance: proposal, requiredCapabilities: [capability], riskPreview: .reviewOnly,
                freshness: candidate.freshness, confidence: candidate.confidence, state: .active
            ))
        }
        let schedule = useful.map(\.0).filter { $0.kind == .schedule || $0.kind == .scheduleChange }
        for firstIndex in schedule.indices {
            for secondIndex in schedule.indices where secondIndex > firstIndex {
                guard opportunities.count < ProactiveLimits.opportunities,
                      overlaps(schedule[firstIndex], schedule[secondIndex]) else { continue }
                let first = schedule[firstIndex], second = schedule[secondIndex]
                let key = [first.id, second.id].sorted().joined(separator: ":")
                let expiry = min(first.effectiveUntil ?? first.effectiveAt ?? now.addingTimeInterval(3_600), second.effectiveUntil ?? second.effectiveAt ?? now.addingTimeInterval(3_600))
                let proposal = preferences.preparedAssistanceEnabled ? PreparedAssistanceProposal(
                    id: stableUUID(key + ":proposal"), summary: "Suzzme can help you review this overlap.",
                    suggestedRequest: "Help me resolve the conflict between \(first.title) and \(second.title)",
                    requiredCapabilities: [.calendar], risk: .reviewOnly, expiresAt: expiry
                ) : nil
                opportunities.append(.init(
                    id: stableUUID(key), key: key, kind: .conflict, createdAt: now, expiresAt: expiry,
                    summary: "\(first.title) overlaps \(second.title).",
                    reason: "Both are present in your current schedule.", supportingInformation: [], supportingMemory: [],
                    supportingLiveContext: [first.sourceReference, second.sourceReference], possibleAssistance: proposal,
                    requiredCapabilities: [.calendar], riskPreview: .reviewOnly, freshness: .current,
                    confidence: min(first.confidence, second.confidence), state: .active
                ))
            }
        }
        return Array(opportunities.prefix(ProactiveLimits.opportunities))
    }

    private static func overlaps(_ lhs: ProactiveCandidate, _ rhs: ProactiveCandidate) -> Bool {
        guard let lhsStart = lhs.effectiveAt, let rhsStart = rhs.effectiveAt else { return false }
        let lhsEnd = lhs.effectiveUntil ?? lhsStart.addingTimeInterval(3_600)
        let rhsEnd = rhs.effectiveUntil ?? rhsStart.addingTimeInterval(3_600)
        return lhsStart < rhsEnd && rhsStart < lhsEnd
    }

    private static func terms(_ values: [String]) -> Set<String> {
        let ignored: Set<String> = ["the", "and", "for", "with", "your", "this", "that", "from", "into", "meeting", "reminder"]
        return Set(values.joined(separator: " ").lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 && !ignored.contains($0) })
    }

    private static func candidate(from event: InformationEvent, sourceHealthy: Bool, now: Date) -> ProactiveCandidate {
        let kind: ProactiveCandidateKind = switch event.kind {
        case .scheduleChange, .locationChange: .scheduleChange
        case .cancellation: .cancellation
        case .reminderChange: .reminder
        case .eventUpdate: .schedule
        case .generalUpdate: .information
        }
        let freshness: ProactiveCandidateFreshness = switch event.freshness(at: now) {
        case .current: .current
        case .future: .future
        case .stale: .stale
        case .expired: .expired
        case .superseded: .superseded
        }
        return .init(
            id: event.fingerprint, kind: kind, title: event.title, summary: event.summary,
            source: event.source.rawValue, sourceReference: event.externalID,
            effectiveAt: event.effectiveAt, effectiveUntil: event.effectiveUntil, entities: event.entities,
            sensitivity: event.sensitivity, freshness: freshness,
            // A cancellation is a meaningful current change. Treating it as completed
            // would suppress the exact last-minute disruption Step 10 must surface.
            isCompleted: event.objectState == .completed || event.objectState == .absent,
            sourceHealthy: sourceHealthy, confidence: 1
        )
    }

    private static func candidate(from item: SuzzmeContextItem, now: Date) -> ProactiveCandidate {
        let source = item.metadata["source"] ?? (item.intent == .event ? "calendar" : item.intent == .reminder ? "reminders" : item.sourceIdentifier)
        let effectiveAt = date(item.metadata[item.intent == .event ? "start" : "due"]) ?? item.expiration
        let effectiveUntil = date(item.metadata["end"])
        let kind: ProactiveCandidateKind = switch item.intent {
        case .event: .schedule
        case .reminder, .task: .reminder
        case .deadline: .deadline
        default: .information
        }
        let completed = item.metadata["completed"] == "true"
        let reference = item.metadata["fingerprint"] ?? item.sourceIdentifier
        return .init(
            id: source + ":" + reference, kind: kind,
            title: item.metadata["title"].flatMap { $0.isEmpty ? nil : $0 } ?? item.content,
            summary: item.content, source: source, sourceReference: item.sourceIdentifier,
            effectiveAt: effectiveAt, effectiveUntil: effectiveUntil, entities: item.entities,
            sensitivity: item.sensitivity,
            freshness: item.expiration.map { $0 <= now ? .expired : .current } ?? .current,
            isCompleted: completed, sourceHealthy: true, confidence: item.confidence
        )
    }

    private static func date(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func stableUUID(_ value: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        let tuple: uuid_t = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: tuple)
    }
}
