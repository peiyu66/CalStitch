import Combine
import EventKit
import Foundation

struct CalendarDestination: Identifiable, Hashable {
    let id: String
    let title: String
    let sourceTitle: String
    let isWritable: Bool

    var displayTitle: String { sourceTitle.isEmpty ? title : "\(title) · \(sourceTitle)" }
}

struct CalendarChange: Identifiable {
    let id: String
    let verb: String
    let title: String
    let date: Date
}

struct CalendarPreviewEvent: Identifiable {
    enum Kind: Equatable { case unchanged, insert, update, remove }

    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let isPast: Bool
    let kind: Kind
    var previousStart: Date? = nil
    var previousEnd: Date? = nil
    var previousIsAllDay: Bool? = nil
}


struct CalendarRemovalEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarID: String
    let calendarTitle: String
    let timeZoneIdentifier: String?
    fileprivate let itemIdentifier: String
    fileprivate let eventIdentifier: String?
    fileprivate let notes: String?
    fileprivate let rawTitle: String?
    fileprivate let rawStart: Date
    fileprivate let rawEnd: Date
    fileprivate let lastModified: Date?
}

struct CalendarOrphanEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let isPast: Bool
    let calendarID: String
    let calendarTitle: String
    fileprivate let eventIdentifier: String?
    fileprivate let markerIdentity: String
    fileprivate let notes: String
    fileprivate let rawStart: Date
    fileprivate let rawEnd: Date
    fileprivate let lastModified: Date?
}

struct CalendarOrphanPreview {
    let start: Date
    let through: Date
    let events: [CalendarOrphanEvent]
    fileprivate let endExclusive: Date
    fileprivate let existingRuleIDs: Set<UUID>
}


enum CalendarIntegrationError: LocalizedError {
    case denied, noLocalSource, noDestination, readOnlyDestination, conflictingDestination
    case invalidPlan, ambiguousEvent, missingEvent, excessiveRange
    case writeFailed, orphanSelectionChanged, removalSelectionChanged

    var errorDescription: String? {
        switch self {
        case .denied: return L10n.text("請在設定中允許 CalStitch 完整存取行事曆，才能核對及維護事件。", "Allow CalStitch full calendar access in Settings so it can verify and maintain events.")
        case .noLocalSource: return L10n.text("找不到模擬器的本機行事曆來源，未寫入任何帳戶。", "The simulator’s local calendar source could not be found. Nothing was written to any account.")
        case .noDestination: return L10n.text("找不到指定的行事曆，未改動任何事件。", "The selected calendar could not be found. No events were changed.")
        case .readOnlyDestination: return L10n.text("指定的行事曆目前唯讀，未改動任何事件。", "The selected calendar is read-only. No events were changed.")
        case .conflictingDestination: return L10n.text("已有同名的本機日曆，但無法確認由 CalStitch 建立，未使用它。", "A local calendar already has this name, but CalStitch could not confirm it created that calendar. It was not used.")
        case .invalidPlan: return L10n.text("遇到無法辨認的規則或事件資料；未改動行事曆。", "CalStitch could not verify the rule or event data. No calendar changes were made.")
        case .ambiguousEvent: return L10n.text("找到重複或有衝突的事件識別，無法安全更新；未改動行事曆。", "Duplicate or conflicting event identifiers were found. No calendar changes were made.")
        case .missingEvent: return L10n.text("找不到先前套用的未來事件，可能已被移動、刪除或移除識別附註；未改動行事曆。", "A previously applied future event could not be found. It may have been moved or deleted, or its identifying note may have been removed. No calendar changes were made.")
        case .excessiveRange: return L10n.text("日期範圍太長，無法安全核對，請縮短維護期間。", "The date range is too long to verify safely. Shorten the repeat period and try again.")
        case .orphanSelectionChanged: return L10n.text("行事曆或規則已變動。未刪除事件，請重新掃描並確認選擇。", "The calendar or rules have changed. No events were deleted. Scan again and confirm your selection.")
        case .removalSelectionChanged: return L10n.text("待移除的事件已變動。未刪除事件，請重新檢視預覽。", "The events to remove have changed. No events were deleted. Review the preview again.")
        case .writeFailed: return L10n.text("行事曆未能確認儲存結果。請先檢查行事曆，再重新開啟 CalStitch。", "The calendar could not confirm that the changes were saved. Check your calendar before reopening CalStitch.")
        }
    }
}

