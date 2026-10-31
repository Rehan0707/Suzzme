import Foundation
import Darwin
import os
import dnssd

#if WATCHED_DNS_CHECKS
private final class Audit: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: [WebDNSValidationAudit]())
    func record(_ event: WebDNSValidationAudit) { state.withLock { $0.append(event) } }
    var descriptions: [String] { state.withLock { $0.map { String(describing: $0) } } }
    var started: Int { state.withLock { $0.filter { if case .started = $0 { true } else { false } }.count } }
    var cancelled: Int { state.withLock { $0.filter { if case .cancelled = $0 { true } else { false } }.count } }
    var opened: Int { state.withLock { $0.filter { if case .descriptorOpened(_, let fd) = $0 { fd >= 0 } else { false } }.count } }
    var closed: Int { state.withLock { $0.filter { if case .descriptorClosed(_, _, let closed, _) = $0 { closed } else { false } }.count } }
}

@main struct WatchedDNSResolverChecks {
    @MainActor private static var passed = 0
    @MainActor private static var failed = 0
    private static let a = UInt16(kDNSServiceType_A)
    private static let aaaa = UInt16(kDNSServiceType_AAAA)
    private static let host = "watch.example.com"
    private static let add = UInt32(kDNSServiceFlagsAdd)
    private static let more = UInt32(kDNSServiceFlagsAdd | kDNSServiceFlagsMoreComing)
    private static func bytes(_ value: String, family: Int32) -> Data {
        if family == AF_INET {
            var address = in_addr(); precondition(inet_pton(family, value, &address) == 1)
            return withUnsafeBytes(of: address) { Data($0) }
        }
        var address = in6_addr(); precondition(inet_pton(family, value, &address) == 1)
        return withUnsafeBytes(of: address) { Data($0) }
    }
    private static func positive(_ type: UInt16, _ address: String, delay: TimeInterval = 0, flags: UInt32? = nil) -> WebDNSValidationStep {
        .init(requestedType: type, delay: delay, flags: flags ?? add, bytes: bytes(address, family: type == a ? AF_INET : AF_INET6))
    }
    private static func negative(_ type: UInt16, delay: TimeInterval = 0) -> WebDNSValidationStep {
        .init(requestedType: type, delay: delay, error: Int32(kDNSServiceErr_NoSuchRecord))
    }
    @MainActor private static func expect(_ value: Bool, _ label: String) {
        if value { passed += 1; print("PASS \(label)") }
        else { failed += 1; print("FAIL \(label)") }
    }
    private static func waitFor(_ predicate: @Sendable () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw WatchedLinkError.timeout
    }
    @MainActor private static func reject(_ expected: WatchedLinkError, _ label: String, _ operation: () async throws -> Void) async {
        do { try await operation(); expect(false, label) }
        catch let error as WatchedLinkError { expect(error == expected, label) }
        catch { expect(false, label + " had unexpected error") }
    }
    @MainActor private static func checkCancellation(_ label: String, _ operation: () async throws -> Void) async {
        do { try await operation(); expect(false, label) }
        catch is CancellationError { expect(true, label) }
        catch { expect(false, label + " had unexpected error") }
    }
    @MainActor private static func scripted(_ steps: [WebDNSValidationStep], error: WatchedLinkError, label: String, approved: Bool = false) async {
        let audit = Audit()
        let resolver = SystemWebHostResolver.validationScripted(steps, audit: audit.record)
        await reject(error, label) {
            if approved { _ = try await WebURLPolicy.approvedAddresses(for: URL(string: "https://" + host + "/")!, resolver: resolver) }
            else { _ = try await resolver.resolution(for: host, timeout: 0.1) }
        }
        expect(audit.started == 2 && audit.cancelled == 2, label + " closes both family operations")
    }

