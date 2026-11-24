import Foundation

@MainActor final class MemoryTransport: CloudRuleTransport {
    var active: String? = "A"
    var serial = 0
    var accounts: [String: CloudRuleSession] = [:]
    var nextFailure: Failure = .none
    enum Failure { case none, loseResponse, offline, staleCAS }
    func accountID() async throws -> String? { active }
    func fetch(accountID: String) async throws -> CloudRuleSession {
        guard active == accountID else { throw CloudRuleError.accountChanged }
        return accounts[accountID] ?? .init(accountID: accountID, version: nil, ledger: .init())
    }
    func compareAndSwap(_ ledger: CloudRuleLedger, from session: CloudRuleSession) async throws -> CloudRuleSession {
        let latest = try await fetch(accountID: session.accountID)
        guard latest.version == session.version else { throw CloudRuleError.conflict }
        let failure = nextFailure; nextFailure = .none
        if case .offline = failure { throw CloudRuleError.unavailable }; if case .staleCAS = failure { throw CloudRuleError.conflict }
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
        let interruptedDeletion = try await reopened.markInterrupted(deleting.id, in: authorized)
        var takeoverDeletion = deleting
        takeoverDeletion.owner = b.deviceID
        // Dismissing the review without confirmation cannot change navigation or ownership.
        precondition(!takeoverReturnsToRuleList(takeoverDeletion, acknowledged: nil))
        precondition(!takeoverReturnsToRuleList(takeoverDeletion, acknowledged: interruptedDeletion))
        precondition(interruptedDeletion.ledger.pendingOperation(deleting.id)?.owner == reopened.deviceID)
        let acceptedDeletion = try await b.takeOver(takeoverDeletion, localBefore: [], localAfter: [], in: interruptedDeletion)
        // Ownership alone is not a confirmed deletion (including a failed EventKit check).
        precondition(!takeoverReturnsToRuleList(takeoverDeletion, acknowledged: acceptedDeletion))
        do { _ = try await b.finish(deleting.id, in: acceptedDeletion); fatalError("unverified deletion completed") }
        catch CloudRuleError.notOwner {}
        try b.recordEventKitComplete(deleting.id, in: acceptedDeletion)
        let cancelled = try await b.finish(deleting.id, in: acceptedDeletion)
        precondition(takeoverReturnsToRuleList(takeoverDeletion, acknowledged: cancelled))
        precondition(!takeoverReturnsToRuleList(nil, acknowledged: cancelled))
        precondition(!takeoverReturnsToRuleList(winner, acknowledged: cancelled))
        precondition(cancelled.ledger.tombstones.contains(rule.id) && cancelled.ledger.rules.isEmpty)
        try reopened.clearSupersededJournal(in: cancelled)
        let staleApply = CloudRuleOperation(owner: reopened.deviceID, scope: [rule.id], upserts: [envelope], deletions: [])
        let writesBefore = transport.serial
        do { _ = try await reopened.claim(staleApply, localBefore: [], localAfter: [], in: childFinished); fatalError("unrefreshed editor recreated deleted rule") }
        catch CloudRuleError.conflict {}
        do { _ = try await reopened.claim(staleApply, localBefore: [], localAfter: [], in: cancelled); fatalError("tombstone failed to stop stale editor") }
        catch CloudRuleError.ruleDeleted {}
        precondition(transport.serial == writesBefore && reopened.recoverableJournal(in: cancelled) == nil)
        transport.active = "B"
        let independent = try await reopened.refresh()!
        precondition(independent.ledger.rules.isEmpty)
        do { _ = try await reopened.migrate([envelope], in: independent); fatalError("account boundary leaked") }
        catch CloudRuleError.legacyAccountMismatch {}
        transport.active = "A"
        let restored = try await reopened.refresh()!
        let notReimported = try await reopened.migrate([envelope], in: restored)
        precondition(notReimported.ledger.rules.isEmpty)
        // Reopen the exact unscoped filename used by the installed Development build.
        let sharedDirectory = directory.appendingPathComponent("environment")
        let devTransport = MemoryTransport()
        let prodTransport = MemoryTransport()
        let oldDev = RuleCloudSync(transport: devTransport,
            stateURL: sharedDirectory.appendingPathComponent("cloud-state-v1.json"))
        let oldMigrated = try await oldDev.migrate([envelope], in: oldDev.refresh()!)
        precondition(oldDev.hasMigratedLegacy(in: oldMigrated))
        let oldOperation = CloudRuleOperation(owner: oldDev.deviceID, scope: [rule.id],
                                              upserts: [envelope], deletions: [])
        let oldPending = try await oldDev.claim(oldOperation, localBefore: [], localAfter: [], in: oldMigrated)
        let dev = RuleCloudSync(transport: devTransport, environment: .development, stateDirectory: sharedDirectory)
        precondition(dev.deviceID == oldDev.deviceID && dev.recoverableJournal(in: oldPending)?.operation.id == oldOperation.id)
        let prod = RuleCloudSync(transport: prodTransport, environment: .production, stateDirectory: sharedDirectory)
        let emptyProd = try await prod.refresh()!
        precondition(prod.deviceID != dev.deviceID && prod.canMigrateLegacy(in: emptyProd))
        precondition(!prod.hasMigratedLegacy(in: emptyProd) && prod.recoverableJournal(in: emptyProd) == nil)
        do { _ = try await prod.verifyOwnership(oldOperation.id, in: emptyProd); fatalError("Development authorization leaked") }
        catch CloudRuleError.notOwner {}
        var productionLegacy = envelope
        productionLegacy.rule.name = "Original local rules, not Development edits"
        let legacyFixture = [productionLegacy] + (1...35).map {
            CloudRuleEnvelope(rule: Rule(name: "Legacy rule \($0)", kind: .gregorian, date: "", category: "Main"),
                              destination: nil, prior: nil)
        }
        let prodFirst = try await prod.migrate(legacyFixture, in: emptyProd)
        precondition(prodFirst.ledger.rules.first?.rule.name == productionLegacy.rule.name && prodFirst.ledger.pending.isEmpty && prodFirst.ledger.rules.count == 36)
        let prodReload = RuleCloudSync(transport: prodTransport, environment: .production, stateDirectory: sharedDirectory)
        let prodSecond = try await prodReload.migrate(legacyFixture, in: prodReload.refresh()!)
        precondition(prodReload.deviceID == prod.deviceID && prodReload.hasMigratedLegacy(in: prodSecond) && prodTransport.serial == 1 && prodSecond.ledger.rules.count == 36)
        prodTransport.active = nil
        let signedOut = try await prodReload.refresh()
        precondition(signedOut == nil)
        prodTransport.active = "B"
        let prodOther = try await prodReload.refresh()!
        do { _ = try await prodReload.migrate([productionLegacy], in: prodOther); fatalError("Production leaked to wrong account") }
        catch CloudRuleError.legacyAccountMismatch {}
        precondition(prodOther.ledger.rules.isEmpty && prodTransport.serial == 1)
        precondition(CloudRuleEnvironment.development.localKey("rules.hasCloudAccount") == "rules.hasCloudAccount")
        precondition(CloudRuleEnvironment.production.localKey("rules.hasCloudAccount") != "rules.hasCloudAccount")
        // Explicit peer freeze is not ownership transfer or an EventKit checkpoint.
        let freezeTransport = MemoryTransport()
        let incumbent = RuleCloudSync(transport: freezeTransport, stateURL: directory.appendingPathComponent("incumbent"))
        let peer = RuleCloudSync(transport: freezeTransport, stateURL: directory.appendingPathComponent("peer"))
        let initial = try await incumbent.refresh()!
        let attempt = CloudRuleOperation(owner: incumbent.deviceID, scope: [rule.id], upserts: [envelope], deletions: [])
        let claimed = try await incumbent.claim(attempt, localBefore: [], localAfter: [], in: initial)
        let checked = try await incumbent.verifyOwnership(attempt.id, in: claimed)
        freezeTransport.nextFailure = .offline
        do { _ = try await peer.confirmInterrupted(attempt, accountID: "A"); fatalError("unacknowledged freeze succeeded") }
        catch CloudRuleError.unavailable {}
        let stillPending = try await peer.refresh()!
        precondition(stillPending.ledger.pendingOperation(attempt.id) == attempt)
        // Lost successful response is accepted only after exact interrupted readback.
        freezeTransport.nextFailure = .loseResponse
        let peerFrozen = try await peer.confirmInterrupted(attempt, accountID: "A")
        precondition(peerFrozen.ledger.pendingOperation(attempt.id)?.interrupted == true)
        precondition(peerFrozen.ledger.pendingOperation(attempt.id)?.owner == incumbent.deviceID)
        do { _ = try await incumbent.verifyOwnership(attempt.id, in: peerFrozen); fatalError("frozen EventKit re-entry allowed") }
        catch CloudRuleError.notOwner {}
        do { _ = try await incumbent.finish(attempt.id, in: peerFrozen); fatalError("unchecked frozen results published") }
        catch CloudRuleError.notOwner {}
        // If the writer had already entered EventKit, publish only its verified,
        // unchanged result as long as no one acquired its writing right.
        try incumbent.recordEventKitComplete(attempt.id, in: checked)
        let winnerAfterFreeze = try await incumbent.finish(attempt.id, in: peerFrozen)
        precondition(winnerAfterFreeze.ledger.completed.contains(attempt.id))
        let confirmedAlreadyComplete = try await peer.confirmInterrupted(attempt, accountID: "A")
        precondition(confirmedAlreadyComplete.ledger.pendingOperation(attempt.id) == nil)
        let retryAttempt = CloudRuleOperation(owner: incumbent.deviceID, scope: [rule.id], upserts: [envelope], deletions: [])
        let freshClaim = try await incumbent.claim(retryAttempt, localBefore: [], localAfter: [], in: winnerAfterFreeze)
        freezeTransport.nextFailure = .staleCAS
        let retryFrozen = try await peer.confirmInterrupted(retryAttempt, accountID: "A")
        precondition(retryFrozen.ledger.pendingOperation(retryAttempt.id)?.interrupted == true)
        var replacement = retryAttempt
        replacement.owner = peer.deviceID
        _ = try await peer.takeOver(replacement, localBefore: [], localAfter: [], in: retryFrozen)
        let serial = freezeTransport.serial
        do { _ = try await incumbent.confirmInterrupted(retryAttempt, accountID: "A"); fatalError("stale freeze overrode takeover") }
        catch CloudRuleError.conflict {}
        do { _ = try await incumbent.finish(retryAttempt.id, in: freshClaim); fatalError("stale owner published") }
        catch CloudRuleError.notOwner {}
        precondition(freezeTransport.serial == serial)
        // A duration never proves the prior writer stopped or permits writes.
        var wait = CloudPendingWait()
        wait.observe(freshClaim, elapsed: .seconds(0))
        wait.observe(freshClaim, elapsed: .seconds(119))
        precondition(wait.confirmedWaiting.isEmpty)
        wait.observe(freshClaim, elapsed: .seconds(120))
        precondition(wait.confirmedWaiting[retryAttempt.id] == retryAttempt)
        var absentWithoutReceipt = freshClaim.ledger
        absentWithoutReceipt.pending = []
        wait.observe(.init(accountID: "A", version: nil, ledger: absentWithoutReceipt), elapsed: .seconds(150))
        precondition(wait.confirmedWaiting[retryAttempt.id] == retryAttempt)
        let otherSession = CloudRuleSession(accountID: "B", version: nil, ledger: .init())
        wait.observe(otherSession, elapsed: .seconds(200))
        precondition(wait.confirmedWaiting.isEmpty)
        // Confirmed-same-operation timeout clears on authoritative late completion.
        wait.observe(claimed, elapsed: .seconds(250))
        wait.observe(claimed, elapsed: .seconds(370))
        precondition(wait.confirmedWaiting[attempt.id] == attempt)
        wait.observe(winnerAfterFreeze, elapsed: .seconds(400))
        precondition(wait.confirmedWaiting.isEmpty)

        // Unlock never publishes previous planned writes, removes effective rules,
        // or grants EventKit ownership to the reviewer.
        let undoTransport = MemoryTransport()
        let original = RuleCloudSync(transport: undoTransport, stateURL: directory.appendingPathComponent("original"))
        let reviewer = RuleCloudSync(transport: undoTransport, stateURL: directory.appendingPathComponent("reviewer"))
        let originalSeed = try await original.migrate([envelope], in: original.refresh()!)
        let pendingDelete = CloudRuleOperation(owner: original.deviceID, scope: [rule.id], upserts: [], deletions: [rule.id])
        let locked = try await original.claim(pendingDelete, localBefore: [], localAfter: [], in: originalSeed)
        do { _ = try await reviewer.retireInterruptedWithoutEventWrite(pendingDelete, in: locked); fatalError("uninterrupted operation unlocked") }
        catch CloudRuleError.conflict {}
        original.endLocalExecution(pendingDelete.id)
        let interrupted = try await original.markInterrupted(pendingDelete.id, in: locked)
        let releaseCandidate = interrupted.ledger.pendingOperation(pendingDelete.id)!
        undoTransport.nextFailure = .staleCAS
        do { _ = try await reviewer.retireInterruptedWithoutEventWrite(releaseCandidate, in: interrupted); fatalError("unlocked on unverified revision") }
        catch CloudRuleError.conflict {}
        undoTransport.nextFailure = .loseResponse
        let unlocked = try await reviewer.retireInterruptedWithoutEventWrite(releaseCandidate, in: interrupted)
        precondition(unlocked.ledger.rules == originalSeed.ledger.rules && unlocked.ledger.tombstones.isEmpty)
        precondition(unlocked.ledger.retired?.contains(pendingDelete.id) == true && !unlocked.ledger.completed.contains(pendingDelete.id))
        do { _ = try await original.verifyOwnership(pendingDelete.id, in: unlocked); fatalError("old original replayed retired attempt") }
        catch CloudRuleError.notOwner {}
        try original.clearSupersededJournal(in: unlocked)
        precondition(original.recoverableJournal(in: unlocked) == nil)
        let ordinaryDelete = CloudRuleOperation(owner: reviewer.deviceID, scope: [rule.id], upserts: [], deletions: [rule.id])
        let explicit = try await reviewer.claim(ordinaryDelete, localBefore: [], localAfter: [], in: unlocked)
        precondition(explicit.ledger.pendingOperation(ordinaryDelete.id)?.owner == reviewer.deviceID)
        print("Cloud sync contract passed: migration, ID redaction, overlapping CAS, lost responses, takeover/stale owner, restart before CAS, tombstones, account isolation, and Development-to-Production migration of 36 synthetic rules")
    }
}