@MainActor
final class CalendarIntegration: ObservableObject {
    @Published private(set) var destinations: [CalendarDestination] = []
    var hasFullAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    private let store = EKEventStore()
    private let defaults: UserDefaults
    private static let destinationKey = "CalStitch.dedicatedLocalCalendar.v1"
    private static let calendarTitle = "CalStitch"

    private struct Identity: Hashable {
        let rule: UUID
        let occurrence: String

        var marker: String { "[CalStitch:v1 rule=\(rule.uuidString) occurrence=\(occurrence)]" }
        var displayID: String { "\(rule.uuidString)/\(occurrence)" }

        init(rule: UUID, occurrence: String) {
            self.rule = rule
            self.occurrence = occurrence
        }

        init?(line: Substring) {
            let prefix = "[CalStitch:v1 rule="
            let separator = " occurrence="
            guard line.hasPrefix(prefix), line.hasSuffix("]") else { return nil }
            let fields = line.dropFirst(prefix.count).dropLast()
            guard let split = fields.range(of: separator) else { return nil }
            let uuid = String(fields[..<split.lowerBound])
            let key = String(fields[split.upperBound...])
            guard uuid.utf8.count == 36, let id = UUID(uuidString: uuid), Self.valid(key) else { return nil }
            self.init(rule: id, occurrence: key)
        }

