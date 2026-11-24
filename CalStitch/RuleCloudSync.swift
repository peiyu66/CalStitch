import CloudKit
import Foundation

/// Matches the signed CloudKit entitlement selected for this Xcode configuration.
enum CloudRuleEnvironment: String {
    case development = "Development"
    case production = "Production"

    static let current: Self = {
        #if DEBUG
        .development
        #else
        .production
        #endif
    }()

    /// The only unscoped cloud release, build 20, was signed for Development.
    /// Keep its durable state available only in Development; Production starts clean.
    func localKey(_ legacy: String) -> String {
        self == .development ? legacy : "production." + legacy
    }
}

struct CloudRuleEnvelope: Codable, Hashable, Identifiable {
    var id: UUID { rule.id }
    var rule: Rule
    var destination: CalendarSyncDestination?
    var unresolvedOwner: UUID?
    /// nil is absent or unknown history; [] is a confirmed empty applied plan.
    var prior: [PlannedOccurrence]?

    init(rule: Rule, destination: CalendarSyncDestination?, prior: [PlannedOccurrence]?, unresolvedOwner: UUID? = nil) {
        self.rule = rule
        self.destination = destination
        self.unresolvedOwner = unresolvedOwner
        self.prior = prior
        sanitize()
    }

    mutating func sanitize() {
        rule.target = ""
        // CNContact identifiers are local to a device, too.
        rule.birthdaySource = nil
        prior = prior?.map { $0.cloudRedacted() }
    }
}

extension PlannedOccurrence {
    fileprivate func cloudRedacted() -> Self {
        var value = self
        value.calendarID = ""
        return value
    }
}

struct CloudRuleOperation: Codable, Equatable, Identifiable {
    var id = UUID()
    var owner: UUID
    var scope: Set<UUID>
    var upserts: [CloudRuleEnvelope]
    var deletions: Set<UUID>
    var plan: CalendarSyncPlan? = nil
    var interrupted = false

    mutating func sanitize() {
        for index in upserts.indices { upserts[index].sanitize() }
    }
}

struct CloudRuleLedger: Codable, Equatable {
    var schema = 1
    var rules: [CloudRuleEnvelope] = []
    var pending: [CloudRuleOperation] = []
    var tombstones: Set<UUID> = []
    var completed: Set<UUID> = []

    func pendingOperation(_ id: UUID) -> CloudRuleOperation? { pending.first { $0.id == id } }

    fileprivate func validate() throws {
        guard schema == 1, Set(rules.map(\.id)).count == rules.count,
              Set(pending.map(\.id)).count == pending.count,
              Set(rules.map(\.id)).isDisjoint(with: tombstones) else {
            throw CloudRuleError.invalidLedger
        }
        var reserved: Set<UUID> = []
        for operation in pending {
            let items = Set(operation.upserts.map(\.id))
            guard !operation.scope.isEmpty, reserved.isDisjoint(with: operation.scope),
                  items.count == operation.upserts.count, items.isSubset(of: operation.scope),
                  operation.deletions.isSubset(of: operation.scope), items.isDisjoint(with: operation.deletions),
                  !completed.contains(operation.id),
                  operation.plan.map({ Self.validPlan($0, operation: operation) }) ?? true else {
                throw CloudRuleError.invalidLedger
            }
            reserved.formUnion(operation.scope)
        }
        for entry in rules + pending.flatMap(\.upserts) {
            guard entry.rule.target.isEmpty, entry.rule.birthdaySource == nil,
                  entry.prior?.allSatisfy({ $0.ruleID == entry.id && $0.calendarID.isEmpty }) != false else {
                throw CloudRuleError.invalidLedger
            }
        }
    }

    private static func validPlan(_ plan: CalendarSyncPlan, operation: CloudRuleOperation) -> Bool {
        guard plan.attemptID == operation.id, plan.ruleIDs.isSubset(of: operation.scope) else { return false }
        let occurrences = plan.desired + plan.previous + plan.result + plan.mutations.flatMap {
            [$0.old, $0.new].compactMap { $0 }
        }
        return occurrences.allSatisfy { plan.ruleIDs.contains($0.ruleID) && $0.calendarID.isEmpty }
    }

}

