import Foundation

@MainActor final class MemoryTransport: CloudRuleTransport {
    var active: String? = "A"
    var serial = 0
    var accounts: [String: CloudRuleSession] = [:]
    var nextFailure: Failure = .none
    enum Failure { case none, loseResponse, offline }
    func accountID() async throws -> String? { active }
    func fetch(accountID: String) async throws -> CloudRuleSession {
        guard active == accountID else { throw CloudRuleError.accountChanged }
        return accounts[accountID] ?? .init(accountID: accountID, version: nil, ledger: .init())
    }
    func compareAndSwap(_ ledger: CloudRuleLedger, from session: CloudRuleSession) async throws -> CloudRuleSession {
        let latest = try await fetch(accountID: session.accountID)
        guard latest.version == session.version else { throw CloudRuleError.conflict }
        let failure = nextFailure; nextFailure = .none
        if case .offline = failure { throw CloudRuleError.unavailable }
        serial += 1
        let result = CloudRuleSession(accountID: latest.accountID, version: Data(String(serial).utf8), ledger: ledger)
        accounts[latest.accountID] = result
        if case .loseResponse = failure { throw CloudRuleError.unavailable }
        return result
    }
}

@main struct Harness {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CalStitchCloudFixture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = MemoryTransport()
        let aURL = directory.appendingPathComponent("a")
        let a = RuleCloudSync(transport: transport, stateURL: aURL)
        let b = RuleCloudSync(transport: transport, stateURL: directory.appendingPathComponent("b"))
        var rule = Rule(name: "Migration fixture", kind: .gregorian, date: "", category: "Main")
        rule.target = "LOCAL_EVENTKIT_IDENTIFIER"
        rule.birthdaySource = .init(contactID: "LOCAL_CONTACT_ID", isLunar: false, month: 1, day: 1,
                                    isLeapMonth: false, year: nil)
        let occurrence = PlannedOccurrence(ruleID: rule.id, key: "0", title: rule.name, start: .now,
                                           end: .now.addingTimeInterval(86_400), isAllDay: true,
                                           calendarID: "LOCAL_EVENTKIT_IDENTIFIER")
        var envelope = CloudRuleEnvelope(rule: rule, destination: .init(title: "Fixture", sourceTitle: "",
                                                                        sourceType: 0, localOwner: a.deviceID),
                                             prior: [occurrence])
        let unknown = CloudRuleEnvelope(rule: rule, destination: nil, prior: nil, unresolvedOwner: a.deviceID)
        let zero = CloudRuleEnvelope(rule: rule, destination: nil, prior: [], unresolvedOwner: a.deviceID)
        let unknownRoundTrip = try JSONDecoder().decode(CloudRuleEnvelope.self, from: JSONEncoder().encode(unknown))
        let zeroRoundTrip = try JSONDecoder().decode(CloudRuleEnvelope.self, from: JSONEncoder().encode(zero))
        precondition(unknownRoundTrip.prior == nil && zeroRoundTrip.prior == [])
        let base = try await a.refresh()!
        let seeded = try await a.migrate([envelope], in: base)
        precondition(a.hasMigratedLegacy(in: seeded) && seeded.ledger.rules.first?.rule.target == "" && seeded.ledger.rules.first?.prior?.first?.calendarID == "")
        let wire = String(decoding: try JSONEncoder().encode(seeded.ledger), as: UTF8.self)
        precondition(!wire.contains("LOCAL_EVENTKIT_IDENTIFIER") && !wire.contains("LOCAL_CONTACT_ID"))
        precondition(seeded.ledger.rules.first?.destination?.localOwner == a.deviceID)
        let bStale = try await b.refresh()!
        envelope.rule.name = "winner"
        let winner = CloudRuleOperation(owner: a.deviceID, scope: [rule.id], upserts: [envelope], deletions: [])
        transport.nextFailure = .loseResponse
        let won = try await a.claim(winner, localBefore: [], localAfter: [], in: seeded)
        precondition(won.ledger.pendingOperation(winner.id) != nil)
        let loser = CloudRuleOperation(owner: b.deviceID, scope: [rule.id], upserts: [envelope], deletions: [])
        do { _ = try await b.claim(loser, localBefore: [], localAfter: [], in: bStale); fatalError("stale claim won") }
        catch CloudRuleError.conflict {}
        precondition(b.recoverableJournal(in: won) == nil)
        do { _ = try await b.takeOver(loser, localBefore: [], localAfter: [], in: won); fatalError("normal pending takeover") }
        catch CloudRuleError.interruptedRequired {}
        a.endLocalExecution(winner.id)
        let frozen = try await a.markInterrupted(winner.id, in: won)
        var resumed = winner; resumed.owner = b.deviceID
        let handed = try await b.takeOver(resumed, localBefore: [], localAfter: [], in: frozen)
        do { _ = try await a.verifyOwnership(winner.id, in: handed); fatalError("stale original resumed") }
        catch CloudRuleError.notOwner {}
        _ = try await b.verifyOwnership(winner.id, in: handed)
        try b.recordEventKitComplete(winner.id, in: handed)
        transport.nextFailure = .loseResponse
        let finished = try await b.finish(winner.id, in: handed)
        precondition(finished.ledger.rules.first?.rule.name == "winner" && b.recoverableJournal(in: finished) == nil)
        try a.clearSupersededJournal(in: finished)