        static func valid(_ key: String) -> Bool {
            !key.isEmpty && key.utf8.count <= 96 && key.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) ||
                $0 == 45 || $0 == 95 || $0 == 46 || $0 == 58
            }
        }
    }

    private enum Operation {
        case insert(Identity, PlannedOccurrence)
        case update(Identity, EKEvent, PlannedOccurrence)
        case remove(Identity, EKEvent)

        var change: CalendarChange {
            switch self {
            case let .insert(identity, value):
                return CalendarChange(id: identity.displayID, verb: L10n.text("新增", "Add"), title: value.title, date: value.start)
            case let .update(identity, _, value):
                return CalendarChange(id: identity.displayID, verb: L10n.text("更新", "Update"), title: value.title, date: value.start)
            case let .remove(identity, value):
                return CalendarChange(id: identity.displayID, verb: L10n.text("移除", "Remove"), title: value.title ?? L10n.text("無標題", "Untitled"), date: value.startDate)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refreshCalendars()
    }

    func refreshCalendars() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            destinations = []
            return
        }
        // Refresh the EventKit cache after account or calendar changes outside this app.
        store.reset()
        #if targetEnvironment(simulator)
        if let id = defaults.string(forKey: Self.destinationKey),
           let calendar = store.calendar(withIdentifier: id), Self.isLocalWritable(calendar) {
            destinations = [Self.destination(calendar)]
        } else {
            destinations = []
        }
        #else
        destinations = store.calendars(for: .event).map(Self.destination).sorted {
            if $0.isWritable != $1.isWritable { return $0.isWritable }
            let order = $0.displayTitle.localizedStandardCompare($1.displayTitle)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        #endif
    }

    func connectLocalCalendar() async throws {
        try await connectCalendars()
    }

    func connectCalendars() async throws {
        if !hasFullAccess {
            guard try await store.requestFullAccessToEvents(), hasFullAccess else {
                destinations = []
                throw CalendarIntegrationError.denied
            }
        }

        #if targetEnvironment(simulator)
        if let remembered = defaults.string(forKey: Self.destinationKey) {
            guard let calendar = store.calendar(withIdentifier: remembered), Self.isLocalWritable(calendar) else {
                destinations = []
                throw CalendarIntegrationError.noDestination
            }
        } else {
            guard let source = store.sources.first(where: { $0.sourceType == .local }) else {
                throw CalendarIntegrationError.noLocalSource
            }
            guard !source.calendars(for: .event).contains(where: { $0.title == Self.calendarTitle }) else {
                throw CalendarIntegrationError.conflictingDestination
            }
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = Self.calendarTitle
            calendar.source = source
            do {
                try store.saveCalendar(calendar, commit: true)
            } catch {
                store.reset()
                throw CalendarIntegrationError.writeFailed
            }
            let id = calendar.calendarIdentifier
            guard let saved = store.calendar(withIdentifier: id), Self.isLocalWritable(saved) else {
                throw CalendarIntegrationError.noDestination
            }
            defaults.set(id, forKey: Self.destinationKey)
        }
        #endif

        refreshCalendars()
    }

    private static func destination(_ calendar: EKCalendar) -> CalendarDestination {
        let source = calendar.source
        let sourceTitle: String
        switch source?.sourceType {
        case .local: sourceTitle = L10n.text("本機", "On This Device")
        case .birthdays: sourceTitle = L10n.text("生日", "Birthdays")
        case .subscribed: sourceTitle = source?.title ?? L10n.text("訂閱", "Subscriptions")
        default: sourceTitle = source?.title ?? ""
        }
        return .init(id: calendar.calendarIdentifier, title: calendar.title, sourceTitle: sourceTitle,
                     isWritable: isWritable(calendar))
    }

    private struct Reconciliation {
        var operations: [Operation]
        var snapshot: [PlannedOccurrence]
        var calendars: [String: EKCalendar] = [:]
        var previewEvents: [CalendarPreviewEvent] = []
    }

    func previewEvents(for ruleID: UUID, desired: [PlannedOccurrence], previous: [PlannedOccurrence]) throws -> [CalendarPreviewEvent] {
        let scope: Set<UUID> = [ruleID]
        return try reconcile(desired: desired.filter { scope.contains($0.ruleID) },
                             previous: previous.filter { scope.contains($0.ruleID) },
                             ruleIDs: scope, now: .now, includingEvents: true).previewEvents
    }

    func existingPreviewEvents(for ruleID: UUID, previous: [PlannedOccurrence]) throws -> [CalendarPreviewEvent] {
        let previous = previous.filter { $0.ruleID == ruleID }
        guard let id = previous.first?.calendarID else { return [] }
        guard hasFullAccess else { throw CalendarIntegrationError.denied }
        guard !id.isEmpty, let calendar = store.calendar(withIdentifier: id) else {
            throw CalendarIntegrationError.noDestination
        }
        #if targetEnvironment(simulator)
        guard defaults.string(forKey: Self.destinationKey) == id, calendar.source?.sourceType == .local else {
            throw CalendarIntegrationError.noDestination
        }
        #endif
        let known = try table(previous, calendarID: id, ruleIDs: [ruleID])
        guard let first = previous.map({ storageDate($0.start, allDay: $0.isAllDay) }).min(),
              let last = previous.map({ storageDate($0.end, allDay: $0.isAllDay) }).max() else { return [] }
        // Live rows are filtered by the known snapshot; a missing occurrence isn't
        // fabricated. Conflicting markers still fail closed rather than guessing.
        let found = try findEvents(from: first, through: last, calendar: calendar, ruleIDs: [ruleID])
            .filter { known[$0.key] != nil }
        return makePreviewEvents(found: found, operations: [], now: .now)
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    func preview(desired: [PlannedOccurrence], previous: [PlannedOccurrence], ruleIDs: Set<UUID>) throws -> [CalendarChange] {
        try reconcile(desired: desired, previous: previous, ruleIDs: ruleIDs, now: .now).operations.map(\.change)
    }

    func previewRemoval(previous: [PlannedOccurrence], ruleIDs: Set<UUID>) throws -> [CalendarRemovalEvent] {
        store.reset()
        return try removalEvents(in: reconcile(desired: [], previous: previous, ruleIDs: ruleIDs, now: .now))
    }

    func applyRemoval(previous: [PlannedOccurrence], ruleIDs: Set<UUID>, matching expected: [CalendarRemovalEvent]) throws {
        store.reset()
        let current = try reconcile(desired: [], previous: previous, ruleIDs: ruleIDs, now: .now)
        guard try removalEvents(in: current) == expected else {
            throw CalendarIntegrationError.removalSelectionChanged
        }
        // Commit the exact objects verified in this reconciliation, not a second plan.
        _ = try apply(current)
    }

    private func removalEvents(in reconciliation: Reconciliation) throws -> [CalendarRemovalEvent] {
        let rows = try reconciliation.operations.map { operation -> CalendarRemovalEvent in
            guard case let .remove(identity, event) = operation,
                  let calendar = event.calendar, let start = event.startDate, let end = event.endDate else {
                throw CalendarIntegrationError.invalidPlan
            }
            return .init(id: identity.displayID, title: event.title ?? L10n.text("無標題", "Untitled"),
                         start: plannedDate(start, allDay: event.isAllDay),
                         end: plannedEndDate(end, allDay: event.isAllDay), isAllDay: event.isAllDay,
                         calendarID: calendar.calendarIdentifier, calendarTitle: Self.destination(calendar).displayTitle,
                         timeZoneIdentifier: event.timeZone?.identifier, itemIdentifier: event.calendarItemIdentifier,
                         eventIdentifier: event.eventIdentifier, notes: event.notes, rawTitle: event.title,
                         rawStart: start, rawEnd: end, lastModified: event.lastModifiedDate)
        }
        return rows.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    @discardableResult
    func apply(desired: [PlannedOccurrence], previous: [PlannedOccurrence], ruleIDs: Set<UUID>) throws -> [PlannedOccurrence] {
        try apply(reconcile(desired: desired, previous: previous, ruleIDs: ruleIDs, now: .now))
    }

    private func apply(_ reconciliation: Reconciliation) throws -> [PlannedOccurrence] {
        guard !reconciliation.operations.isEmpty else { return reconciliation.snapshot }
        do {
            for operation in reconciliation.operations {
                switch operation {
                case let .insert(identity, occurrence):
                    guard let calendar = reconciliation.calendars[occurrence.calendarID] else {
                        throw CalendarIntegrationError.invalidPlan
                    }
                    let event = EKEvent(eventStore: store)
                    event.calendar = calendar
                    event.notes = "\n\n----\n\n" + identity.marker
                    configure(event, with: occurrence)
                    try store.save(event, span: .thisEvent, commit: false)
                case let .update(_, event, occurrence):
                    // Leave existing notes untouched, including prose around our exact marker.
                    configure(event, with: occurrence)
                    try store.save(event, span: .thisEvent, commit: false)
                case let .remove(_, event):
                    try store.remove(event, span: .thisEvent, commit: false)
                }
            }
            try store.commit()
            return reconciliation.snapshot
        } catch {
            store.reset()
            throw CalendarIntegrationError.writeFailed
        }
    }

    func previewOrphans(existingRuleIDs: Set<UUID>) throws -> CalendarOrphanPreview {
        let now = Date.now
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .year, value: -5, to: today),
              let through = calendar.date(byAdding: .year, value: 10, to: today),
              let endExclusive = calendar.date(byAdding: .day, value: 1, to: through) else {
            throw CalendarIntegrationError.invalidPlan
        }
        let candidates = try scanOrphans(start: start, endExclusive: endExclusive, existingRuleIDs: existingRuleIDs, now: now)
        let events = candidates.values.map(\.info).sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id < $1.id
        }
        return .init(start: start, through: through, events: events,
                     endExclusive: endExclusive, existingRuleIDs: existingRuleIDs)
    }

    func removeOrphans(_ selected: [CalendarOrphanEvent], from preview: CalendarOrphanPreview,
                       existingRuleIDs: Set<UUID>) throws {
        guard !selected.isEmpty else { return }
        guard preview.existingRuleIDs == existingRuleIDs,
              Set(selected.map(\.id)).count == selected.count else {
            throw CalendarIntegrationError.orphanSelectionChanged
        }
        let displayed = Dictionary(uniqueKeysWithValues: preview.events.map { ($0.id, $0) })
        guard selected.allSatisfy({ displayed[$0.id] == $0 }) else {
            throw CalendarIntegrationError.orphanSelectionChanged
        }
        let current = try scanOrphans(start: preview.start, endExclusive: preview.endExclusive,
                                      existingRuleIDs: existingRuleIDs, now: .now)
        // Confirm all selected rows from the same fresh scan before staging any writes.
        let confirmed = try selected.map { item in
            guard let found = current[item.id], found.info == item else {
                throw CalendarIntegrationError.orphanSelectionChanged
            }
            return found.event
        }
        do {
            for event in confirmed {
                try store.remove(event, span: .thisEvent, commit: false)
            }
            try store.commit()
        } catch {
            store.reset()
            throw CalendarIntegrationError.writeFailed
        }
    }

    private struct OrphanCandidate {
        let event: EKEvent
        let info: CalendarOrphanEvent
    }

    private func scanOrphans(start: Date, endExclusive: Date, existingRuleIDs: Set<UUID>, now: Date) throws -> [String: OrphanCandidate] {
        guard hasFullAccess else { throw CalendarIntegrationError.denied }
        store.reset()
        #if targetEnvironment(simulator)
        let calendars = try defaults.string(forKey: Self.destinationKey).map { [try writableCalendar(id: $0)] } ?? []
        #else
        let calendars = store.calendars(for: .event).filter(Self.isWritable)
        #endif
        guard !calendars.isEmpty else { return [:] }
        let calendarByID = Dictionary(uniqueKeysWithValues: calendars.map { ($0.calendarIdentifier, $0) })
        let chunk: TimeInterval = 365 * 3 * 86_400
        var cursor = start
        var seenOccurrences: Set<String> = []
        var candidates: [Identity: OrphanCandidate] = [:]
        var conflicting: Set<Identity> = []
        while cursor < endExclusive {
            let bound = min(endExclusive, cursor.addingTimeInterval(chunk))
            let predicate = store.predicateForEvents(withStart: cursor, end: bound, calendars: calendars)
            for event in store.events(matching: predicate) {
                guard let eventCalendar = event.calendar,
                      let calendar = calendarByID[eventCalendar.calendarIdentifier],
                      let rawStart = event.startDate, let rawEnd = event.endDate,
                      rawStart >= start, rawStart < endExclusive,
                      let notes = event.notes else { continue }
                let calendarID = calendar.calendarIdentifier
                let itemID = event.calendarItemIdentifier
                let key = "\(calendarID.utf8.count):\(calendarID)\(itemID.utf8.count):\(itemID):\(rawStart.timeIntervalSinceReferenceDate)"
                guard seenOccurrences.insert(key).inserted else { continue }
                let tagLines = notes.split(whereSeparator: \.isNewline).filter {
                    $0.trimmingCharacters(in: .whitespaces).hasPrefix("[CalStitch:")
                }
                let markers = tagLines.compactMap(Identity.init(line:))
                let missing = markers.filter { !existingRuleIDs.contains($0.rule) }
                guard !missing.isEmpty else { continue }

                // A duplicate or a conflicting/malformed marker taints that identity even
                // when one matching event is ineligible for listing for another reason.
                guard tagLines.count == 1, let identity = missing.first,
                      !event.hasRecurrenceRules, !event.isDetached,
                      rawStart > now || rawEnd <= now else {
                    conflicting.formUnion(missing)
                    continue
                }
                if candidates[identity] != nil {
                    conflicting.insert(identity)
                    continue
                }
                let info = CalendarOrphanEvent(
                    id: key, title: event.title ?? L10n.text("無標題", "Untitled"),
                    start: plannedDate(rawStart, allDay: event.isAllDay),
                    end: plannedEndDate(rawEnd, allDay: event.isAllDay),
                    isAllDay: event.isAllDay, isPast: rawEnd <= now,
                    calendarID: calendarID, calendarTitle: Self.destination(calendar).displayTitle,
                    eventIdentifier: event.eventIdentifier, markerIdentity: identity.displayID,
                    notes: notes, rawStart: rawStart, rawEnd: rawEnd, lastModified: event.lastModifiedDate
                )
                candidates[identity] = .init(event: event, info: info)
            }
            cursor = bound
        }
        return Dictionary(uniqueKeysWithValues: candidates.filter { !conflicting.contains($0.key) }.values.map {
            ($0.info.id, $0)
        })
    }

    private func writableCalendar(id: String) throws -> EKCalendar {
        guard !id.isEmpty, let calendar = store.calendar(withIdentifier: id) else {
            throw CalendarIntegrationError.noDestination
        }
        #if targetEnvironment(simulator)
        guard defaults.string(forKey: Self.destinationKey) == id, Self.isLocalWritable(calendar) else {
            throw CalendarIntegrationError.noDestination
        }
        #else
        guard Self.isWritable(calendar) else { throw CalendarIntegrationError.readOnlyDestination }
        #endif
        return calendar
    }

    private static func isWritable(_ calendar: EKCalendar) -> Bool {
        calendar.allowsContentModifications && calendar.source != nil &&
            calendar.type != .birthday && calendar.type != .subscription
    }

    private static func isLocalWritable(_ calendar: EKCalendar) -> Bool {
        calendar.source?.sourceType == .local && calendar.type == .local && isWritable(calendar)
    }

    private func table(_ values: [PlannedOccurrence], calendarID: String, ruleIDs: Set<UUID>) throws -> [Identity: PlannedOccurrence] {
        var result: [Identity: PlannedOccurrence] = [:]
        for occurrence in values {
            guard occurrence.calendarID == calendarID, ruleIDs.contains(occurrence.ruleID),
                  Identity.valid(occurrence.key), occurrence.end > occurrence.start else {
                throw CalendarIntegrationError.invalidPlan
            }
            let identity = Identity(rule: occurrence.ruleID, occurrence: occurrence.key)
            guard result.updateValue(occurrence, forKey: identity) == nil else {
                throw CalendarIntegrationError.invalidPlan
            }
        }
        return result
    }

    private func reconcile(desired: [PlannedOccurrence], previous: [PlannedOccurrence], ruleIDs: Set<UUID>, now: Date, includingEvents: Bool = false) throws -> Reconciliation {
        let all = desired + previous
        guard !all.isEmpty else { return .init(operations: [], snapshot: []) }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            destinations = []
            throw CalendarIntegrationError.denied
        }

        var targetByRule: [UUID: String] = [:]
        for occurrence in all {
            guard ruleIDs.contains(occurrence.ruleID) else { throw CalendarIntegrationError.invalidPlan }
            // Moving an already-managed rule between calendars requires a separate explicit migration.
            if let known = targetByRule[occurrence.ruleID], known != occurrence.calendarID {
                throw CalendarIntegrationError.invalidPlan
            }
            targetByRule[occurrence.ruleID] = occurrence.calendarID
        }
        let wantedGroups = Dictionary(grouping: desired, by: \.calendarID)
        let priorGroups = Dictionary(grouping: previous, by: \.calendarID)
        var destinationGroups: [String: Set<UUID>] = [:]
        for (ruleID, target) in targetByRule {
            destinationGroups[target, default: []].insert(ruleID)
        }
        var batch = Reconciliation(operations: [], snapshot: [])
        for id in destinationGroups.keys.sorted() {
            let calendar = try writableCalendar(id: id)
            let group = try reconcileCalendar(desired: wantedGroups[id] ?? [], previous: priorGroups[id] ?? [],
                                              ruleIDs: destinationGroups[id] ?? [], now: now, calendar: calendar, includingEvents: includingEvents)
            batch.calendars[id] = calendar
            batch.operations.append(contentsOf: group.operations)
            batch.snapshot.append(contentsOf: group.snapshot)
            batch.previewEvents.append(contentsOf: group.previewEvents)
        }
        batch.operations.sort {
            if $0.change.date == $1.change.date { return $0.change.id < $1.change.id }
            return $0.change.date < $1.change.date
        }
        batch.previewEvents.sort { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        return batch
    }

    private func reconcileCalendar(desired: [PlannedOccurrence], previous: [PlannedOccurrence], ruleIDs: Set<UUID>,
                                   now: Date, calendar: EKCalendar, includingEvents: Bool) throws -> Reconciliation {
        let wanted = try table(desired, calendarID: calendar.calendarIdentifier, ruleIDs: ruleIDs)
        let prior = try table(previous, calendarID: calendar.calendarIdentifier, ruleIDs: ruleIDs)
        let all = desired + previous
        guard let first = all.map({ storageDate($0.start, allDay: $0.isAllDay) }).min(),
              let last = all.map({ storageDate($0.end, allDay: $0.isAllDay) }).max() else { return .init(operations: [], snapshot: []) }
        let found = try findEvents(from: first, through: last, calendar: calendar, ruleIDs: ruleIDs)

        // A matching marker suffices to locate a candidate, not to claim an event
        // absent from the app's successful-apply snapshot.
        guard found.keys.allSatisfy({ prior[$0] != nil }) else {
            throw CalendarIntegrationError.ambiguousEvent
        }
        for (key, occurrence) in prior {
            if storageDate(occurrence.start, allDay: occurrence.isAllDay) > now && found[key] == nil {
                throw CalendarIntegrationError.missingEvent
            }
        }

        var operations: [Operation] = []
        var snapshot: [Identity: PlannedOccurrence] = [:]
        // The previous snapshot contains only actually managed rows. Retain already-started
        // keys as tombstones even when their new desired date is in the future.
        for (key, occurrence) in prior where storageDate(occurrence.start, allDay: occurrence.isAllDay) <= now {
            snapshot[key] = occurrence
        }
        for (key, event) in found where event.startDate <= now && snapshot[key] == nil {
            snapshot[key] = PlannedOccurrence(
                ruleID: key.rule, key: key.occurrence, title: event.title ?? "無標題",
                start: plannedDate(event.startDate, allDay: event.isAllDay),
                end: plannedEndDate(event.endDate, allDay: event.isAllDay),
                isAllDay: event.isAllDay, calendarID: calendar.calendarIdentifier
            )
        }

        for (key, occurrence) in wanted where snapshot[key] == nil {
            let start = storageDate(occurrence.start, allDay: occurrence.isAllDay)
            if let managed = found[key] {
                if start <= now {
                    operations.append(.remove(key, managed))
                    continue
                }
                if differs(managed, from: occurrence) {
                    operations.append(.update(key, managed, occurrence))
                }
                snapshot[key] = occurrence
            } else if start > now {
                operations.append(.insert(key, occurrence))
                snapshot[key] = occurrence
            }
        }
        for (key, event) in found where wanted[key] == nil && snapshot[key] == nil {
            operations.append(.remove(key, event))
        }

        operations.sort {
            if $0.change.date == $1.change.date { return $0.change.id < $1.change.id }
            return $0.change.date < $1.change.date
        }
        return .init(operations: operations, snapshot: snapshot.sorted { $0.key.displayID < $1.key.displayID }.map(\.value),
                     previewEvents: includingEvents ? makePreviewEvents(found: found, operations: operations, now: now) : [])
    }

    private func makePreviewEvents(found: [Identity: EKEvent], operations: [Operation], now: Date) -> [CalendarPreviewEvent] {
        // Reconciliation already checked exact target, matching marker and applied snapshot
        // for every event in found. Never synthesize a live record from the cached snapshot.
        func existing(_ identity: Identity, _ event: EKEvent, kind: CalendarPreviewEvent.Kind) -> CalendarPreviewEvent {
            .init(id: identity.displayID, title: event.title ?? L10n.text("無標題", "Untitled"),
                  start: plannedDate(event.startDate, allDay: event.isAllDay),
                  end: plannedEndDate(event.endDate, allDay: event.isAllDay),
                  isAllDay: event.isAllDay, isPast: event.endDate <= now, kind: kind)
        }

        var rows: [Identity: CalendarPreviewEvent] = [:]
        for (key, event) in found {
            rows[key] = existing(key, event, kind: .unchanged)
        }
        for operation in operations {
            switch operation {
            case let .insert(identity, occurrence):
                rows[identity] = .init(id: identity.displayID, title: occurrence.title, start: occurrence.start,
                                       end: occurrence.end, isAllDay: occurrence.isAllDay, isPast: false, kind: .insert)
            case let .update(identity, event, occurrence):
                let old = existing(identity, event, kind: .unchanged)
                rows[identity] = .init(id: identity.displayID, title: occurrence.title, start: occurrence.start,
                                       end: occurrence.end, isAllDay: occurrence.isAllDay, isPast: false, kind: .update,
                                       previousStart: old.start, previousEnd: old.end, previousIsAllDay: old.isAllDay)
            case let .remove(identity, event):
                rows[identity] = existing(identity, event, kind: .remove)
            }
        }
        return Array(rows.values)
    }

    private func findEvents(from first: Date, through last: Date, calendar: EKCalendar, ruleIDs: Set<UUID>) throws -> [Identity: EKEvent] {
        let day: TimeInterval = 86_400
        let margin = 366 * day
        let start = first.addingTimeInterval(-margin)
        let end = last.addingTimeInterval(margin)
        // EventKit restricts the length of each predicate; use smaller contiguous windows.
        let maximumWindow = 365 * 3 * day
        guard end.timeIntervalSince(start) <= 102 * 366 * day else {
            throw CalendarIntegrationError.excessiveRange
        }
        var cursor = start
        var seen = Set<String>()
        var result: [Identity: EKEvent] = [:]
        while cursor < end {
            let bound = min(end, cursor.addingTimeInterval(maximumWindow))
            let predicate = store.predicateForEvents(withStart: cursor, end: bound, calendars: [calendar])
            for event in store.events(matching: predicate) {
                guard event.calendar?.calendarIdentifier == calendar.calendarIdentifier else { continue }
                let notes = event.notes ?? ""
                let markers = notes.split(whereSeparator: \.isNewline).compactMap(Identity.init(line:))
                let affected = markers.filter { ruleIDs.contains($0.rule) }
                guard !affected.isEmpty else { continue }
                // An event may intersect two adjacent query windows. Its start distinguishes series occurrences.
                let distinct = "\(event.calendarItemIdentifier)/\(event.startDate.timeIntervalSinceReferenceDate)"
                guard seen.insert(distinct).inserted else { continue }
                guard markers.count == 1, !event.hasRecurrenceRules, !event.isDetached,
                      let key = affected.first, result[key] == nil else {
                    throw CalendarIntegrationError.ambiguousEvent
                }
                result[key] = event
            }
            cursor = bound
        }
        return result
    }

    private func storageDate(_ date: Date, allDay: Bool) -> Date {
        guard allDay else { return date }
        // An all-day EventKit event is a floating civil date, not midnight in a fixed UTC offset.
        var source = Calendar(identifier: .gregorian)
        source.timeZone = TimeZone(identifier: "Asia/Taipei")!
        var local = Calendar(identifier: .gregorian)
        local.timeZone = .current
        let components = source.dateComponents([.year, .month, .day], from: date)
        return local.date(from: components) ?? date
    }

    private func plannedDate(_ date: Date, allDay: Bool) -> Date {
        guard allDay else { return date }
        var local = Calendar(identifier: .gregorian)
        local.timeZone = .current
        var target = Calendar(identifier: .gregorian)
        target.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let components = local.dateComponents([.year, .month, .day], from: date)
        return target.date(from: components) ?? date
    }

    private func differs(_ event: EKEvent, from occurrence: PlannedOccurrence) -> Bool {
        if event.title != occurrence.title || event.isAllDay != occurrence.isAllDay { return true }
        if occurrence.isAllDay {
            return plannedDate(event.startDate, allDay: true) != occurrence.start ||
                plannedEndDate(event.endDate, allDay: true) != occurrence.end
        }
        return abs(event.startDate.timeIntervalSince(occurrence.start)) >= 1 ||
            abs(event.endDate.timeIntervalSince(occurrence.end)) >= 1
    }

    private func plannedEndDate(_ date: Date, allDay: Bool) -> Date {
        guard allDay else { return date }
        var local = Calendar(identifier: .gregorian)
        local.timeZone = .current
        let midnight = local.startOfDay(for: date)
        // Some EventKit sources read the last day as 23:59:59 rather than the next midnight.
        let exclusive = date == midnight ? date : (local.date(byAdding: .day, value: 1, to: midnight) ?? date)
        return plannedDate(exclusive, allDay: true)
    }

    private func configure(_ event: EKEvent, with occurrence: PlannedOccurrence) {
        event.title = occurrence.title
        event.isAllDay = occurrence.isAllDay
        event.timeZone = occurrence.isAllDay ? nil : (occurrence.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? RuleEngine.timeZone)
        event.startDate = storageDate(occurrence.start, allDay: occurrence.isAllDay)
        let exclusiveEnd = storageDate(occurrence.end, allDay: occurrence.isAllDay)
        // EventKit expands an all-day end to the end of the selected civil day.
        // Pass the final day instead of the app's exclusive boundary on the following day.
        event.endDate = occurrence.isAllDay ? exclusiveEnd.addingTimeInterval(-1) : exclusiveEnd
    }
}