struct CloudRuleSession {
    let accountID: String
    /// Archived CKRecord system fields; equality identifies the observed server version.
    let version: Data?
    let ledger: CloudRuleLedger
    var changeTag: String? = nil
}

struct CloudRuleJournal: Codable {
    enum Stage: String, Codable { case acquiring, authorized, eventKitComplete }
    var operation: CloudRuleOperation
    var localBefore: [PlannedOccurrence]
    var localAfter: [PlannedOccurrence]
    var localPlan: Data?
    var baseVersion: Data? = nil
    var baseChangeTag: String? = nil
    var isTakeover = false
    var stage: Stage = .acquiring
}

/// Only an acknowledged manual takeover deletion navigates away from the editor.
func takeoverReturnsToRuleList(_ operation: CloudRuleOperation?, acknowledged: CloudRuleSession?) -> Bool {
    guard let operation, !operation.deletions.isEmpty, let ledger = acknowledged?.ledger else { return false }
    return ledger.completed.contains(operation.id) && operation.deletions.isSubset(of: ledger.tombstones)
}

enum CloudRuleError: LocalizedError {
    case unavailable, accountChanged, conflict, ruleDeleted, reserved, interruptedRequired, notOwner, invalidLedger, tooLarge, journalPending, legacyAccountMismatch

    var errorDescription: String? {
        switch self {
        case .unavailable: L10n.text("iCloud 暫時不可用，請稍後再試。", "iCloud is temporarily unavailable. Try again later.")
        case .accountChanged: L10n.text("iCloud 帳號已變更。請重新載入規則。", "The iCloud account changed. Reload the rules.")
        case .conflict: L10n.text("另一台裝置已變更規則。請重新載入並確認後再試。", "Another device changed the rules. Reload and review before trying again.")
        case .ruleDeleted: L10n.text("這條規則已在其他裝置刪除，無法套用。", "This rule was deleted on another device and can no longer be applied.")
        case .reserved: L10n.text("這個範圍有待完成的操作。", "An operation in this scope is still pending.")
        case .interruptedRequired: L10n.text("只有因中斷而凍結的操作可以手動接手。", "Only a frozen interrupted operation can be taken over.")
        case .notOwner: L10n.text("這台裝置沒有此操作的寫入資格。", "This device no longer has write permission for this operation.")
        case .invalidLedger: L10n.text("無法驗證 iCloud 規則資料。行事曆未修改。", "The iCloud rule data could not be verified. Your calendar was not changed.")
        case .tooLarge: L10n.text("同步紀錄已達容量上限。行事曆未修改。", "The rule sync ledger is full. Your calendar was not changed.")
        case .journalPending: L10n.text("這台裝置還有尚未確認的操作。", "This device has an operation that has not yet been confirmed.")
        case .legacyAccountMismatch: L10n.text("這部裝置的舊規則已與另一個 iCloud 帳號連結。", "The older rules on this device belong to a different iCloud account.")
        }
    }
}

@MainActor protocol CloudRuleTransport {
    /// nil only when CloudKit explicitly reports there is no signed-in account.
    func accountID() async throws -> String?
    func fetch(accountID: String) async throws -> CloudRuleSession
    func compareAndSwap(_ ledger: CloudRuleLedger, from session: CloudRuleSession) async throws -> CloudRuleSession
}

#if DEBUG && targetEnvironment(simulator)
/// Development UI smoke uses a separate bundle ID and never connects to CloudKit.
@MainActor private final class SignedOutSmokeTransport: CloudRuleTransport {
    func accountID() async throws -> String? { nil }
    func fetch(accountID: String) async throws -> CloudRuleSession { throw CloudRuleError.unavailable }
    func compareAndSwap(_ ledger: CloudRuleLedger, from session: CloudRuleSession) async throws -> CloudRuleSession {
        throw CloudRuleError.unavailable
    }
}
#endif

@MainActor final class RuleCloudSync {
    private struct DeviceState: Codable {
        var deviceID = UUID()
        var migrationOwner: String?
        var migrated: Set<String> = []
        var journals: [String: CloudRuleJournal] = [:]
    }

    let transport: any CloudRuleTransport
    private let stateURL: URL
    private var state: DeviceState
    private var storeError: Error?
    private var activeOperations: Set<UUID> = []
    var deviceID: UUID { state.deviceID }