    @MainActor static func main() async throws {
        let audit = Audit()
        let resolver = SystemWebHostResolver.validationScripted([
            positive(a, "8.8.8.8"), positive(aaaa, "2001:4860:4860::8888", delay: 0.03),
        ], audit: audit.record)
        let clock = ContinuousClock(); let start = clock.now
        let answer = try await resolver.resolution(for: host, timeout: 0.2)
        expect(Set(answer.addresses) == ["8.8.8.8", "2001:4860:4860::8888"], "independent A and AAAA batches both collected")
        expect(start.duration(to: clock.now) >= .milliseconds(20), "A MoreComing clear does not finish unresolved AAAA")
        expect(answer.canonicalName == host, "result retains original DNS identity")
        expect(audit.started == 2 && audit.cancelled == 2, "successful resolution closes both family operations")

        let negativeFirst = SystemWebHostResolver.validationScripted([
            negative(aaaa), positive(a, "8.8.8.8", delay: 0.02),
        ], audit: { _ in })
        expect(try await negativeFirst.resolution(for: host, timeout: 0.1).addresses == ["8.8.8.8"], "one negative family waits for the other positive family")
        await scripted([negative(a), negative(aaaa)], error: .blockedHost, label: "both negative families produce no approved address")
        await scripted([positive(a, "8.8.8.8", flags: more), positive(a, "127.0.0.1", delay: 0.01), negative(aaaa)], error: .blockedHost, label: "mixed public/private A batch is rejected", approved: true)
        await scripted([positive(a, "8.8.8.8"), positive(aaaa, "2001:4860::8888", flags: more), positive(aaaa, "fd00::1", delay: 0.01)], error: .blockedHost, label: "mixed public/private AAAA batch is rejected", approved: true)
        await scripted([positive(a, "8.8.8.8")], error: .timeout, label: "missing AAAA completion fails closed")
        await scripted([positive(aaaa, "2001:4860::8888")], error: .timeout, label: "missing A completion fails closed")
        await scripted([.init(requestedType: a, flags: more, responseType: UInt16(kDNSServiceType_CNAME)), negative(aaaa)], error: .blockedHost, label: "CNAME referral rejected before parsing or following alias")
        await scripted([.init(requestedType: a, responseType: 39), negative(aaaa)], error: .blockedHost, label: "unknown/DNAME record rejected")
        var changedName = positive(a, "8.8.8.8"); changedName.name = "other.example.com."
        await scripted([changedName, negative(aaaa)], error: .blockedHost, label: "different callback DNS identity rejected")
        var wrongClass = positive(a, "8.8.8.8"); wrongClass.recordClass = 3
        await scripted([wrongClass, negative(aaaa)], error: .blockedHost, label: "non-IN response rejected")
        await scripted([.init(requestedType: a, bytes: Data(repeating: 1, count: 3)), negative(aaaa)], error: .blockedHost, label: "malformed A bytes rejected")
        await scripted([negative(a), .init(requestedType: aaaa, bytes: Data(repeating: 1, count: 15))], error: .blockedHost, label: "malformed AAAA bytes rejected")
        await scripted([positive(a, "8.8.8.8", flags: 0), negative(aaaa)], error: .blockedHost, label: "remove event rejected as changing answer")
        await scripted([.init(requestedType: a, error: Int32(kDNSServiceErr_ServiceNotRunning)), negative(aaaa)], error: .unavailable, label: "resolver-daemon failure fails closed")
        await scripted(Array(repeating: positive(a, "8.8.8.8", flags: more), count: 65) + [negative(aaaa)], error: .blockedHost, label: "record callback count is bounded")
        await scripted([positive(a, "8.8.8.8"), positive(a, "127.0.0.1", delay: 0.01), negative(aaaa, delay: 0.03)], error: .blockedHost, label: "changed completed family rejected before other family ends")

        for timeout in [0.0, -1, .nan, .infinity, WatchedLinkLimits.dnsTimeout + 0.1] {
            let invalidAudit = Audit()
            let invalid = SystemWebHostResolver.validationScripted([], audit: invalidAudit.record)
            await reject(.timeout, "invalid caller DNS budget rejected") { _ = try await invalid.resolution(for: host, timeout: timeout) }
            expect(invalidAudit.started == 0, "invalid budget starts no DNS operations")
        }
        let budgetAudit = Audit()
        let budgeted = SystemWebHostResolver.validationScripted([], audit: budgetAudit.record)
        let budgetStart = clock.now
        await reject(.timeout, "policy forwards the remaining caller DNS budget") {
            _ = try await WebURLPolicy.approvedAddresses(for: URL(string: "https://" + host + "/")!, resolver: budgeted, timeout: 0.025)
        }
        expect(budgetStart.duration(to: clock.now) < .milliseconds(300), "remaining budget is not reset to three seconds")
        expect(budgetAudit.cancelled == 2, "remaining budget closes both DNS operations")

        let beforeAudit = Audit()
        let beforeResolver = SystemWebHostResolver.validationScripted([], audit: beforeAudit.record)
        let beforeTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await beforeResolver.resolution(for: host, timeout: 0.1)
        }
        await checkCancellation("pre-cancelled resolution throws CancellationError") { _ = try await beforeTask.value }
        expect(beforeAudit.started == 0, "pre-cancelled resolution starts no daemon operations")

