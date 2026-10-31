import Foundation
import CryptoKit

actor ProactiveIntelligenceEngine {
    private let store: ProactiveIntelligenceStore
    private let information: InformationEngine?
    private let memoryStore: LongTermMemoryStore?
    private let contextEngine: ContextEngine
    private let privacy: PrivacyEngine
    private let localBriefingSummarizer: (@Sendable (String) async throws -> String?)?
    private var preparationRevision: UInt64 = 0

    init(
        store: ProactiveIntelligenceStore,
        information: InformationEngine? = nil,
        memoryStore: LongTermMemoryStore? = nil,
        contextEngine: ContextEngine = ContextEngine(),
        privacy: PrivacyEngine = PrivacyEngine(),
        localBriefingSummarizer: (@Sendable (String) async throws -> String?)? = nil
    ) {
        self.store = store
        self.information = information
        self.memoryStore = memoryStore
        self.contextEngine = contextEngine
        self.privacy = privacy
        self.localBriefingSummarizer = localBriefingSummarizer
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

    func cancel(respectingTaskCancellation: Bool = false) async {
        guard !respectingTaskCancellation || !Task.isCancelled else { return }
        preparationRevision &+= 1
        await store.cancelGeneration(respectingTaskCancellation: respectingTaskCancellation)
    }

    func current(now: Date = .now) async throws -> ProactiveSnapshot {
        let cached = try await revalidateWatchedContent(try await store.current(now: now), now: now)
        let references = Set((cached.dailyContext?.entries ?? []).filter { ["connectedApps", "gmail", "whatsapp"].contains($0.source) }.map(\.sourceReference))
        if !references.isEmpty {
            let permitted = Set((try await information?.retrieve(.init(sources: [.connectedApps, .watchedWeb, .gmail, .whatsapp], limit: InformationLimits.records), now: now) ?? []).map(\.externalID))
            if !references.isSubset(of: permitted) {
                try await store.clearProactiveContent()
                return try await store.current(now: now)
            }
        }
        return cached
    }

    func savedBriefings(now: Date = .now) async throws -> [ProactiveBriefing] {
        let saved = try await store.savedBriefings(now: now)
        var result: [ProactiveBriefing] = []
        for briefing in saved {
            var allowed = true
            for source in [InformationSourceID.calendar, .reminders] where briefing.sourceEvidence.contains(source.rawValue) {
                if await information?.isAuthorized(source) != true { allowed = false; break }
            }
            guard allowed else { continue }
            let snapshot = ProactiveSnapshot(generatedAt: briefing.createdAt, briefing: briefing, opportunities: [], timeCriticalItems: [], dailyContext: nil)
            guard try await revalidateWatchedContent(snapshot, now: now).briefing != nil else { continue }
            let protectedItems = briefing.items.filter { item in
                !Set(item.sourceEvidence).isDisjoint(with: ["gmail", "whatsapp", "connectedApps"])
            }
            let events = try await information?.retrieveHistorical(.init(sources: [.connectedApps, .gmail, .whatsapp], limit: InformationLimits.records), asOf: briefing.createdAt, now: now) ?? []
            let permitted = Set(events.map(\.fingerprint))
            guard protectedItems.allSatisfy({ permitted.contains($0.candidateID) }) else { continue }
            result.append(briefing)
        }
        return result
    }

    private func revalidateWatchedContent(_ cached: ProactiveSnapshot, now: Date) async throws -> ProactiveSnapshot {
        func withheld() -> ProactiveSnapshot {
            // Derived content can be rebuilt. Preserve saved JSON, preferences,
            // delivery history and dismissed items; reading never resets them.
            .init(generatedAt: now, briefing: nil, opportunities: [], timeCriticalItems: [], dailyContext: nil)
        }
        if let briefing = cached.briefing {
            if briefing.sourceEvidence.contains("watchedWeb") {
                guard let references = briefing.watchedSourceReferences, !references.isEmpty else { return withheld() }
            }
            if let references = briefing.watchedSourceReferences,
               references.count > ProactiveLimits.briefingItems || !references.allSatisfy(\.isValid) { return withheld() }
        }
        // Legacy opportunities have opaque keys and no reliable source marker.
        // Withhold those artifacts until a fresh generation supplies provenance.
        let opportunities = cached.opportunities.filter { $0.watchedSourceReferences != nil }
        guard opportunities.allSatisfy({ opportunity in
            let references = opportunity.watchedSourceReferences ?? []
            return references.count <= 2 && references.allSatisfy(\.isValid)
        }) else { return withheld() }
        let contextReferences = (cached.dailyContext?.entries ?? []).filter { $0.source == "watchedWeb" }.map {
            ProactiveWatchedReference(externalID: $0.sourceReference, fingerprint: $0.id)
        }
        let references = Set((cached.briefing?.watchedSourceReferences ?? [])
            + opportunities.flatMap { $0.watchedSourceReferences ?? [] } + contextReferences)
        guard references.count <= ProactiveLimits.dailyContextItems + ProactiveLimits.briefingItems + 2 * ProactiveLimits.opportunities,
              references.allSatisfy(\.isValid) else { return withheld() }
        if !references.isEmpty {
            let events = try await information?.retrieve(.init(sources: [.watchedWeb], limit: InformationLimits.records), now: now) ?? []
            try Task.checkCancellation()
            let permitted = Set(events.map { ProactiveWatchedReference(externalID: $0.externalID, fingerprint: $0.fingerprint) })
            guard references.isSubset(of: permitted) else { return withheld() }
        }
        guard opportunities.count != cached.opportunities.count else { return cached }
        return .init(generatedAt: cached.generatedAt, briefing: cached.briefing, opportunities: opportunities,
                     timeCriticalItems: cached.timeCriticalItems, dailyContext: cached.dailyContext)
    }

    func prepare(
        from sources: [any ContextSource],
        now: Date = .now,
        calendar: Calendar = .current,
        profileName: String? = nil,
        summaryCutoff: Date? = nil
    ) async throws -> ProactiveSnapshot {
        preparationRevision &+= 1
        let owner = preparationRevision
        async let informationResult = informationInput(now: now)
        async let liveResult = liveInput(from: sources, now: now, calendar: calendar)
        async let memoryResult = memoryInput(now: now)
        let (informationValues, liveValues, memories) = try await (informationResult, liveResult, memoryResult)
        try Task.checkCancellation()
        guard owner == preparationRevision else { throw CancellationError() }
        let hasLiveReminders = sources.contains { $0.identifier == "reminders" }
            && !liveValues.limitations.contains { $0.source == "reminders" }
        // Current open-work selection is authoritative over cached reminders.
        // Keep information-only operation when live access is unavailable.
        let liveCalendarReferences = Set(liveValues.candidates.filter { $0.source == "calendar" }.map(\.sourceReference))
        let cached = informationValues.candidates.filter {
            (!hasLiveReminders || $0.source != "reminders")
                && ($0.source != "calendar" || !liveCalendarReferences.contains($0.sourceReference))
        }
        let live = liveValues.candidates.map { current in
            // Keep a reported change only when the live event still agrees with
            // it. A fresh event moved earlier must replace the old later time.
            guard current.source == "calendar",
                  let verifiedChange = informationValues.candidates.first(where: {
                      $0.source == "calendar" && $0.sourceReference == current.sourceReference
                          && $0.kind == .scheduleChange && $0.title == current.title
                          && Self.sameNativeTime($0.effectiveAt, current.effectiveAt)
                          && Self.sameNativeTime($0.effectiveUntil, current.effectiveUntil)
                          && $0.sourceHealthy && !$0.isCompleted
                          && ($0.freshness == .current || $0.freshness == .future)
                  }) else { return current }
            return verifiedChange
        }
        let input = ProactiveInput(
            candidates: cached + live,
            memories: memories,
            healthLimitations: informationValues.limitations + liveValues.limitations,
            generatedAt: now
        )
        return try await prepare(input: input, now: now, calendar: calendar, profileName: profileName, summaryCutoff: summaryCutoff)
    }

    func prepare(input: ProactiveInput, now: Date? = nil, calendar: Calendar = .current, profileName: String? = nil, summaryCutoff: Date? = nil) async throws -> ProactiveSnapshot {
        preparationRevision &+= 1
        let owner = preparationRevision
        let reference = now ?? input.generatedAt
        let cutoff = min(summaryCutoff ?? reference, reference)
        let enforceCutoff = summaryCutoff != nil
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
            let temporal = Self.temporalUsefulness(for: candidate, now: reference, nextBriefing: nextBriefing, calendar: calendar)
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
        var briefing = preferences.dailyBriefingEnabled
            ? Self.makeBriefing(from: evaluated, input: input, now: reference, nextBriefing: nextBriefing, profileName: profileName, calendar: calendar, cutoff: cutoff, enforceCutoff: enforceCutoff)
            : nil
        if let current = briefing {
            briefing = try await locallySummarized(current)
            try Task.checkCancellation()
            guard owner == preparationRevision else { throw CancellationError() }
        }
        let opportunities = Self.makeOpportunities(
            from: evaluated,
            memories: input.memories,
            preferences: preferences,
            now: reference
        )
        let timeCritical = Self.urgentItems(from: evaluated)
        let dailyContext = Self.makeDailyContext(
            from: evaluated,
            limitations: input.healthLimitations,
            now: reference,
            calendar: calendar,
            cutoff: enforceCutoff ? cutoff : nil
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
        let current = try await revalidateWatchedContent(try await store.current(now: reference), now: reference)
        guard owner == preparationRevision else { throw CancellationError() }
        return current
    }

    /// Improves only the spoken narration. The deterministic version remains
    /// the fallback, and the injected closure may return text only when a local
    /// model actually generated it.
    private func locallySummarized(_ briefing: ProactiveBriefing) async throws -> ProactiveBriefing {
        guard !briefing.items.isEmpty, let localBriefingSummarizer else { return briefing }
        let generated: String?
        do {
            generated = try await localBriefingSummarizer(briefing.narration)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return briefing
        }
        try Task.checkCancellation()
        guard let text = generated?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count <= ProactiveLimits.narrationCharacters,
              !text.contains("\0"), privacy.classify(text).policy != .neverProcess else {
            return briefing
        }
        var result = briefing
        result.narration = text
        return result
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
            guard value.enabled, value.state != .healthy || value.limited else { return nil }
            if value.state == .healthy && value.limited {
                return .init(source: value.source.rawValue, message: "Only part of your \(value.source.title.lowercased()) was checked. This summary may be incomplete.")
            }
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
        calendar: Calendar,
        cutoff: Date? = nil
    ) -> DailyContextSnapshot {
        let enforceCutoff = cutoff != nil
        let cutoff = min(cutoff ?? now, now)
        let day = calendar.startOfDay(for: cutoff)
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        let entries = evaluated
            .filter { candidate, relevance, temporal, _ in
                if !enforceCutoff {
                    guard candidate.freshness != .expired else { return false }
                    let effective = candidate.effectiveAt ?? now
                    let withinToday = effective >= day && effective < end
                    if candidate.isCompleted { return withinToday }
                    guard temporal != .obsolete else { return false }
                    return withinToday || (effective >= end && [.deadline, .reminder, .commitment, .schedule].contains(candidate.kind)) || relevance.relevance != .irrelevant
                }
                if candidate.isCompleted {
                    guard candidate.sourceUpdatedAt.map({ $0 <= cutoff }) ?? true else { return false }
                    return candidate.effectiveAt.map { $0 >= day && $0 < end && $0 <= cutoff } ?? false
                }
                guard temporal != .obsolete || (candidate.source == "calendar" && candidate.kind == .schedule) else { return false }
                return belongsToDailyBriefing(candidate, relevance: relevance, now: cutoff, calendar: calendar)
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
                        && [.commitment, .deadline].contains(candidate.kind),
                    isAllDay: candidate.isAllDay
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

    private static func belongsToDailyBriefing(_ candidate: ProactiveCandidate,
        relevance: RelevanceDecision, now: Date, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        guard let effective = candidate.effectiveAt else { return false }
        let historicalCalendar = candidate.source == "calendar" && candidate.kind == .schedule
        if let updated = candidate.sourceUpdatedAt, updated > now { return false }
        guard (candidate.freshness != .expired || historicalCalendar), candidate.sourceHealthy,
              effective >= day, effective < end, effective <= now else { return false }
        if candidate.kind == .information && effective > now { return false }
        if candidate.kind == .information && candidate.source == "gmail" {
            // This marker is produced only after the on-device model returns
            // a grounded important or urgent extraction from an allowed body.
            guard candidate.title.hasPrefix("Important email · ") else { return false }
        }
        return relevance.relevance != .irrelevant ||
            [.schedule, .scheduleChange, .cancellation, .deadline, .reminder, .commitment].contains(candidate.kind)
    }

    static func relevance(for candidate: ProactiveCandidate, memories: [SuzzmeMemoryRecord], now: Date) -> RelevanceDecision {
        var evidence: [RelevanceEvidence] = []
        func add(_ kind: RelevanceEvidenceKind, _ explanation: String, _ reference: String) {
            guard evidence.count < ProactiveLimits.evidencePerItem,
                  !evidence.contains(where: { $0.kind == kind && $0.reference == reference }) else { return }
            evidence.append(.init(id: "\(kind.rawValue):\(reference)", kind: kind, explanation: explanation, reference: reference))
        }
        if candidate.sourceHealthy { add(.sourceReliability, "It comes from a source Suzzme could check.", candidate.source) }
        if candidate.source == "connectedApps" {
            add(.explicitPreference, "You explicitly selected this resource for Daily Summary.", candidate.sourceReference)
        } else if candidate.source == "gmail" || candidate.source == "whatsapp" {
            add(.explicitPreference, "You selected this source for Daily Summary.", candidate.sourceReference)
        }
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

    static func temporalUsefulness(for candidate: ProactiveCandidate, now: Date, nextBriefing: Date,
                                   calendar: Calendar = .current) -> TemporalUsefulness {
        if candidate.freshness == .expired || candidate.freshness == .superseded || candidate.freshness == .stale || candidate.isCompleted {
            return .obsolete
        }
        if let end = candidate.effectiveUntil, end <= now { return .obsolete }
        guard let date = candidate.effectiveAt else { return .canWait }
        if date < now.addingTimeInterval(-30 * 60) {
            // A selected inbox or chat is a record of today's activity, even
            // when its message arrived hours before the summary runs.
            if candidate.kind == .information, ["gmail", "whatsapp"].contains(candidate.source),
               calendar.isDate(date, inSameDayAs: now) { return .canWait }
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

    private static func urgentItems(from values: [(ProactiveCandidate, RelevanceDecision, TemporalUsefulness, ProactiveDeliveryClassification)]) -> [ProactiveBriefingItem] {
        values.filter { $0.3 == .timeCritical }.prefix(ProactiveLimits.briefingItems).map { candidate, relevance, _, delivery in
            ProactiveBriefingItem(id: stableUUID(candidate.id), candidateID: candidate.id, kind: candidate.kind,
                summary: String(candidate.summary.prefix(240)), whyRelevant: String(relevance.explanation.prefix(300)),
                effectiveTime: candidate.effectiveAt, sourceEvidence: Array(relevance.evidence.map(\.reference).prefix(ProactiveLimits.evidencePerItem)),
                relatedEntities: Array(candidate.entities.prefix(5)), freshness: candidate.freshness,
                confidence: candidate.confidence, sensitivity: candidate.sensitivity, delivery: delivery, isAllDay: candidate.isAllDay)
        }
    }

    private static func makeBriefing(
        from values: [(ProactiveCandidate, RelevanceDecision, TemporalUsefulness, ProactiveDeliveryClassification)],
        input: ProactiveInput,
        now: Date,
        nextBriefing: Date,
        profileName: String?,
        calendar: Calendar,
        cutoff: Date,
        enforceCutoff: Bool
    ) -> ProactiveBriefing? {
        var sourceCounts: [String: Int] = [:]
        let selected = values.filter { candidate, relevance, _, delivery in
            let historicalCalendar = candidate.source == "calendar" && candidate.kind == .schedule
            if enforceCutoff {
                guard (delivery != .ignore || historicalCalendar),
                      belongsToDailyBriefing(candidate, relevance: relevance, now: cutoff, calendar: calendar) else { return false }
            } else if delivery == .ignore { return false }
            if candidate.kind == .information, ["gmail", "whatsapp"].contains(candidate.source) {
                guard sourceCounts[candidate.source, default: 0] < 2 else { return false }
                sourceCounts[candidate.source, default: 0] += 1
            }
            return true
        }.prefix(ProactiveLimits.briefingItems)
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
                delivery: delivery == .ignore ? .brief : delivery,
                isAllDay: candidate.isAllDay
            )
        }
        let limitations = input.healthLimitations.map(\.message)
        guard !items.isEmpty || !limitations.isEmpty else { return nil }
        var buckets: [ProactiveBriefingSectionKind: [ProactiveBriefingItem]] = [:]
        for item in items {
            let section: ProactiveBriefingSectionKind
            if item.delivery == .timeCritical || item.kind == .deadline || item.kind == .reminder { section = .needsAttention }
            else if [.scheduleChange, .cancellation].contains(item.kind) { section = .changes }
            else if let date = item.effectiveTime, calendar.isDate(date, inSameDayAs: cutoff) { section = .today }
            else { section = .later }
            buckets[section, default: []].append(item)
        }
        let sections = ProactiveBriefingSectionKind.allCases.compactMap { kind -> ProactiveBriefingSection? in
            guard kind != .opening, let values = buckets[kind], !values.isEmpty else { return nil }
            return .init(kind: kind, items: values)
        }
        var narrationItems = Array(items.prefix(5))
        if !narrationItems.isEmpty {
            let represented = Set(selected.prefix(5).map { $0.0.source })
            if let missingSource = selected.indices.first(where: { !represented.contains(selected[$0].0.source) }) {
                narrationItems[narrationItems.count - 1] = items[missingSource]
            }
        }
        let narration = makeNarration(items: narrationItems, limitations: limitations, now: now, profileName: profileName)
        let sources = Array(Set(selected.map { $0.0.source })).sorted()
        let live = Array(Set(selected.filter { $0.0.source == "calendar" || $0.0.source == "reminders" }.map { $0.0.sourceReference })).prefix(8).map { $0 }
        let memory = Array(Set(selected.flatMap { $0.1.evidence.filter { [.project, .commitment, .person, .explicitPreference].contains($0.kind) }.map(\.reference) })).prefix(ProactiveLimits.memoryEvidence).map { $0 }
        return .init(
            id: UUID(), createdAt: now,
            coverageWindow: .init(start: now, end: max(nextBriefing, now.addingTimeInterval(24 * 3_600))),
            informationCutoff: cutoff,
            sections: sections,
            sourceEvidence: sources,
            liveContextEvidence: live,
            memoryEvidence: memory,
            healthLimitations: limitations,
            narration: narration,
            deliveryState: limitations.isEmpty ? .ready : .partiallyDelivered,
            watchedSourceReferences: watchedReferences(from: selected.map { $0.0 })
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
            let dateFormatter = DateFormatter(); dateFormatter.dateStyle = .medium; dateFormatter.timeStyle = .none
            parts.append(contentsOf: items.prefix(5).map { item in
                guard let time = item.effectiveTime else { return item.summary }
                let isToday = Calendar.current.isDate(time, inSameDayAs: now)
                switch item.kind {
                case .schedule, .scheduleChange:
                    if item.isAllDay == true {
                        let day = isToday ? "Today" : "On \(dateFormatter.string(from: time))"
                        return "\(day), \(item.summary) is an all-day event."
                    }
                    let day = isToday ? "At" : "On \(dateFormatter.string(from: time)), at"
                    return "\(day) \(formatter.string(from: time)), \(item.summary)"
                case .deadline, .reminder, .commitment:
                    return "By \(ProactiveDatePresentation.label(time, isAllDay: false, relativeTo: now)), \(item.summary)"
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
                freshness: candidate.freshness, confidence: candidate.confidence, state: .active,
                watchedSourceReferences: watchedReferences(from: [candidate])
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
                    confidence: min(first.confidence, second.confidence), state: .active,
                    watchedSourceReferences: watchedReferences(from: [first, second])
                ))
            }
        }
        return Array(opportunities.prefix(ProactiveLimits.opportunities))
    }

    private static func watchedReferences(from candidates: [ProactiveCandidate]) -> [ProactiveWatchedReference] {
        Array(Set(candidates.filter { $0.source == "watchedWeb" }.map {
            ProactiveWatchedReference(externalID: $0.sourceReference, fingerprint: $0.id)
        })).sorted { ($0.externalID, $0.fingerprint) < ($1.externalID, $1.fingerprint) }
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
        case .emailUpdate, .generalUpdate: .information
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
            effectiveAt: event.effectiveAt, effectiveUntil: event.effectiveUntil, sourceUpdatedAt: event.sourceUpdatedAt, entities: event.entities,
            sensitivity: event.sensitivity, freshness: freshness,
            // A cancellation is a meaningful current change. Treating it as completed
            // would suppress the exact last-minute disruption Step 10 must surface.
            isCompleted: event.objectState == .completed || event.objectState == .absent,
            sourceHealthy: sourceHealthy, confidence: 1, isAllDay: event.isAllDay == true
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
        let sourceReference = source == "calendar"
            ? item.metadata["informationIdentifier"].flatMap { $0.isEmpty ? nil : $0 } ?? item.sourceIdentifier
            : item.sourceIdentifier
        return .init(
            id: source + ":" + reference, kind: kind,
            title: item.metadata["title"].flatMap { $0.isEmpty ? nil : $0 } ?? item.content,
            summary: item.content, source: source, sourceReference: sourceReference,
            effectiveAt: effectiveAt, effectiveUntil: effectiveUntil, sourceUpdatedAt: item.timestamp, entities: item.entities,
            sensitivity: item.sensitivity,
            freshness: item.expiration.map { $0 <= now ? .expired : .current } ?? .current,
            isCompleted: completed, sourceHealthy: true, confidence: item.confidence,
            isAllDay: item.metadata["allDay"] == "true"
        )
    }

    private static func date(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func sameNativeTime(_ first: Date?, _ second: Date?) -> Bool {
        switch (first, second) {
        case (nil, nil): true
        // Native context's ISO8601 representation has whole-second precision.
        case let (first?, second?): abs(first.timeIntervalSince(second)) < 1
        default: false
        }
    }

    private static func stableUUID(_ value: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        let tuple: uuid_t = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: tuple)
    }
}