    init(transport: (any CloudRuleTransport)? = nil, stateURL: URL? = nil,
         environment: CloudRuleEnvironment = .current, stateDirectory: URL? = nil) {
        #if DEBUG && targetEnvironment(simulator)
        if Bundle.main.bundleIdentifier == "org.peiyu66.CalStitch.CloudSyncSmokeTest",
           ProcessInfo.processInfo.environment["CALSTITCH_SIGNED_OUT_SMOKE"] == "1" {
            self.transport = SignedOutSmokeTransport()
        } else {
            self.transport = transport ?? CloudKitRuleTransport()
        }
        #else
        self.transport = transport ?? CloudKitRuleTransport()
        #endif
        let directory = stateDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CalStitch", isDirectory: true)
        self.stateURL = stateURL ?? directory.appendingPathComponent(environment.localKey("cloud-state-v1.json"))
        do {
            let data = try Data(contentsOf: self.stateURL)
            self.state = try JSONDecoder().decode(DeviceState.self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            self.state = .init()
            do { try persist(self.state) } catch { self.storeError = error }
        } catch {
            self.state = .init()
            self.storeError = error
        }
    }

    private func persist(_ update: DeviceState) throws {
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(update).write(to: stateURL, options: .atomic)
        state = update
    }

    private func changeState(_ update: (inout DeviceState) -> Void) throws {
        if let storeError { throw storeError }
        var draft = state
        update(&draft)
        try persist(draft)
    }

    func refresh() async throws -> CloudRuleSession? {
        if let storeError { throw storeError }
        guard let id = try await transport.accountID() else { return nil }
        return try await refresh(accountID: id)
    }

    private func refresh(accountID: String) async throws -> CloudRuleSession {
        let result = try await transport.fetch(accountID: accountID)
        guard result.accountID == accountID, try await transport.accountID() == accountID else { throw CloudRuleError.accountChanged }
        try result.ledger.validate()
        return result
    }

    private func save(_ ledger: CloudRuleLedger, from session: CloudRuleSession) async throws -> CloudRuleSession {
        try ledger.validate()
        guard try await transport.accountID() == session.accountID else { throw CloudRuleError.accountChanged }
        let result = try await transport.compareAndSwap(ledger, from: session)
        guard result.accountID == session.accountID, try await transport.accountID() == session.accountID else { throw CloudRuleError.accountChanged }
        try result.ledger.validate()
        return result
    }

    func hasMigratedLegacy(in session: CloudRuleSession) -> Bool {
        state.migrated.contains(session.accountID)
    }

    var hasLegacyMigrationOwner: Bool { state.migrationOwner != nil }

    func canMigrateLegacy(in session: CloudRuleSession) -> Bool {
        state.migrationOwner.map { $0 == session.accountID } ?? true
    }

    func migrate(_ legacy: [CloudRuleEnvelope], in session: CloudRuleSession) async throws -> CloudRuleSession {
        let account = session.accountID
        if state.migrated.contains(account) || legacy.isEmpty { return session }
        if let owner = state.migrationOwner, owner != account { throw CloudRuleError.legacyAccountMismatch }
        // Account ownership must be persisted before the first external write, including lost acknowledgments.
        try changeState { $0.migrationOwner = account }
        var current = session
        for attempt in 0...2 {
            var next = current.ledger
            var seen = Set(next.rules.map(\.id)).union(next.tombstones)
            var added = false
            for var entry in legacy where seen.insert(entry.id).inserted {
                guard !next.pending.contains(where: { $0.scope.contains(entry.id) }) else { throw CloudRuleError.reserved }
                entry.sanitize()
                next.rules.append(entry)
                added = true
            }
            do {
                let saved = added ? try await save(next, from: current) : try await refresh(accountID: account)
                let confirmed = Set(saved.ledger.rules.map(\.id)).union(saved.ledger.tombstones)
                guard Set(legacy.map(\.id)).isSubset(of: confirmed) else { throw CloudRuleError.conflict }
                try changeState { $0.migrated.insert(account) }
                return saved
            } catch CloudRuleError.conflict where attempt < 2 {
                current = try await refresh(accountID: account)
            }
        }
        throw CloudRuleError.conflict
    }

    func recoverableJournal(in session: CloudRuleSession) -> CloudRuleJournal? {
        guard let journal = state.journals[session.accountID], !activeOperations.contains(journal.operation.id) else { return nil }
        return journal
    }

    func endLocalExecution(_ operationID: UUID) {
        activeOperations.remove(operationID)
    }

    func claim(_ operation: CloudRuleOperation, localBefore: [PlannedOccurrence], localAfter: [PlannedOccurrence],
               localPlan: Data? = nil, in session: CloudRuleSession) async throws -> CloudRuleSession {
        guard operation.owner == deviceID, !operation.interrupted else { throw CloudRuleError.notOwner }
        guard state.journals[session.accountID] == nil else { throw CloudRuleError.journalPending }
        guard session.ledger.pending.allSatisfy({ $0.scope.isDisjoint(with: operation.scope) }) else { throw CloudRuleError.reserved }
        guard Set(operation.upserts.map(\.id)).isDisjoint(with: session.ledger.tombstones) else { throw CloudRuleError.ruleDeleted }
        var portable = operation
        portable.sanitize()
        var next = session.ledger
        next.pending.append(portable)
        try next.validate()
        try changeState { $0.journals[session.accountID] = .init(operation: portable, localBefore: localBefore, localAfter: localAfter, localPlan: localPlan,
                 baseVersion: session.version, baseChangeTag: session.changeTag) }
        activeOperations.insert(portable.id)
        return try await authorize(portable, next: next, in: session)
    }

    private func authorize(_ operation: CloudRuleOperation, next: CloudRuleLedger, in session: CloudRuleSession) async throws -> CloudRuleSession {
        do {
            let saved = try await save(next, from: session)
            try changeState { $0.journals[session.accountID]?.stage = .authorized }
            return saved
        } catch {
            // A response can be lost after the server accepted a write. Never authorize using the
            // failure itself; re-read the exact operation and owner before committing to EventKit.
            let failure = error
            do {
                let observed = try await refresh(accountID: session.accountID)
                if observed.ledger.pendingOperation(operation.id) == operation {
                    try changeState { $0.journals[session.accountID]?.stage = .authorized }
                    return observed
                }
                if (observed.changeTag ?? "") == (session.changeTag ?? "") && (observed.changeTag != nil || observed.version == session.version) {
                    // A stable reread does not prove that an unacknowledged write cannot arrive later.
                    // Only an explicit rejected CAS can safely release the acquiring journal.
                    if let local = failure as? CloudRuleError, knownRejection(local) {
                        try changeState { $0.journals.removeValue(forKey: session.accountID) }
                    }
                } else if observed.ledger.pendingOperation(operation.id) == nil && !observed.ledger.completed.contains(operation.id) {
                    // The old version can no longer win a CAS.
                    try changeState { $0.journals.removeValue(forKey: session.accountID) }
                }
            } catch { /* keep the durable journal */ }
            activeOperations.remove(operation.id)
            throw failure
        }
    }

    private func knownRejection(_ error: CloudRuleError) -> Bool {
        switch error { case .conflict, .invalidLedger, .tooLarge: true; default: false }
    }

    /// Re-enter an acquiring journal from the exact base version. If another change superseded
    /// that base, the old request cannot be accepted and the unapplied journal may be retired.
    func resolveAcquiringJournal(in session: CloudRuleSession) async throws -> CloudRuleSession {
        guard let local = recoverableJournal(in: session), local.stage == .acquiring else { return session }
        let observed = try await refresh(accountID: session.accountID)
        let operation = local.operation
        if let remote = observed.ledger.pendingOperation(operation.id), remote == operation {
            try changeState { $0.journals[session.accountID]?.stage = .authorized }
            return observed
        }
        if observed.ledger.completed.contains(operation.id) {
            try changeState { $0.journals.removeValue(forKey: session.accountID) }
            return observed
        }
        let sameVersion = local.baseChangeTag.map { $0 == observed.changeTag }
            ?? (local.baseVersion == observed.version)
        if !sameVersion {
            try changeState { $0.journals.removeValue(forKey: session.accountID) }
            return observed
        }
        var next = observed.ledger
        if local.isTakeover {
            guard let index = next.pending.firstIndex(where: { $0.id == operation.id && $0.interrupted }) else {
                throw CloudRuleError.notOwner
            }
            next.pending[index] = operation
        } else {
            guard next.pending.allSatisfy({ $0.scope.isDisjoint(with: operation.scope) }) else {
                throw CloudRuleError.reserved
            }
            next.pending.append(operation)
        }
        activeOperations.insert(operation.id)
        defer { activeOperations.remove(operation.id) }
        return try await authorize(operation, next: next, in: observed)
    }

    /// Verify on the server immediately before touching EventKit (especially after reopening).
    func verifyOwnership(_ operationID: UUID, in session: CloudRuleSession) async throws -> CloudRuleSession {
        let observed = try await refresh(accountID: session.accountID)
        guard let operation = observed.ledger.pendingOperation(operationID), operation.owner == deviceID, !operation.interrupted else {
            throw CloudRuleError.notOwner
        }
        return observed
    }

    func recordEventKitComplete(_ operationID: UUID, in session: CloudRuleSession) throws {
        guard let journal = state.journals[session.accountID], journal.operation.id == operationID,
              journal.stage == .authorized || journal.stage == .eventKitComplete,
              let pending = session.ledger.pendingOperation(operationID), pending.owner == deviceID,
              !pending.interrupted else { throw CloudRuleError.notOwner }
        try changeState { $0.journals[session.accountID]?.stage = .eventKitComplete }
    }

    /// Idempotent only after the caller has verified the EventKit effects and persisted that checkpoint.
    func finish(_ operationID: UUID, in session: CloudRuleSession) async throws -> CloudRuleSession {
        defer { activeOperations.remove(operationID) }
        let account = session.accountID
        var latest = try await refresh(accountID: account)
        for attempt in 0...2 {
            if latest.ledger.completed.contains(operationID) {
                if state.journals[account]?.operation.id == operationID {
                    try changeState { $0.journals.removeValue(forKey: account) }
                }
                return latest
            }
            guard let operation = latest.ledger.pendingOperation(operationID), operation.owner == deviceID,
                  !operation.interrupted, state.journals[account]?.operation.id == operationID,
                  state.journals[account]?.stage == .eventKitComplete else { throw CloudRuleError.notOwner }
            var next = latest.ledger
            let replacements = Dictionary(uniqueKeysWithValues: operation.upserts.map { ($0.id, $0) })
            let existed = Set(next.rules.map(\.id))
            next.rules = next.rules.filter { !operation.deletions.contains($0.id) }.map { replacements[$0.id] ?? $0 }
            next.rules += operation.upserts.filter { !existed.contains($0.id) }
            next.tombstones.formUnion(operation.deletions)
            next.pending.removeAll { $0.id == operationID }
            next.completed.insert(operationID)
            do {
                let saved = try await save(next, from: latest)
                try changeState { $0.journals.removeValue(forKey: account) }
                return saved
            } catch {
                let first = error
                latest = try await refresh(accountID: account)
                if latest.ledger.completed.contains(operationID) {
                    try changeState { $0.journals.removeValue(forKey: account) }
                    return latest
                }
                if attempt == 2 || !(first is CloudRuleError) { throw first }
            }
        }
        throw CloudRuleError.conflict
    }

    /// May be called only after the application has positively established an interruption.
    /// Merely observing another device's pending record is not evidence of interruption.
    func markInterrupted(_ operationID: UUID, in session: CloudRuleSession) async throws -> CloudRuleSession {
        guard !activeOperations.contains(operationID), let index = session.ledger.pending.firstIndex(where: { $0.id == operationID }) else {
            throw CloudRuleError.reserved
        }
        var next = session.ledger
        guard next.pending[index].owner == deviceID else { throw CloudRuleError.notOwner }
        next.pending[index].interrupted = true
        return try await save(next, from: session)
    }

    /// Caller positively confirms the original device stopped, and independently previews the correct destination.
    /// Reuses the same operation ID; caller may intentionally change desired dates using preserved drafts.
    func takeOver(_ replacement: CloudRuleOperation, localBefore: [PlannedOccurrence], localAfter: [PlannedOccurrence],
                  localPlan: Data? = nil, in session: CloudRuleSession) async throws -> CloudRuleSession {
        guard let index = session.ledger.pending.firstIndex(where: { $0.id == replacement.id }),
              session.ledger.pending[index].interrupted else { throw CloudRuleError.interruptedRequired }
        guard replacement.scope == session.ledger.pending[index].scope, replacement.owner == deviceID,
              !replacement.interrupted, !activeOperations.contains(replacement.id) else { throw CloudRuleError.notOwner }
        guard state.journals[session.accountID].map({ $0.operation.id == replacement.id }) ?? true else {
            throw CloudRuleError.journalPending
        }
        var portable = replacement
        portable.sanitize()
        var next = session.ledger
        next.pending[index] = portable
        try next.validate()
        try changeState { $0.journals[session.accountID] = .init(operation: portable, localBefore: localBefore, localAfter: localAfter, localPlan: localPlan,
                 baseVersion: session.version, baseChangeTag: session.changeTag, isTakeover: true) }
        activeOperations.insert(portable.id)
        return try await authorize(portable, next: next, in: session)
    }

    /// Explicitly discard a superseded local journal only when current cloud ownership is clear.
    func clearSupersededJournal(in session: CloudRuleSession) throws {
        guard let local = recoverableJournal(in: session) else { return }
        let id = local.operation.id
        guard session.ledger.completed.contains(id)
                || (session.ledger.pendingOperation(id).map { $0.owner != deviceID } ?? false) else { return }
        try changeState { $0.journals.removeValue(forKey: session.accountID) }
    }
}

@MainActor final class CloudKitRuleTransport: CloudRuleTransport {
    static let containerIdentifier = "iCloud.org.peiyu66.CalStitch"
    static let maxLedgerBytes = 16 * 1024 * 1024
    private let recordID = CKRecord.ID(recordName: "CalStitchRules-v1")
    private lazy var container = CKContainer(identifier: Self.containerIdentifier)
    private var database: CKDatabase { container.privateCloudDatabase }