        let pendingAudit = Audit()
        let pending = SystemWebHostResolver.validationScripted([], audit: pendingAudit.record)
        let pendingTask = Task { try await pending.resolution(for: host, timeout: 0.2) }
        try await waitFor { pendingAudit.started == 2 }
        await reject(.unavailable, "only one resolver operation can remain outstanding") { _ = try await SystemWebHostResolver().resolution(for: host, timeout: 0.1) }
        pendingTask.cancel()
        await checkCancellation("pending resolution cancellation is classified") { _ = try await pendingTask.value }
        expect(pendingAudit.cancelled == 2, "pending cancellation closes both operations once")

        var allRacesClosed = true
        for iteration in 0..<40 {
            let raceAudit = Audit()
            var delayed = positive(a, "8.8.8.8", delay: 0.002)
            delayed.deliverAfterCancellation = true
            let racing = SystemWebHostResolver.validationScripted([delayed, negative(aaaa, delay: 0.002)], audit: raceAudit.record)
            let task = Task { try await racing.resolution(for: host, timeout: 0.015) }
            try await Task.sleep(for: iteration.isMultiple(of: 2) ? .milliseconds(1) : .milliseconds(3))
            task.cancel()
            do { _ = try await task.value } catch is CancellationError {} catch { allRacesClosed = false }
            allRacesClosed = allRacesClosed && raceAudit.started == raceAudit.cancelled
        }
        try await Task.sleep(for: .milliseconds(20))
        expect(allRacesClosed, "40 success/cancellation races close every started operation once; late callbacks cannot resume twice")

        // Actual DNS-SD daemon operations are restricted to Apple's LocalOnly
        // interface. No DNS packets, public host lookups, hosts edits or system
        // resolver/trust settings are required for this native adapter evidence.
        let localHost = "suzzme-dns-" + UUID().uuidString.lowercased() + ".example.com"
        let negativeAudit = Audit()
        let localNegative = SystemWebHostResolver.validationLocalOnly(audit: negativeAudit.record)
        await reject(.blockedHost, "native LocalOnly A and AAAA negative answers complete") { _ = try await localNegative.resolution(for: localHost, timeout: 0.5) }
        expect(negativeAudit.cancelled == 2, "native negative completion terminates both operations before return")
        try? await waitFor { negativeAudit.closed == 2 }
        print("Native negative audit: \(negativeAudit.descriptions)")
        expect(negativeAudit.opened == 2 && negativeAudit.closed == 2, "native negative completion promptly drains both actual resolver descriptors")
        let nativeTimeoutAudit = Audit()
        let localTimeout = SystemWebHostResolver.validationLocalOnly(negativeAnswers: false, audit: nativeTimeoutAudit.record)
        let nativeStart = clock.now
        await reject(.timeout, "native LocalOnly pending query deadline cancels actual daemon work") { _ = try await localTimeout.resolution(for: localHost, timeout: 0.08) }
        expect(nativeStart.duration(to: clock.now) < .seconds(1), "native resolver deadline returns promptly")
        expect(nativeTimeoutAudit.cancelled == 2, "native timeout terminates both operations before return")
        try? await waitFor { nativeTimeoutAudit.closed == 2 }
        print("Native timeout audit: \(nativeTimeoutAudit.descriptions)")
        expect(nativeTimeoutAudit.opened == 2 && nativeTimeoutAudit.closed == 2, "native timeout promptly drains both daemon descriptors")
        let nativeCancelAudit = Audit()
        let localCancel = SystemWebHostResolver.validationLocalOnly(negativeAnswers: false, audit: nativeCancelAudit.record)
        let nativeTask = Task { try await localCancel.resolution(for: localHost, timeout: 0.5) }
        try await waitFor { nativeCancelAudit.opened == 2 }
        let nativeCancelStart = clock.now
        nativeTask.cancel()
        await checkCancellation("native LocalOnly query cancellation is classified") { _ = try await nativeTask.value }
        expect(nativeCancelStart.duration(to: clock.now) < .seconds(1), "native query cancellation returns promptly")
        expect(nativeCancelAudit.cancelled == 2, "native cancellation terminates both operations before return")
        try? await waitFor { nativeCancelAudit.closed == 2 }
        print("Native cancellation audit: \(nativeCancelAudit.descriptions)")
        expect(nativeCancelAudit.opened == 2 && nativeCancelAudit.closed == 2, "native cancellation promptly drains both daemon descriptors")
        print("Watched DNS resolver: \(passed) passed, \(failed) failed")
        print("Native evidence: LocalOnly daemon negative A/AAAA completion, pending-query timeout and cancellation; \(negativeAudit.closed + nativeTimeoutAudit.closed + nativeCancelAudit.closed) actual resolver descriptors observed closed. Scripted callback cases are separate from native DNS evidence.")
        if failed > 0 { exit(1) }
    }
}
#else
#error("Run this fixture with WATCHED_DNS_CHECKS; native test overrides are absent from normal products")
#endif