        // A not-yet-visible child must still reserve its parent against concurrent deletion.
        let child = Rule(name: "Child", kind: .gregorian, date: "", category: "Main", parent: rule.id)
        let pendingChild = CloudRuleOperation(owner: a.deviceID, scope: [rule.id, child.id],
                                             upserts: [.init(rule: child, destination: envelope.destination, prior: [])],
                                             deletions: [])
        let childClaim = try await a.claim(pendingChild, localBefore: [], localAfter: [],
                                           localPlan: Data("LOCAL_EXACT_REMOVAL_FINGERPRINT".utf8), in: finished)
        precondition(!childClaim.ledger.rules.contains(where: { $0.id == child.id }))
        let pendingWire = String(decoding: try JSONEncoder().encode(childClaim.ledger), as: UTF8.self)
        precondition(!pendingWire.contains("LOCAL_EXACT_REMOVAL_FINGERPRINT"))
        let overlappingParent = CloudRuleOperation(owner: b.deviceID, scope: [rule.id],
                                                   upserts: [], deletions: [rule.id])
        do { _ = try await b.claim(overlappingParent, localBefore: [], localAfter: [], in: childClaim); fatalError("child reservation missed") }
        catch CloudRuleError.reserved {}
        do { _ = try await a.finish(pendingChild.id, in: childClaim); fatalError("unverified event result published") }
        catch CloudRuleError.notOwner {}
        try a.recordEventKitComplete(pendingChild.id, in: childClaim)
        let childFinished = try await a.finish(pendingChild.id, in: childClaim)
        precondition(childFinished.ledger.rules.map(\.id) == [rule.id, child.id])

        let deleting = CloudRuleOperation(owner: a.deviceID, scope: [rule.id, child.id], upserts: [], deletions: [rule.id, child.id])
        transport.nextFailure = .offline
        do { _ = try await a.claim(deleting, localBefore: [], localAfter: [], in: childFinished); fatalError("offline claim won") }
        catch CloudRuleError.unavailable {}
        let reopened = RuleCloudSync(transport: transport, stateURL: aURL)
        precondition(reopened.deviceID == a.deviceID && reopened.recoverableJournal(in: childFinished)?.stage == .acquiring)
        let authorized = try await reopened.resolveAcquiringJournal(in: childFinished)
        precondition(reopened.recoverableJournal(in: authorized)?.stage == .authorized)
        try reopened.recordEventKitComplete(deleting.id, in: authorized)
        let cancelled = try await reopened.finish(deleting.id, in: authorized)
        precondition(cancelled.ledger.tombstones.contains(rule.id) && cancelled.ledger.rules.isEmpty)
        transport.active = "B"
        let independent = try await reopened.refresh()!
        precondition(independent.ledger.rules.isEmpty)
        do { _ = try await reopened.migrate([envelope], in: independent); fatalError("account boundary leaked") }
        catch CloudRuleError.legacyAccountMismatch {}
        transport.active = "A"
        let restored = try await reopened.refresh()!
        let notReimported = try await reopened.migrate([envelope], in: restored)
        precondition(notReimported.ledger.rules.isEmpty)
        print("Cloud sync contract passed: migration, ID redaction, overlapping CAS, lost responses, takeover/stale owner, restart before CAS, tombstones, and account isolation")
    }
}