    func accountID() async throws -> String? {
        switch try await container.accountStatus() {
        case .noAccount: return nil
        case .available: return try await container.userRecordID().recordName
        default: throw CloudRuleError.unavailable
        }
    }

    func fetch(accountID: String) async throws -> CloudRuleSession {
        let record: CKRecord
        do { record = try await database.record(for: recordID) }
        catch let error as CKError where error.code == .unknownItem {
            return .init(accountID: accountID, version: nil, ledger: .init())
        }
        guard let url = (record["ledger"] as? CKAsset)?.fileURL else { throw CloudRuleError.invalidLedger }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard let size, size <= Self.maxLedgerBytes else { throw CloudRuleError.tooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= Self.maxLedgerBytes else { throw CloudRuleError.tooLarge }
        let ledger = try JSONDecoder().decode(CloudRuleLedger.self, from: data)
        return .init(accountID: accountID, version: systemFields(record), ledger: ledger, changeTag: record.recordChangeTag)
    }

    func compareAndSwap(_ ledger: CloudRuleLedger, from session: CloudRuleSession) async throws -> CloudRuleSession {
        let record: CKRecord
        if let version = session.version {
            let decoder = try NSKeyedUnarchiver(forReadingFrom: version)
            decoder.requiresSecureCoding = true
            guard let restored = CKRecord(coder: decoder), restored.recordID == recordID else { throw CloudRuleError.invalidLedger }
            decoder.finishDecoding()
            record = restored
        } else {
            record = CKRecord(recordType: "CalStitchRuleLedger", recordID: recordID)
        }
        let data = try JSONEncoder().encode(ledger)
        guard data.count <= Self.maxLedgerBytes else { throw CloudRuleError.tooLarge }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("calstitch-ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        record["ledger"] = CKAsset(fileURL: temporary)
        do {
            let (saved, _) = try await database.modifyRecords(saving: [record], deleting: [],
                savePolicy: .ifServerRecordUnchanged, atomically: true)
            guard let result = saved[recordID] else { throw CloudRuleError.unavailable }
            let confirmed = try result.get()
            return .init(accountID: session.accountID, version: systemFields(confirmed), ledger: ledger, changeTag: confirmed.recordChangeTag)
        } catch let error as CKError {
            if error.code == .serverRecordChanged
                || (error.partialErrorsByItemID?[recordID] as? CKError)?.code == .serverRecordChanged {
                throw CloudRuleError.conflict
            }
            throw error
        }
    }

    private func systemFields(_ record: CKRecord) -> Data {
        let encoder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: encoder)
        encoder.finishEncoding()
        return encoder.encodedData
    }
}
