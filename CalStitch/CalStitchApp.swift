import SwiftUI
import CloudKit
import UIKit

@main
struct CalStitchApp: App {
    var body: some Scene {
        WindowGroup { RulesHome().environment(\.locale, L10n.locale) }
    }
}

private let slate = Color(red: 67/255, green: 88/255, blue: 119/255)

private func readableTint(light: UInt32, dark: UInt32) -> Color {
    Color(uiColor: UIColor { traits in
        let rgb = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                       green: CGFloat((rgb >> 8) & 255) / 255,
                       blue: CGFloat(rgb & 255) / 255, alpha: 1)
    })
}

let requiredFieldTint = readableTint(light: 0x995357, dark: 0xD79599)

private let paper = Color(uiColor: .systemGroupedBackground)
private let card = Color(uiColor: .secondarySystemGroupedBackground)

private func uniqueNames(_ names: [String]) -> [String] {
    var seen = Set<String>()
    return names.filter { seen.insert($0).inserted }
}

private func selectableCategories(_ existing: [String]) -> [String] {
    uniqueNames(["生日", "節日", "祭祀"] + existing.filter { !$0.isEmpty })
}

private let ruleZone = TimeZone(identifier: "Asia/Taipei") ?? .current
private var gregorianCalendar: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = ruleZone
    return cal
}
enum RuleKind: String, CaseIterable, Identifiable, Codable {
    case lunar = "農曆"
    case solar = "節氣"
    case gregorian = "西元"
    var id: Self { self }

    var displayLabel: String {
        switch self {
        case .lunar: L10n.text(rawValue, "Lunar")
        case .solar: L10n.text(rawValue, "Solar Term")
        case .gregorian: L10n.text(rawValue, "Gregorian")
        }
    }

    var symbol: String {
        switch self {
        case .lunar: "moon"
        case .solar: "sun.max"
        case .gregorian: "calendar"
        }
    }

    var subtitle: String {
        switch self {
        case .lunar: L10n.text("依農曆月日選擇基準日期", "Choose a date in the lunar calendar")
        case .solar: L10n.text("從二十四節氣選擇", "Choose one of the 24 solar terms")
        case .gregorian: L10n.text("依西元日期設定", "Choose a date in the Gregorian calendar")
        }
    }

    var dates: [String] {
        switch self {
        case .solar: SolarTerms.names
        case .lunar, .gregorian: []
        }
    }
}

enum PeriodUnit: String, CaseIterable, Identifiable, Codable {
    case year = "年", month = "月", week = "週", day = "日"
    var id: Self { self }

    func displayLabel(count: Int = 1) -> String {
        let english = switch self {
        case .year: "year"
        case .month: "month"
        case .week: "week"
        case .day: "day"
        }
        return L10n.text(rawValue, english + (count == 1 ? "" : "s"))
    }
}

enum EndMode: String, CaseIterable, Identifiable, Codable {
    case duration = "持續期間", date = "指定截止日期"
    var id: Self { self }
    var displayLabel: String { self == .duration ? L10n.text("重複期間", "Repeat Period") : L10n.text(rawValue, "Specific End Date") }
}

enum EventTiming: String, CaseIterable, Identifiable, Codable {
    case allDay = "整日", timed = "指定時間"
    var id: Self { self }
}

enum RelativePosition: String, CaseIterable, Identifiable, Codable {
    case before = "之前", same = "同一天", after = "之後"
    var id: Self { self }

    var displayLabel: String {
        switch self {
        case .before: L10n.text(rawValue, "Before")
        case .same: L10n.text(rawValue, "Same Day")
        case .after: L10n.text(rawValue, "After")
        }
    }
}

struct Rule: Hashable, Identifiable, Codable {
    var id = UUID()
    var name: String
    var kind: RuleKind
    var date: String
    var lunarMonth = 1
    var lunarDay = 1
    var lunarIsLeap = false
    var includeLeapMonths: Bool? = nil
    var category: String
    var subcategory: String = ""
    var parent: UUID? = nil
    var period: PeriodUnit = .year
    var interval: Int = 1
    var start = gregorianCalendar.startOfDay(for: Date())
    var timing: EventTiming = .allDay
    var startTime = gregorianCalendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    var durationDays = 1
    var durationHalfHours = 1
    var solarTimeZoneIdentifier: String? = nil
    var endMode: EndMode = .duration
    var endCount = 5
    var endUnit: PeriodUnit = .year
    var endDate = gregorianCalendar.date(byAdding: .year, value: 5, to: Date()) ?? Date()
    var monthEnd = true
    var position: RelativePosition = .before
    var offsetDays = 1
    var target = ""
    var hasApplied = false
    var weekdayPattern: WeekdayPattern? = nil
    var weeklyWeekday: Int? = nil
    var birthdaySource: BirthdayImportSource? = nil
    var appearance: RuleAppearance? = nil

    var displayName: String { name.isEmpty ? L10n.text("未命名規則", "Untitled Rule") : name }
    var displayAppearance: RuleAppearance { appearance ?? .init() }
    var defaultSymbol: String {
        category.contains("生日") || subcategory.contains("生日") ? "birthday.cake" : kind.symbol
    }

    var isMothersDayRule: Bool {
        guard parent == nil else { return false }
        return kind == .gregorian && period == .year && interval == 1 &&
            weekdayPattern?.ordinal == 2 && weekdayPattern?.weekday == 1 &&
            (weekdayPattern?.month ?? gregorianCalendar.component(.month, from: start)) == 5
    }

    var suggestedTitle: String? {
        guard parent == nil else { return nil }
        if kind == .solar { return SolarTerms.names.contains(date) ? SolarTerms.displayName(date) : nil }
        return isMothersDayRule ? L10n.text("母親節", "Mother’s Day") : nil
    }

    var suggestedCategory: String? {
        guard parent == nil, birthdaySource == nil else { return nil }
        switch kind {
        case .solar: return "節氣"
        case .lunar: return "祭祀"
        case .gregorian: return isMothersDayRule ? "節日" : nil
        }
    }

    var recurrenceCaption: String {
        if L10n.isEnglish { return englishRecurrenceCaption() }
        let count = Self.captionNumber(interval, measure: true)
        let yearly = interval == 1 ? "每年" : "每\(count)年"
        let monthly = interval == 1 ? "每月" : "每\(count)個月"
        if parent != nil {
            let days = Self.captionNumber(offsetDays, measure: true)
            switch position {
            case .before: return "依據日期前\(days)天"
            case .same: return "與依據日期同一天"
            case .after: return "依據日期後\(days)天"
            }
        }
        switch kind {
        case .solar:
            return date.isEmpty ? "\(yearly)的指定節氣" : "\(yearly)\(date)"
        case .lunar:
            let day = Self.lunarDayCaption(lunarDay)
            if period == .month { return "農曆\(monthly)\(day)" }
            let month = lunarMonth == 1 ? "正月" : Self.captionNumber(lunarMonth) + "月"
            return "農曆\(yearly)\(lunarIsLeap ? "閏" : "")\(month)\(day)"
        case .gregorian:
            let startMonth = gregorianCalendar.component(.month, from: start)
            let startDay = gregorianCalendar.component(.day, from: start)
            switch period {
            case .day: return interval == 1 ? "每天" : "每隔\(count)天"
            case .week:
                let weekday = Self.captionWeekday(weeklyWeekday ?? gregorianCalendar.component(.weekday, from: start))
                return interval == 1 ? "每\(weekday)" : "每\(count)週的\(weekday)"
            case .year, .month:
                if let pattern = weekdayPattern {
                    let ordinal = Self.captionNumber(pattern.ordinal)
                    let weekday = Self.captionWeekday(pattern.weekday)
                    if period == .year {
                        let month = Self.captionNumber(pattern.month ?? startMonth)
                        return "西元\(yearly)\(month)月的第\(ordinal)個\(weekday)"
                    }
                    return "西元\(monthly)的第\(ordinal)個\(weekday)"
                }
                let date = monthEnd && startDay == gregorianCalendar.range(of: .day, in: .month, for: start)?.last
                    ? "月底" : Self.captionNumber(startDay) + "日"
                if period == .year {
                    return "西元\(yearly)\(Self.captionNumber(startMonth))月\(date == "月底" ? "底" : date)"
                }
                return "西元\(monthly)\(date)"
            }
        }
    }

    var homeRecurrenceCaption: String {
        L10n.isEnglish ? englishRecurrenceCaption(compact: true) : recurrenceCaption
    }

    private func englishRecurrenceCaption(compact: Bool = false) -> String {
        var calendar = gregorianCalendar
        calendar.locale = L10n.locale
        let repeats: String
        if compact && interval == 1 {
            repeats = switch period {
            case .year: "Yearly"
            case .month: "Monthly"
            case .week: "Weekly"
            case .day: "Daily"
            }
        } else if compact && interval > 1 && period == .year {
            repeats = "Every \(interval) yrs"
        } else {
            repeats = interval == 1 ? "Every \(period.displayLabel())" : "Every \(interval) \(period.displayLabel(count: interval))"
        }
        let startMonth = calendar.component(.month, from: start)
        let startDay = calendar.component(.day, from: start)
        let weekday = { (n: Int) in
            (compact ? calendar.shortWeekdaySymbols : calendar.weekdaySymbols)[safeWeekdayIndex(n)]
        }
        func monthName(_ n: Int) -> String {
            (compact ? calendar.shortMonthSymbols : calendar.monthSymbols)[max(1, min(12, n)) - 1]
        }
        if parent != nil {
            let days = offsetDays == 1 ? "1 day" : "\(offsetDays) days"
            switch position {
            case .before: return "\(days) before the parent event"
            case .same: return "Same day as the parent event"
            case .after: return "\(days) after the parent event"
            }
        }
        switch kind {
        case .solar:
            return date.isEmpty ? "\(repeats) on the selected solar term" : "\(repeats) on \(SolarTerms.displayName(date))"
        case .lunar:
            if period == .month { return "\(repeats) on lunar day \(lunarDay)" }
            let month = lunarIsLeap ? "leap month \(lunarMonth)" : "lunar month \(lunarMonth)"
            return "\(repeats) on \(month), day \(lunarDay)"
        case .gregorian:
            if period == .day { return repeats }
            if period == .week {
                let day = weekday(weeklyWeekday ?? calendar.component(.weekday, from: start))
                return compact && interval == 2 ? "Every other \(day)" : "\(repeats) on \(day)"
            }
            if let pattern = weekdayPattern {
                let ordinalDay = "\(L10n.ordinal(pattern.ordinal)) \(weekday(pattern.weekday))"
                if period == .year {
                    let month = monthName(pattern.month ?? startMonth)
                    return compact && interval == 1 ? "\(ordinalDay) in \(month)" : "\(repeats) on the \(ordinalDay) in \(month)"
                }
                return "\(repeats) on the \(ordinalDay)"
            }
            let lastDay = calendar.range(of: .day, in: .month, for: start)?.count
            let fixedToEnd = monthEnd && startDay == lastDay
            if period == .year {
                let month = monthName(startMonth)
                return fixedToEnd ? "\(repeats) on the last day of \(month)" : "\(repeats) on \(month) \(startDay)"
            }
            return fixedToEnd ? "\(repeats) on the last day" : "\(repeats) on day \(startDay)"
        }
    }

    private func safeWeekdayIndex(_ value: Int) -> Int { max(0, min(6, value - 1)) }

    private static func captionWeekday(_ value: Int) -> String {
        let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
        return (1...7).contains(value) ? "星期" + weekdays[value - 1] : "指定星期"
    }

    private static func captionNumber(_ value: Int, measure: Bool = false) -> String {
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        if value == 2 && measure { return "兩" }
        if (0...9).contains(value) { return digits[value] }
        guard (10...99).contains(value) else { return String(value) }
        let tens = value / 10, ones = value % 10
        return (tens == 1 ? "" : digits[tens]) + "十" + (ones == 0 ? "" : digits[ones])
    }

    private static func lunarDayCaption(_ day: Int) -> String {
        switch day {
        case 1...10: return "初" + captionNumber(day)
        case 20: return "二十"
        case 21...29: return "廿" + captionNumber(day - 20)
        default: return captionNumber(day)
        }
    }

    mutating func pinSolarTimeZone() {
        let currentZone = RuleEngine.civilCalendar(for: self)
        let selected = UserDefaults.standard.string(forKey: "settings.defaultTimeZoneIdentifier")
            .flatMap(TimeZone.init(identifier:)) ?? TimeZone.current
        var local = Calendar(identifier: .gregorian)
        local.timeZone = selected
        func civilDay(_ input: Date) -> Date {
            local.date(from: currentZone.dateComponents([.year, .month, .day], from: input)) ?? input
        }
        let oldTime = currentZone.dateComponents([.hour, .minute], from: startTime)
        start = civilDay(start)
        endDate = civilDay(endDate)
        startTime = local.date(bySettingHour: oldTime.hour ?? 9, minute: oldTime.minute ?? 0, second: 0, of: local.startOfDay(for: Date())) ?? startTime
        solarTimeZoneIdentifier = selected.identifier
    }

    mutating func useSolarDefaultDuration() {
        let gregorianCalendar = RuleEngine.civilCalendar(for: self)
        guard let coverageEnd = gregorianCalendar.date(from: DateComponents(
            year: SolarTerms.supportedYears.upperBound, month: 12, day: 31
        )) else { return }
        endMode = .duration
        endDate = coverageEnd
        for (unit, maximum) in [(PeriodUnit.year, 5), (.month, 11)] {
            endUnit = unit
            for count in stride(from: maximum, through: 1, by: -1) {
                endCount = count
                if let cutoff = try? RuleEngine.cutoff(for: self), cutoff <= coverageEnd { return }
            }
        }
        endUnit = .day
        endCount = max(1, (gregorianCalendar.dateComponents(
            [.day], from: gregorianCalendar.startOfDay(for: start), to: coverageEnd
        ).day ?? 0) + 1)
    }

    static let family = "家人"
    static let life = "生活"
    static let birthdays = "生日與紀念日"
}

func categoryCalendarPresets(rules: [Rule], destinations: [CalendarDestination]) -> [String: String] {
    let writable = Set(destinations.lazy.filter(\.isWritable).map(\.id))
    var result: [String: String] = [:]
    for rule in rules where rule.parent == nil && !rule.category.isEmpty && writable.contains(rule.target) {
        if result[rule.category] == nil { result[rule.category] = rule.target }
    }
    return result
}

private struct GroupAppearanceKey: Codable, Hashable, Identifiable {
    let category: String
    var subcategory: String? = nil
    var id: Self { self }
    var title: String { subcategory ?? L10n.category(category) }
    var defaultSymbol: String {
        guard subcategory == nil else { return "folder" }
        switch category {
        case Rule.family: return "person.2"
        case Rule.life: return "leaf"
        default: return "folder"
        }
    }
}

private struct GroupAppearance: Codable {
    let key: GroupAppearanceKey
    let value: RuleAppearance
}

private struct RuleSnapshot: Codable {
    var rules: [Rule] = []
    var occurrences: [PlannedOccurrence] = []
    var groupAppearances: [GroupAppearance]? = nil
    var knownEmptyRuleIDs: Set<UUID>? = nil

    private static func url(localOnly: Bool = false) throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("CalStitch", isDirectory: true)
            .appendingPathComponent(CloudRuleEnvironment.current.localKey(
                localOnly ? "rules-local-v2.json" : "rules-before-cloud-v2.json"
            ))
    }

    static func read(localOnly: Bool = false) throws -> Self {
        let scoped = try Self.url(localOnly: localOnly)
        let fm = FileManager.default
        // Both environments can import the unchanged pre-sync baseline independently.
        // Once local edits are made they stay in the active environment's file.
        let source = !localOnly && !fm.fileExists(atPath: scoped.path)
            ? scoped.deletingLastPathComponent().appendingPathComponent("rules-v1.json") : scoped
        guard fm.fileExists(atPath: source.path) else { return Self() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: source))
    }

    func preflightWrite() throws {
        let url = try Self.url()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".preflight-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try JSONEncoder().encode(self).write(to: temporary, options: .atomic)
    }

    func write(localOnly: Bool = false) throws {
        let url = try Self.url(localOnly: localOnly)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var clean = self
        clean.pruneGroupAppearances()
        try JSONEncoder().encode(clean).write(to: url, options: .atomic)
    }

    mutating func pruneGroupAppearances() {
        guard let stored = groupAppearances, !stored.isEmpty else { return }
        var keys = Set<GroupAppearanceKey>()
        for rule in rules where rule.parent == nil {
            keys.insert(.init(category: rule.category))
            if !rule.subcategory.isEmpty {
                keys.insert(.init(category: rule.category, subcategory: rule.subcategory))
            }
        }
        let remaining = stored.filter { keys.contains($0.key) }
        groupAppearances = remaining.isEmpty ? nil : remaining
    }
}

private struct VerifiedCalendarBinding: Codable {
    let id: String
    let descriptor: CalendarSyncDestination
    // nil old value (without evidence) cannot override a different cloud descriptor.
    var evidence: CloudDestinationEvidence? = nil
}

private struct CloudDestinationEvidence: Codable, Equatable {
    let destination: CalendarSyncDestination?
    let unresolvedOwner: UUID?
    init(_ entry: CloudRuleEnvelope) {
        destination = entry.destination
        unresolvedOwner = entry.unresolvedOwner
    }
}

private struct CloudLocalWritePlan: Codable {
    let destinations: [UUID: String]
    let removalGuard: Data?
}

private extension CalendarIntegrationError {
    var requiresManualRecovery: Bool {
        switch self {
        case .uncertainRemovalRecovery, .ambiguousEvent, .invalidPlan, .writeFailed, .removalSelectionChanged: true
        default: false
        }
    }
}

private struct LocalRuleWriteJournal: Codable {
    let plan: CalendarSyncPlan
    let destinations: [UUID: String]
    var proposed: RuleSnapshot
    var removalGuard: Data? = nil
    var eventKitComplete: Bool = false

    private static func url(localOnly: Bool) throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("CalStitch", isDirectory: true)
            .appendingPathComponent(CloudRuleEnvironment.current.localKey(
                localOnly ? "local-only-journal-v1.json" : "before-cloud-journal-v2.json"
            ))
    }

    static func hasUnscopedLegacyJournal() throws -> Bool {
        let old = try url(localOnly: false).deletingLastPathComponent()
            .appendingPathComponent("legacy-local-journal-v1.json")
        do {
            _ = try old.resourceValues(forKeys: [.isRegularFileKey])
            return true
        } catch {
            let failure = error as NSError
            guard failure.domain == NSCocoaErrorDomain,
                  failure.code == NSFileReadNoSuchFileError || failure.code == NSFileNoSuchFileError else { throw error }
            return false
        }
    }

    static func read(localOnly: Bool) throws -> Self? {
        let path = try url(localOnly: localOnly)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: path))
    }

    func write(localOnly: Bool) throws {
        let path = try Self.url(localOnly: localOnly)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: path, options: .atomic)
    }

    static func clear(localOnly: Bool) throws {
        try FileManager.default.removeItem(at: url(localOnly: localOnly))
    }
}

private struct RuleOperationError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

private struct RuleReconciliation {
    let desired: [PlannedOccurrence]
    let previous: [PlannedOccurrence]
    let ruleIDs: Set<UUID>
    let rules: [Rule]
}

func dateCaption(_ date: Date, calendar: Calendar = gregorianCalendar) -> String {
    L10n.date(date, timeZone: calendar.timeZone, includesWeekday: true)
}

private func timeCaption(_ date: Date, calendar: Calendar = gregorianCalendar) -> String {
    L10n.time(date, timeZone: calendar.timeZone)
}

private struct RuleDateField: View {
    enum Kind { case date, time }
    let title: String
    @Binding var selection: Date
    var kind: Kind = .date
    var civilCalendar: Calendar = gregorianCalendar
    @State private var showingPicker = false
    @State private var draft = Date()

    var body: some View {
        Button {
            draft = selection
            showingPicker = true
        } label: {
            LabeledContent(title, value: kind == .date ? dateCaption(selection, calendar: civilCalendar) : timeCaption(selection, calendar: civilCalendar))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingPicker) {
            NavigationStack {
                VStack {
                    if kind == .date {
                        DatePicker(title, selection: $draft, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                    } else {
                        DatePicker(title, selection: $draft, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                    }
                }
                .padding()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L10n.text("取消", "Cancel")) { showingPicker = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.text("完成", "Done")) {
                            selection = draft
                            showingPicker = false
                        }
                    }
                }
            }
            .environment(\.locale, L10n.locale)
            .environment(\.calendar, civilCalendar)
            .environment(\.timeZone, civilCalendar.timeZone)
            .presentationDetents([.medium, .large])
        }
    }
}

private enum Route: Hashable {
    case settings
    case edit(Rule, isNew: Bool)
}

private struct RulesHome: View {
    @StateObject private var calendar = CalendarIntegration()
    @State private var cloud = RuleCloudSync()
    @State private var cloudSession: CloudRuleSession?
    @State private var cloudReadError: String?
    @State private var cloudReady = false
    @State private var cloudBusy = false
    @State private var cloudRefreshing = false
    @State private var cloudResetPending = false
    @State private var knownDestinations: [UUID: String] = [:]
    @State private var directFrozen: [UUID: String] = [:]
    @State private var freezeReview: Rule?
    @State private var pendingWait = CloudPendingWait()
    @State private var pendingWaitAccount: String?
    @State private var pendingClockOrigin = ContinuousClock().now
    @AppStorage("settings.hideFrozenRules") private var hideFrozen = false
    @AppStorage(CloudRuleEnvironment.current.localKey("rules.hasCloudAccount")) private var hasCloudAccount = false
    @State private var awaitingLocalRecovery = false
    @State private var path: [Route] = []
    @State private var isAdding = false
    @State private var contactPickerRequest: UUID?
    @State private var birthdaySelection: BirthdayPickerSelection?
    @State private var showingBirthdayRoutes = false
    @State private var showingOrphanCleanup = false
    @State private var pendingBirthdayRoute: BirthdayImportRoute?
    @State private var selectingBirthdayGroup = false
    @State private var checkedBirthdaySettingsReturn = false
    @State private var choosingPeopleAfterGroup = false
    private enum BirthdayImportRoute { case people, group }
    @State private var isShowingBatch = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var showGettingStarted = false
    @State private var reachedBackground = false
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var toolbarError: String?
    @State private var requestingCalendarAccess = false
    @State private var appliedNotice: UUID?
    @State private var snapshot = RuleSnapshot()
    @State private var appearanceGroup: GroupAppearanceKey?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("行事曆規則", "Calendar Rules"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        toolsRow
                    }
                    if !calendar.hasFullAccess { calendarAccessNotice }
                    if let cloudReadError {
                        Label(cloudReadError, systemImage: "icloud.slash")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button(L10n.text("重新同步", "Retry Sync")) { Task { await load() } }
                    }
                    if loaded && showGettingStarted { intro }
                    if !loaded && !loadFailed {
                        ProgressView(L10n.text("正在讀取規則…", "Loading rules…"))
                    } else if loadFailed {
                        Button(L10n.text("重新讀取規則", "Reload Rules")) { Task { await load() } }
                    } else if visibleRootRules.isEmpty {
                        emptyState
                    }
                    let names = uniqueNames(visibleRootRules.map(\.category))
                    ForEach(names, id: \.self) { name in
                        category(name, rules: visibleRootRules.filter { $0.category == name }, isFirst: name == names.first)
                    }
                    if loaded {
                        let layout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                            : AnyLayout(HStackLayout(spacing: 20))
                        layout {
                            Button {
                                showingBirthdayRoutes = true
                            } label: {
                                Label(L10n.text("匯入生日", "Import Birthdays"), systemImage: "person.crop.rectangle")
                                    .frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("open-birthday-import")
                            Button {
                                showingOrphanCleanup = true
                            } label: {
                                Label(L10n.text("清除遺留事件", "Clean Up Leftover Events"), systemImage: "trash")
                                    .frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("open-orphan-cleanup")
                        }
                        .disabled(!calendar.hasFullAccess)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 3)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 20)
            }
            .background(paper)
            .navigationTitle("CalStitch")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Route.settings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(L10n.text("設定", "Settings"))
                    .accessibilityIdentifier("open-settings")
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .settings:
                    CalStitchSettingsView(hideFrozen: $hideFrozen)
                case .edit(let rule, let isNew):
                    if isDeletedInCloud(rule.id) {
                        VStack(spacing: 20) {
                            ContentUnavailableView(
                                L10n.text("規則已刪除", "Rule Deleted"), systemImage: "trash",
                                description: Text(CloudRuleError.ruleDeleted.localizedDescription)
                            )
                            if calendar.hasFullAccess && !pendingWait.expiredOperations(touching: rule.id).isEmpty {
                                Button(L10n.text("解除凍結", "Unfreeze")) { freezeReview = rule }
                            }
                            Button(L10n.text("返回規則列表", "Back to Rules")) { path.removeAll() }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        RuleEditor(initial: snapshot.rules.first { $0.id == rule.id } ?? rule, isNew: isNew,
                                   parent: snapshot.rules.first { $0.id == rule.parent },
                                   allRules: snapshot.rules, calendar: calendar,
                                   preview: preview, onApply: apply, onApplied: returnAfterApply,
                                   previewDeletion: { id in try previewRemoval([id], allowChild: true) },
                                   onDelete: { id, expected in try await removeSelected([id], expected, allowChild: true) },
                                   onDeleted: { if !path.isEmpty { path.removeLast() } },
                                   onSaveAppearance: saveRuleAppearance,
                                   frozenReason: calendar.hasFullAccess ? (freezeReason(rule.id) ?? pendingReason(rule.id)) : CalendarIntegrationError.denied.localizedDescription,
                                   hiddenRuleIDs: calendar.hasFullAccess && hideFrozen ? Set(snapshot.rules.filter { freezeReason($0.id) != nil }.map(\.id)) : [],
                                   thawTitle: nil,
                                   onThaw: !calendar.hasFullAccess || freezeReason(rule.id) == nil ? nil : { freezeReview = rule }) { child, isNew in
                            path.append(.edit(child, isNew: isNew))
                        }
                    }
                }
            }
            .sheet(isPresented: $isAdding) { addSheet }
            .sheet(item: $freezeReview) { frozenRule in
                FrozenRuleReview(rule: frozenRule, original: originalCalendarTitle(frozenRule.id),
                                 inspect: { try await reviewThaw(frozenRule.id) },
                                 confirm: { expected in try await confirmThaw(frozenRule.id, expected: expected) })
            }
            .background {
                ContactPickerPresenter(request: contactPickerRequest) { selection in
                    contactPickerRequest = nil
                    if calendar.hasFullAccess { birthdaySelection = selection }
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
            .sheet(item: $birthdaySelection) { selection in
                BirthdayImportView(selection: selection, calendar: calendar, categories: batchCategories,
                                   presetCalendarIDs: { categoryCalendarPresets(rules: rootRules, destinations: calendar.destinations) },
                                   status: birthdayStatus, onImport: importBirthdays)
            }
            .sheet(isPresented: $showingBirthdayRoutes, onDismiss: openSelectedBirthdayRoute) {
                birthdayRouteSheet
            }
            .sheet(isPresented: $selectingBirthdayGroup, onDismiss: {
                if choosingPeopleAfterGroup {
                    choosingPeopleAfterGroup = false
                    if calendar.hasFullAccess { contactPickerRequest = UUID() }
                }
            }) {
                BirthdayGroupImportView(calendar: calendar, categories: batchCategories,
                                        presetCalendarIDs: { categoryCalendarPresets(rules: rootRules, destinations: calendar.destinations) },
                                        status: birthdayStatus, onChoosePeople: {
                                            choosingPeopleAfterGroup = true
                                            selectingBirthdayGroup = false
                                        }, onImport: importBirthdays)
            }
            .sheet(isPresented: $showingOrphanCleanup) {
                OrphanCleanupView(calendar: calendar, existingRuleIDs: orphanProtectedIDs,
                                  beforeRemove: refreshBeforeOrphans)
            }
            .sheet(isPresented: $isShowingBatch) {
                BatchActionsView(rules: batchEligibleRoots.map {
                    .init(id: $0.id, title: $0.displayName, subtitle: $0.recurrenceCaption,
                          category: $0.category, subcategory: $0.subcategory)
                }, initiallySelected: [], categories: batchCategories,
                preview: previewBatch, apply: applyBatch,
                removalPreview: previewRemoval, remove: removeSelected)
            }
            .sheet(item: $appearanceGroup) { key in
                AppearanceEditSheet(title: key.title, initial: groupAppearance(key),
                                    defaultSymbol: key.defaultSymbol) { newAppearance in
                    try saveGroupAppearance(newAppearance, for: key)
                }
            }
            .alert(L10n.text("無法完成操作", "Could Not Complete the Action"), isPresented: Binding(
                get: { toolbarError != nil }, set: { if !$0 { toolbarError = nil } }
            )) {
                Button(L10n.text("好", "OK"), role: .cancel) { toolbarError = nil }
            } message: { Text(toolbarError ?? "") }
        }
        .tint(slate)
        .onChange(of: snapshot.rules) { _, _ in snapshot.pruneGroupAppearances() }
        .overlay(alignment: .bottom) {
            if appliedNotice != nil {
                Label(L10n.text("已套用", "Applied"), systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .allowsHitTesting(false)
            }
        }
        .task(id: appliedNotice) {
            guard let notice = appliedNotice else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            if appliedNotice == notice { appliedNotice = nil }
        }
        .environment(\.timeZone, ruleZone)
        .environment(\.calendar, gregorianCalendar)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                await load()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            cloudReady = false
            cloudResetPending = true
            if !cloudBusy {
                snapshot = RuleSnapshot()
                cloudSession = nil
                loaded = false
                Task { await load() }
            }
        }
        .onChange(of: calendar.authorizationStatus) {
            if calendar.hasFullAccess {
                restoreBirthdaySettingsRouteIfAuthorized()
            } else {
                dismissCalendarMaintenance()
            }
            if let session = cloudSession, !cloudBusy { restoreCloud(session) }
        }
        .onChange(of: calendar.destinations) { _, _ in
            if let session = cloudSession, !cloudBusy { restoreCloud(session) }
        }
        .task {
            calendar.refreshCalendars()
            if !loaded && !loadFailed { await load() }
            restoreBirthdaySettingsRouteIfAuthorized()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                calendar.refreshCalendars()
                Task { await load() }
            }
            if phase == .background { reachedBackground = true }
            if phase == .active && reachedBackground {
                showGettingStarted = rootRules.isEmpty
                reachedBackground = false
            }
        }
    }

    private var calendarAccessNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.text("需要完整取用行事曆", "Full Calendar Access Needed"), systemImage: "calendar.badge.exclamationmark")
                .font(.headline)
            Text(L10n.text("你仍可查看已同步的規則。完整取用行事曆後，才能管理規則及預覽事件。",
                           "You can still view synced rules. Allow full Calendar access to manage rules and preview events."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if calendar.canRequestFullAccess {
                Button(L10n.text("允許完整取用", "Allow Full Access")) {
                    guard !requestingCalendarAccess else { return }
                    requestingCalendarAccess = true
                    Task {
                        defer { requestingCalendarAccess = false }
                        do { try await calendar.requestCalendarFullAccess() }
                        catch CalendarIntegrationError.denied { /* The entry now directs the user to Settings. */ }
                        catch { toolbarError = error.localizedDescription }
                    }
                }
                .disabled(requestingCalendarAccess)
                .accessibilityIdentifier("request-calendar-full-access")
            } else {
                Button(L10n.text("前往設定", "Open Settings")) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .accessibilityIdentifier("open-calendar-access-settings")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(slate.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
    }

    private func restoreBirthdaySettingsRouteIfAuthorized() {
        guard calendar.hasFullAccess, !checkedBirthdaySettingsReturn else { return }
        checkedBirthdaySettingsReturn = true
        if BirthdayGroupSettingsReturn.consume() { selectingBirthdayGroup = true }
    }

    private func dismissCalendarMaintenance() {
        isAdding = false
        isShowingBatch = false
        showingBirthdayRoutes = false
        selectingBirthdayGroup = false
        contactPickerRequest = nil
        birthdaySelection = nil
        pendingBirthdayRoute = nil
        choosingPeopleAfterGroup = false
        showingOrphanCleanup = false
        appearanceGroup = nil
    }

    private func requireCalendarMaintenance() throws {
        guard calendar.hasFullAccess else { throw CalendarIntegrationError.denied }
    }

    private var rootRules: [Rule] { snapshot.rules.filter { $0.parent == nil } }
    private var visibleRootRules: [Rule] {
        calendar.hasFullAccess && hideFrozen ? rootRules.filter { freezeReason($0.id) == nil } : rootRules
    }

    private var batchEligibleRoots: [Rule] {
        let branches = Dictionary(grouping: snapshot.rules, by: \.parent)
        return rootRules.filter { root in
            var seen: Set<UUID> = []
            var pending = [root]
            while let rule = pending.popLast() {
                guard seen.insert(rule.id).inserted else { continue }
                if freezeReason(rule.id) != nil || pendingOperation(rule.id) != nil { return false }
                pending += branches[rule.id] ?? []
            }
            return true
        }
    }

    private var birthdayRouteSheet: some View {
        NavigationStack {
            List {
                Button {
                    pendingBirthdayRoute = .people
                    showingBirthdayRoutes = false
                } label: {
                    Label(L10n.text("個別選人", "Select People"), systemImage: "person.crop.rectangle")
                }
                .accessibilityIdentifier("birthday-route-people")
                Button {
                    pendingBirthdayRoute = .group
                    showingBirthdayRoutes = false
                } label: {
                    Label(L10n.text("依群組匯入", "Import by Group"), systemImage: "person.2")
                }
                .accessibilityIdentifier("birthday-route-group")
            }
            .navigationTitle(L10n.text("匯入生日", "Import Birthdays"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("取消", "Cancel")) { showingBirthdayRoutes = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func openSelectedBirthdayRoute() {
        let selected = pendingBirthdayRoute
        pendingBirthdayRoute = nil
        guard calendar.hasFullAccess else { return }
        switch selected {
        case .people: contactPickerRequest = UUID()
        case .group: selectingBirthdayGroup = true
        case nil: break
        }
    }

    private func groupAppearance(_ key: GroupAppearanceKey) -> RuleAppearance {
        snapshot.groupAppearances?.first { $0.key == key }?.value ?? .init()
    }

    private func saveGroupAppearance(_ appearance: RuleAppearance, for key: GroupAppearanceKey) throws {
        try requireCalendarMaintenance()
        guard rootRules.contains(where: { $0.category == key.category && (key.subcategory == nil || $0.subcategory == key.subcategory) }) else {
            throw RuleOperationError(L10n.text("找不到這個分類。", "This category could not be found."))
        }
        var updated = snapshot
        var entries = updated.groupAppearances ?? []
        entries.removeAll { $0.key == key }
        if !appearance.isDefault { entries.append(.init(key: key, value: appearance)) }
        updated.groupAppearances = entries.isEmpty ? nil : entries
        if let account = cloudSession?.accountID {
            try saveAppearances(updated.groupAppearances, account: account)
        } else {
            try updated.write(localOnly: hasCloudAccount)
        }
        snapshot = updated
    }

    private func saveRuleAppearance(_ id: UUID, _ appearance: RuleAppearance) async throws -> Bool {
        try requireCalendarMaintenance()
        guard let index = snapshot.rules.firstIndex(where: { $0.id == id }) else { return false }
        var updated = snapshot
        updated.rules[index].appearance = appearance.isDefault ? nil : appearance
        try await performMutation(updated, scope: [id])
        return true
    }

    private func returnAfterApply() {
        guard !path.isEmpty else { return }
        path.removeLast()
        appliedNotice = UUID()
        AccessibilityNotification.Announcement(L10n.text("已套用", "Applied")).post()
    }

    private func showAppleCalendar() {
        guard let url = URL(string: "calshow:") else { return }
        openURL(url) { accepted in
            if !accepted {
                toolbarError = L10n.text("此裝置無法開啟 Apple 行事曆。請手動開啟「行事曆」App。", "This device could not open Apple Calendar. Please open Calendar manually.")
            }
        }
    }

    private func load() async {
        guard !cloudBusy, !cloudRefreshing else { return }
        cloudRefreshing = true
        defer {
            cloudRefreshing = false
            if cloudResetPending && !cloudBusy { Task { await load() } }
        }
        if cloudResetPending {
            cloudResetPending = false
            pendingWait = CloudPendingWait()
            pendingWaitAccount = nil
            snapshot = RuleSnapshot()
            cloudSession = nil
            loaded = false
        }
        do {
            if try LocalRuleWriteJournal.hasUnscopedLegacyJournal() {
                throw RuleOperationError(L10n.text("舊版有尚未確認的本機寫入，無法判定它屬於哪個同步環境。請先在原版本完成復原。", "An unverified local calendar update from an older version has no sync environment. Recover it in the version that started it first."))
            }
            if var session = try await cloud.refresh() {
                if try LocalRuleWriteJournal.read(localOnly: hasCloudAccount) != nil {
                    throw RuleOperationError(L10n.text("有尚未確認的本機寫入，請先完成原本機狀態的復原，再啟用 iCloud 規則同步。", "A local calendar update has not been verified. Recover it in the original local mode before enabling rule sync."))
                }
                recordAccountSeen(session.accountID)
                if let preceding = cloudSession, preceding.accountID != session.accountID {
                    snapshot = RuleSnapshot()
                    knownDestinations = [:]
                }
                if cloud.canMigrateLegacy(in: session),
                   !hasCloudAccount || (cloud.hasLegacyMigrationOwner && !cloud.hasMigratedLegacy(in: session)) {
                    let legacy = try RuleSnapshot.read()
                    if !legacy.rules.isEmpty {
                        let envelope = legacy.rules.map { rule in
                            let destination = rule.target.isEmpty ? nil : try? calendar.syncDestination(id: rule.target, deviceID: cloud.deviceID)
                            let prior = legacy.occurrences.filter { $0.ruleID == rule.id }
                            return portable(rule, destination: destination,
                                            prior: rule.hasApplied && prior.isEmpty && legacy.knownEmptyRuleIDs?.contains(rule.id) != true ? nil : prior)
                        }
                        let alreadyCloud = Set(session.ledger.rules.map(\.id)).union(session.ledger.tombstones)
                        let knownBindings = bindings(session.accountID)
                        let seedRules = legacy.rules.filter {
                            (!$0.target.isEmpty || $0.birthdaySource != nil) && !alreadyCloud.contains($0.id)
                        }
                        let seeds = Dictionary(uniqueKeysWithValues: seedRules
                            .filter { !$0.target.isEmpty && knownBindings[$0.id] == nil }.map { ($0.id, $0.target) })
                        do {
                            // Keep known local identities even if the server response is lost.
                            mergeBindings(seeds, account: session.accountID)
                            rememberBirthdaySources(seedRules, account: session.accountID)
                            try saveAppearances(legacy.groupAppearances, account: session.accountID, replacing: false)
                            session = try await cloud.migrate(envelope, in: session)
                        } catch CloudRuleError.legacyAccountMismatch {
                            // Local data is permanently tied to its first iCloud namespace.
                            // A different signed-in account can still show its own ledger.
                        }
                    }
                }
                guard !cloudResetPending else { throw CloudRuleError.accountChanged }
                hasCloudAccount = true
                try observeWait(session)
                restoreCloud(session)
                cloudReady = true
                cloudReadError = nil
                await recoverCloud(session)
            } else {
                // An explicit no-account response is not an empty cloud ledger.
                guard !cloudResetPending else { throw CloudRuleError.accountChanged }
                cloudSession = nil
                pendingWait = CloudPendingWait()
                pendingWaitAccount = nil
                knownDestinations = [:]
                directFrozen = [:]
                snapshot = try RuleSnapshot.read(localOnly: hasCloudAccount)
                cloudReady = true
                cloudReadError = nil
                await recoverLocal()
            }
            if !loaded { showGettingStarted = snapshot.rules.isEmpty }
            loadFailed = false
            loaded = true
        } catch {
            if let account = pendingWaitAccount {
                pendingWait.expire(elapsed: pendingClockOrigin.duration(to: ContinuousClock().now))
                try? cloud.saveManualWaits(pendingWait.confirmedWaiting, accountID: account)
            }
            cloudReady = false
            cloudReadError = error.localizedDescription
            loadFailed = !loaded
        }
    }

    private func portable(_ input: Rule, destination: CalendarSyncDestination?,
                          prior: [PlannedOccurrence]?) -> CloudRuleEnvelope {
        var rule = input
        rule.target = ""
        return CloudRuleEnvelope(rule: rule, destination: destination,
                                 prior: prior?.map { value in
                                     var occurrence = value
                                     occurrence.calendarID = ""
                                     return occurrence
                                 },
                                 unresolvedOwner: destination == nil && !input.target.isEmpty ? cloud.deviceID : nil)
    }

    private func mergeBindings(_ values: [UUID: String], account: String) {
        var merged = bindings(account)
        merged.merge(values) { _, newValue in newValue }
        if let data = try? JSONEncoder().encode(merged) {
            UserDefaults.standard.set(data, forKey: cloudLocalKey("rules.destinationBindings." + account))
        }
    }

    private func bindings(_ account: String) -> [UUID: String] {
        let data = UserDefaults.standard.data(forKey: cloudLocalKey("rules.destinationBindings." + account))
        return data.flatMap { try? JSONDecoder().decode([UUID: String].self, from: $0) } ?? [:]
    }

    private func saveAppearances(_ appearances: [GroupAppearance]?, account: String,
                                 replacing: Bool = true) throws {
        let key = cloudLocalKey("rules.localAppearance." + account)
        guard replacing || UserDefaults.standard.data(forKey: key) == nil else { return }
        UserDefaults.standard.set(try JSONEncoder().encode(appearances ?? []), forKey: key)
    }

    private func accountAppearances(_ account: String) -> [GroupAppearance]? {
        let key = cloudLocalKey("rules.localAppearance." + account)
        return UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([GroupAppearance].self, from: $0) }
    }

    private func birthdaySources(_ account: String) -> [UUID: BirthdayImportSource] {
        let key = cloudLocalKey("rules.localBirthdaySources." + account)
        return UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([UUID: BirthdayImportSource].self, from: $0) } ?? [:]
    }

    private func rememberBirthdaySources(_ rules: [Rule], account: String) {
        var values = birthdaySources(account)
        for rule in rules {
            if let source = rule.birthdaySource { values[rule.id] = source }
        }
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: cloudLocalKey("rules.localBirthdaySources." + account))
        }
    }

    private func restoreCloud(_ session: CloudRuleSession) {
        cloudSession = session
        let remembered = bindings(session.accountID)
        let verified = verifiedBindings(session.accountID)
        let contactOrigins = birthdaySources(session.accountID)
        var known: [UUID: String] = [:]
        var frozen: [UUID: String] = [:]
        var rules: [Rule] = []
        var occurrences: [PlannedOccurrence] = []
        let committed = Set(session.ledger.rules.map(\.id))
        let placeholders = session.ledger.pending.flatMap(\.upserts).filter { !committed.contains($0.id) }
        for entry in session.ledger.rules + placeholders {
            var rule = entry.rule
            if !committed.contains(rule.id) { rule.hasApplied = false }
            rule.birthdaySource = contactOrigins[rule.id]
            if let binding = verified[rule.id],
               (binding.evidence == CloudDestinationEvidence(entry)
                 || (binding.evidence == nil && binding.descriptor == entry.destination)),
               (try? calendar.resolveSyncDestination(binding.descriptor, rememberedID: binding.id, deviceID: cloud.deviceID)) == binding.id {
                rule.target = binding.id
            } else if let destination = entry.destination {
                if let owner = destination.localOwner, owner != cloud.deviceID {
                    frozen[rule.id] = L10n.text("這是原 iPhone 的本機行事曆，請回該裝置操作。", "This calendar is local to the original iPhone. Use that device for changes.")
                } else {
                do {
                    rule.target = try calendar.resolveSyncDestination(destination, rememberedID: remembered[rule.id], deviceID: cloud.deviceID)
                } catch { frozen[rule.id] = error.localizedDescription }
                }
            } else if entry.unresolvedOwner == cloud.deviceID,
                      let id = remembered[rule.id],
                      (try? calendar.syncDestination(id: id, deviceID: cloud.deviceID)) != nil {
                rule.target = id
            } else if rule.hasApplied || entry.unresolvedOwner != nil {
                frozen[rule.id] = L10n.text("無法確認原行事曆。", "The original calendar could not be confirmed.")
            }
            if !rule.target.isEmpty {
                known[rule.id] = rule.target
                occurrences += (entry.prior ?? []).map { original in
                    var occurrence = original
                    occurrence.calendarID = rule.target
                    return occurrence
                }
            }
            rules.append(rule)
        }
        mergeBindings(known, account: session.accountID)
        knownDestinations = known
        directFrozen = frozen
        let appearances = accountAppearances(session.accountID)
        snapshot = RuleSnapshot(rules: rules, occurrences: occurrences, groupAppearances: appearances)
    }

    private func observeWait(_ session: CloudRuleSession) throws {
        if pendingWaitAccount != session.accountID {
            pendingWaitAccount = session.accountID
            pendingWait = CloudPendingWait(confirmedWaiting: cloud.manualWaits(accountID: session.accountID))
        }
        pendingWait.observe(session, elapsed: pendingClockOrigin.duration(to: ContinuousClock().now))
        try cloud.saveManualWaits(pendingWait.confirmedWaiting, accountID: session.accountID)
    }

    private func clearWait(_ proposal: CloudThawProposal) throws {
        guard !proposal.expired.isEmpty, pendingWaitAccount == proposal.accountID else { return }
        var updated = pendingWait
        updated.clearManually(proposal.expired, for: proposal.affected)
        try cloud.saveManualWaits(updated.confirmedWaiting, accountID: proposal.accountID)
        pendingWait = updated
    }

    private func freezeReason(_ id: UUID, includingAncestors: Bool = true) -> String? {
        var cursor: UUID? = id
        var seen = Set<UUID>()
        while let current = cursor, seen.insert(current).inserted {
            if interruptedOperation(current) != nil {
                return L10n.text("套用中斷。", "The update was interrupted.")
            }
            if !pendingWait.expiredOperations(touching: current).isEmpty {
                return L10n.text("待完成時間較長，暫時凍結。", "This update is taking longer than expected. The rule is frozen for now.")
            }
            if pendingOperation(current) != nil { return nil }
            if let reason = directFrozen[current] { return reason }
            cursor = includingAncestors ? snapshot.rules.first(where: { $0.id == current })?.parent : nil
        }
        return nil
    }

    private func operationTouches(_ operation: CloudRuleOperation, ruleID: UUID) -> Bool {
        operation.deletions.contains(ruleID) || operation.upserts.contains(where: { $0.id == ruleID })
            || operation.plan?.ruleIDs.contains(ruleID) == true
    }

    private func pendingOperation(_ id: UUID) -> CloudRuleOperation? {
        cloudSession?.ledger.pending.first { operationTouches($0, ruleID: id) }
    }

    private func interruptedOperation(_ id: UUID) -> CloudRuleOperation? {
        pendingOperation(id).flatMap { $0.interrupted ? $0 : nil }
    }

    private func assertWritable(_ scope: Set<UUID>, eventRuleIDs: Set<UUID> = []) throws {
        try requireCalendarMaintenance()
        guard loaded, cloudReady, !cloudResetPending, !awaitingLocalRecovery else {
            throw RuleOperationError(L10n.text("規則尚未與 iCloud 核對，暫未更動行事曆。", "Rules have not been verified with iCloud. No calendar events changed."))
        }
        guard scope.allSatisfy({ freezeReason($0) == nil && pendingOperation($0) == nil }) else {
            throw RuleOperationError(L10n.text("此次操作包含凍結或等待完成的規則，未更動行事曆。", "This action includes frozen or pending rules. No calendar events changed."))
        }
        if let session = cloudSession,
           session.ledger.rules.contains(where: { eventRuleIDs.contains($0.rule.id) && $0.rule.hasApplied && $0.prior == nil }) {
            throw RuleOperationError(L10n.text("無法確認舊版的套用紀錄，不能安全地重新建立或移除事件。", "The previous update record is unavailable. Events cannot safely be recreated or removed."))
        }
    }

    private func cloudLocalKey(_ legacy: String) -> String {
        CloudRuleEnvironment.current.localKey(legacy)
    }

    private var accountsSeen: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: cloudLocalKey("rules.cloudAccountsSeen")) ?? [])
    }

    private func recordAccountSeen(_ account: String) {
        UserDefaults.standard.set(Array(accountsSeen.union([account])).sorted(), forKey: cloudLocalKey("rules.cloudAccountsSeen"))
    }

    private func orphanProtectedIDs() throws -> Set<UUID> {
        // Existing EventKit markers are shared across devices and don't encode
        // either the CloudKit environment or the iCloud account. A missing ID
        // here is not evidence that the event is safe to remove.
        throw RuleOperationError(L10n.text("目前無法從事件標記判定同步環境或帳號，因此暫停清除遺留事件。仍可從規則移除其事件。", "Event markers do not identify their sync environment or account, so leftover cleanup is paused. You can still remove events through their rules."))
    }

    private func saveDraft(_ rule: Rule, account: String) {
        if let data = try? JSONEncoder().encode(rule) {
            UserDefaults.standard.set(data, forKey: cloudLocalKey("rules.cloudDraft.\(account).\(rule.id)"))
        }
    }

    /// The sole EventKit mutation entry point for user-initiated rule changes.
    private func performMutation(_ proposed: RuleSnapshot, scope: Set<UUID>,
                                 desired: [PlannedOccurrence] = [], previous: [PlannedOccurrence] = [],
                                 eventRuleIDs: Set<UUID> = [], removal: [CalendarRemovalEvent]? = nil) async throws {
        guard !cloudBusy, !cloudRefreshing else {
            throw RuleOperationError(L10n.text("iCloud 正在核對規則，請稍候重試。", "iCloud is checking rules. Try again shortly."))
        }
        // A new child is not in the visible tree until the server commits it. Reserve
        // its ancestor too so a concurrent parent change cannot miss that new child.
        var lockScope = scope
        let ancestry = Dictionary(uniqueKeysWithValues: snapshot.rules.map { ($0.id, $0) })
            .merging(Dictionary(uniqueKeysWithValues: proposed.rules.map { ($0.id, $0) })) { _, new in new }
        for id in scope {
            var cursor = ancestry[id]?.parent
            while let ancestor = cursor, lockScope.insert(ancestor).inserted { cursor = ancestry[ancestor]?.parent }
        }
        try assertWritable(lockScope, eventRuleIDs: eventRuleIDs)
        cloudBusy = true
        defer {
            cloudBusy = false
            if cloudResetPending { Task { await load() } }
        }
        try proposed.preflightWrite()
        let attemptID = UUID()
        defer { cloud.endLocalExecution(attemptID) }
        let eventPlan: CalendarSyncPlan?
        do {
            eventPlan = try eventRuleIDs.isEmpty ? nil : calendar.prepareSyncPlan(
                desired: desired, previous: previous, ruleIDs: eventRuleIDs, attemptID: attemptID, matchingRemoval: removal
            )
        } catch CalendarIntegrationError.missingEvent where cloudSession != nil {
            throw RuleOperationError(L10n.text("正在等待行事曆同步，請在舊事件可見後重試。未更動行事曆。", "Wait for Calendar to sync the existing events and try again. No calendar events changed."))
        }
        let before = Dictionary(uniqueKeysWithValues: snapshot.rules.map { ($0.id, $0.target) })
        let after = Dictionary(uniqueKeysWithValues: proposed.rules.map { ($0.id, $0.target) })
        let locations = before.merging(after) { _, new in new }
        let removalGuard = try eventPlan.map { try calendar.syncRemovalGuard(for: $0, destinations: locations) }
        if let session = cloudSession {
            let deletion = scope.subtracting(Set(proposed.rules.map(\.id)))
            let old = Dictionary(uniqueKeysWithValues: session.ledger.rules.map { ($0.rule.id, $0) })
            let envelopes = try proposed.rules.filter { scope.contains($0.id) }.map { rule in
                let destination = rule.target.isEmpty ? old[rule.id]?.destination :
                    try calendar.syncDestination(id: rule.target, deviceID: cloud.deviceID)
                let prior: [PlannedOccurrence]? = eventRuleIDs.contains(rule.id)
                    ? eventPlan?.result.filter { $0.ruleID == rule.id } : (old[rule.id]?.prior ?? (rule.hasApplied ? nil : []))
                return portable(rule, destination: destination, prior: prior)
            }
            let operation = CloudRuleOperation(id: attemptID, owner: cloud.deviceID, scope: lockScope,
                                               upserts: envelopes, deletions: deletion, plan: eventPlan)
            mergeBindings(locations.filter { scope.contains($0.key) && !$0.value.isEmpty }, account: session.accountID)
            rememberBirthdaySources(proposed.rules.filter { scope.contains($0.id) }, account: session.accountID)
            do {
                let localLocations = locations.filter { scope.contains($0.key) && !$0.value.isEmpty }
                let claimed = try await cloud.claim(operation, localBefore: previous, localAfter: desired,
                                                    localPlan: try JSONEncoder().encode(CloudLocalWritePlan(destinations: localLocations, removalGuard: removalGuard)), in: session)
                restoreCloud(claimed)
                let current = try await cloud.verifyOwnership(attemptID, in: claimed)
                guard !cloudResetPending else { throw CloudRuleError.accountChanged }
                if let removal {
                    let currentRemoval = try calendar.previewRemoval(previous: previous, ruleIDs: eventRuleIDs)
                    guard currentRemoval == removal else { throw CalendarIntegrationError.removalSelectionChanged }
                }
                if let eventPlan { _ = try calendar.applySyncPlan(eventPlan, destinations: localLocations, removalGuard: removalGuard) }
                try cloud.recordEventKitComplete(attemptID, in: current)
                let completed = try await cloud.finish(attemptID, in: current)
                restoreCloud(completed)
            } catch {
                if let refreshed = try? await cloud.refresh() {
                    if refreshed.accountID == session.accountID {
                        restoreCloud(refreshed)
                    } else {
                        cloudResetPending = true
                        cloudReady = false
                    }
                }
                throw error
            }
        } else {
            guard try await cloud.refresh() == nil, !cloudResetPending else {
                cloudReady = false
                cloudResetPending = true
                throw RuleOperationError(L10n.text("iCloud 帳號已變更，未更動行事曆。請重試。", "The iCloud account changed. No calendar events changed. Try again."))
            }
            if let eventPlan {
                var journal = LocalRuleWriteJournal(plan: eventPlan, destinations: locations, proposed: proposed,
                                                    removalGuard: removalGuard)
                try journal.write(localOnly: hasCloudAccount)
                awaitingLocalRecovery = true
                let result = try calendar.applySyncPlan(eventPlan, destinations: locations, removalGuard: removalGuard)
                try finishLocal(&journal, occurrences: result)
            } else {
                try proposed.write(localOnly: hasCloudAccount)
                snapshot = proposed
            }
        }
    }

    private func finishLocal(_ journal: inout LocalRuleWriteJournal, occurrences: [PlannedOccurrence]) throws {
        let scope = journal.plan.ruleIDs
        var result = journal.proposed
        result.occurrences.removeAll { scope.contains($0.ruleID) }
        result.occurrences += occurrences
        var zeros = result.knownEmptyRuleIDs ?? []
        zeros.subtract(scope)
        let nonempty = Set(occurrences.map(\.ruleID))
        zeros.formUnion(result.rules.filter {
            scope.contains($0.id) && $0.hasApplied && !nonempty.contains($0.id)
        }.map(\.id))
        result.knownEmptyRuleIDs = zeros
        // Persist confirmation before any further disk operation. If saving the rules
        // fails we can redo only that part without replaying EventKit.
        journal.proposed = result
        journal.eventKitComplete = true
        try journal.write(localOnly: hasCloudAccount)
        try result.write(localOnly: hasCloudAccount)
        try LocalRuleWriteJournal.clear(localOnly: hasCloudAccount)
        awaitingLocalRecovery = false
        snapshot = result
    }

    private func recoverLocal() async {
        do {
            guard var journal = try LocalRuleWriteJournal.read(localOnly: hasCloudAccount) else {
                awaitingLocalRecovery = false
                return
            }
            awaitingLocalRecovery = true
            guard !cloudResetPending else { return }
            if journal.eventKitComplete {
                try finishLocal(&journal, occurrences: journal.proposed.occurrences.filter { journal.plan.ruleIDs.contains($0.ruleID) })
            } else {
                let result = try calendar.applySyncPlan(journal.plan, destinations: journal.destinations,
                                                       recovering: true, removalGuard: journal.removalGuard)
                try finishLocal(&journal, occurrences: result)
            }
        } catch {
            cloudReadError = error.localizedDescription
        }
    }

    private func recoverCloud(_ session: CloudRuleSession) async {
        guard !cloudBusy, !cloudResetPending,
              let journal = cloud.recoverableJournal(in: session) else { return }
        cloudBusy = true
        defer { cloudBusy = false }
        do {
            let reconciled = try await cloud.resolveAcquiringJournal(in: session)
            restoreCloud(reconciled)
            guard let active = cloud.recoverableJournal(in: reconciled) else { return }
            if reconciled.ledger.completed.contains(active.operation.id) {
                let complete = try await cloud.finish(active.operation.id, in: reconciled)
                restoreCloud(complete)
                return
            }
            try cloud.clearSupersededJournal(in: reconciled)
            guard let operation = reconciled.ledger.pending.first(where: { $0.id == active.operation.id }),
                  operation.owner == cloud.deviceID, !cloudResetPending else { return }
            if operation.interrupted {
                guard active.stage == .eventKitComplete else { return }
                // Only publish an already verified result; never resume EventKit while frozen.
                restoreCloud(try await cloud.finish(operation.id, in: reconciled))
                return
            }
            let latest = try await cloud.verifyOwnership(operation.id, in: reconciled)
            guard !cloudResetPending else { throw CloudRuleError.accountChanged }
            if active.stage != .eventKitComplete {
                if let plan = operation.plan {
                    guard let data = active.localPlan else { throw CalendarIntegrationError.invalidPlan }
                    let local = try JSONDecoder().decode(CloudLocalWritePlan.self, from: data)
                    _ = try calendar.applySyncPlan(plan, destinations: local.destinations,
                                                   recovering: true, removalGuard: local.removalGuard)
                }
                try cloud.recordEventKitComplete(operation.id, in: latest)
            }
            let complete = try await cloud.finish(operation.id, in: latest)
            restoreCloud(complete)
        } catch {
            // Unknown cloud outcomes stay pending. Only a verified owner with an EventKit
            // recovery failure can mark this attempt interrupted.
            if let eventError = error as? CalendarIntegrationError,
               eventError.requiresManualRecovery,
               let latest = try? await cloud.refresh(), latest.accountID == session.accountID,
               latest.ledger.pending.contains(where: { $0.id == journal.operation.id && $0.owner == cloud.deviceID }),
               let frozen = try? await cloud.markInterrupted(journal.operation.id, in: latest) {
                restoreCloud(frozen)
            }
            cloudReadError = error.localizedDescription
        }
    }

    private func pendingReason(_ id: UUID) -> String? {
        let pending = pendingOperation(id)
        return pending != nil && pending?.interrupted == false
            ? L10n.text("待完成", "Pending") : nil
    }

    private func refreshBeforeOrphans() async throws {
        try requireCalendarMaintenance()
        guard !cloudBusy, !cloudRefreshing else { throw CloudRuleError.reserved }
        let priorAccount = cloudSession?.accountID
        await load()
        guard cloudSession?.accountID == priorAccount else { throw CloudRuleError.accountChanged }
        _ = try orphanProtectedIDs()
    }

    private func verifiedBindings(_ account: String) -> [UUID: VerifiedCalendarBinding] {
        let data = UserDefaults.standard.data(forKey: cloudLocalKey("rules.verifiedBindings." + account))
        return data.flatMap { try? JSONDecoder().decode([UUID: VerifiedCalendarBinding].self, from: $0) } ?? [:]
    }

    private func storeVerifiedBinding(_ id: String, descriptor: CalendarSyncDestination, for rule: UUID, session: CloudRuleSession) throws {
        let account = session.accountID
        guard let entry = session.ledger.rules.first(where: { $0.id == rule }) else { throw CloudRuleError.conflict }
        var values = verifiedBindings(account)
        values[rule] = VerifiedCalendarBinding(id: id, descriptor: descriptor, evidence: CloudDestinationEvidence(entry))
        let data = try JSONEncoder().encode(values)
        UserDefaults.standard.set(data, forKey: cloudLocalKey("rules.verifiedBindings." + account))
        mergeBindings([rule: id], account: account)
    }

    private func originalCalendarTitle(_ ruleID: UUID) -> String? {
        let entry = cloudSession?.ledger.rules.first { $0.id == ruleID }
            ?? pendingOperation(ruleID)?.upserts.first { $0.id == ruleID }
        guard let destination = entry?.destination else { return nil }
        return destination.sourceTitle.isEmpty ? destination.title : "\(destination.title) · \(destination.sourceTitle)"
    }

    private func reviewThaw(_ ruleID: UUID) async throws -> CloudThawProposal {
        try requireCalendarMaintenance()
        guard !cloudBusy, !cloudRefreshing, !cloudResetPending, let account = cloudSession?.accountID else {
            throw CloudRuleError.unavailable
        }
        cloudBusy = true
        defer { cloudBusy = false; if cloudResetPending { Task { await load() } } }
        guard let latest = try await cloud.refresh(), latest.accountID == account, !cloudResetPending else {
            throw CloudRuleError.accountChanged
        }
        try observeWait(latest)
        restoreCloud(latest)
        cloudReady = true
        return try inspectThaw(ruleID)
    }

    private func inspectThaw(_ ruleID: UUID) throws -> CloudThawProposal {
        try requireCalendarMaintenance()
        guard cloudReady, !cloudResetPending, let session = cloudSession else { throw CloudRuleError.unavailable }
        let expired = pendingWait.expiredOperations(touching: ruleID)
        if session.ledger.tombstones.contains(ruleID) {
            return .init(accountID: session.accountID, operation: nil, expired: expired, affected: [ruleID],
                         deleted: true, locations: [:], previous: [], observed: [])
        }
        if let rule = snapshot.rules.first(where: { $0.id == ruleID }), let parent = rule.parent,
           freezeReason(parent) != nil, interruptedOperation(ruleID) == nil,
           pendingWait.expiredOperations(touching: parent).isDisjoint(with: expired) {
            throw RuleOperationError(L10n.text("請先解除依據規則的凍結。", "Unfreeze the parent rule first."))
        }
        var affected = Set([ruleID])
        for id in expired { affected.formUnion(pendingWait.confirmedWaiting[id] ?? []) }
        let scopeOperations = session.ledger.pending.filter { op in affected.contains { operationTouches(op, ruleID: $0) } }
        let operation = pendingOperation(ruleID)
        let concluded = session.ledger.completed.union(session.ledger.retired ?? [])
        if scopeOperations.contains(where: { $0 != operation || !$0.interrupted }) ||
            expired.contains(where: { $0 != operation?.id && !concluded.contains($0) }) {
            throw RuleOperationError(L10n.text("尚無法確認原裝置已停止寫入。規則保持凍結，待同步確認。", "The original writer has not been verified as stopped. The rule remains frozen until sync can confirm it."))
        }
        affected.formUnion(operation?.plan?.ruleIDs ?? [])
        var locations: [UUID: String] = [:]
        var previous: [PlannedOccurrence] = []
        for id in affected {
            if session.ledger.tombstones.contains(id) { continue }
            guard let entry = session.ledger.rules.first(where: { $0.id == id }) else {
                // A new pending rule has no confirmed baseline to unlock.
                throw CalendarIntegrationError.invalidPlan
            }
            guard let calendarID = knownDestinations[id] else {
                throw RuleOperationError(directFrozen[id] ?? CalendarIntegrationError.noDestination.localizedDescription)
            }
            guard entry.prior != nil || !entry.rule.hasApplied else { throw CalendarIntegrationError.invalidPlan }
            locations[id] = calendarID
            previous += (entry.prior ?? []).map { item in
                var item = item
                item.calendarID = calendarID
                return item
            }
        }
        let plan = operation?.plan
        var attempted = (plan?.previous ?? []) + (plan?.desired ?? []) + (plan?.result ?? [])
        if let plan { attempted += plan.mutations.flatMap { [$0.old, $0.new].compactMap { $0 } } }
        let observed = try calendar.verifyOriginalForUnfreeze(previous: previous, attempted: attempted, locations: locations)
        return CloudThawProposal(accountID: session.accountID, operation: operation, expired: expired,
                                 affected: affected, deleted: false, locations: locations,
                                 previous: previous.sorted { $0.ruleID == $1.ruleID ? $0.key < $1.key : $0.ruleID.uuidString < $1.ruleID.uuidString },
                                 observed: observed)
    }

    private func confirmThaw(_ ruleID: UUID, expected: CloudThawProposal) async throws {
        try requireCalendarMaintenance()
        guard !cloudBusy, !cloudRefreshing, !cloudResetPending, cloudSession?.accountID == expected.accountID else {
            throw CloudRuleError.unavailable
        }
        cloudBusy = true
        defer {
            cloudBusy = false
            if cloudResetPending { Task { await load() } }
        }
        guard let latest = try await cloud.refresh(), latest.accountID == expected.accountID, !cloudResetPending else {
            throw CloudRuleError.accountChanged
        }
        try observeWait(latest)
        restoreCloud(latest)
        cloudReady = true
        let current = try inspectThaw(ruleID)
        guard current == expected else { throw CalendarIntegrationError.removalSelectionChanged }
        if let operation = current.operation {
            let ended = try await cloud.retireInterruptedWithoutEventWrite(operation, in: latest)
            guard !cloudResetPending else { throw CloudRuleError.accountChanged }
            try observeWait(ended)
            restoreCloud(ended)
            // A racing successful original writer may have different evidence.
            guard ended.ledger.retired?.contains(operation.id) == true else {
                throw CalendarIntegrationError.removalSelectionChanged
            }
        }
        try clearWait(current)
    }

    private func resolve(_ input: Rule, allowingVerifiedRebinding: Bool = false) throws -> RuleReconciliation {
        guard loaded else { throw RuleOperationError(L10n.text("規則尚未讀取，請返回列表後重試。", "Rules have not loaded yet. Return to the list and try again.")) }
        var rule = input
        rule.name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.category = rule.category.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.subcategory = rule.subcategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.name.isEmpty else {
            throw RuleOperationError(L10n.text("事件標題為必填，請返回規則主頁填寫。", "An event title is required. Return to the rule to enter one."))
        }
        guard rule.parent != nil || !rule.category.isEmpty else {
            throw RuleOperationError(L10n.text("分類為必填，請返回規則主頁填寫或選擇分類。", "A category is required. Return to the rule to enter or choose one."))
        }
        if let parent = snapshot.rules.first(where: { $0.id == rule.parent }) {
            guard parent.hasApplied else { throw RuleOperationError(L10n.text("請先套用依據規則。", "Apply the parent rule first.")) }
            if !allowingVerifiedRebinding {
                let existing = snapshot.rules.first { $0.id == rule.id }
                rule.target = existing?.hasApplied == true ? (existing?.target ?? "") : parent.target
            }
            rule.category = parent.category
            rule.subcategory = parent.subcategory
        }
        guard !rule.target.isEmpty else { throw RuleOperationError(L10n.text("目的行事曆為必填。請返回規則主頁，先連接行事曆並選擇目的地。", "A destination calendar is required. Return to the rule, connect Calendar, and choose a destination.")) }
        if let saved = snapshot.rules.first(where: { $0.id == rule.id }),
           saved.hasApplied && saved.target != rule.target && !allowingVerifiedRebinding {
            throw RuleOperationError(L10n.text("這條規則已套用，不能更換目的行事曆。", "This rule has already been applied. Its destination calendar cannot be changed."))
        }
        rule.hasApplied = true
        var rules = snapshot.rules
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        let map = Dictionary(grouping: rules, by: \.parent)
        var pending = [rule.id]
        var branchIDs: Set<UUID> = [rule.id]
        while let parentID = pending.popLast() {
            for child in map[parentID] ?? [] where branchIDs.insert(child.id).inserted {
                pending.append(child.id)
            }
        }
        for index in rules.indices where branchIDs.contains(rules[index].id) {
            rules[index].category = rule.category
            rules[index].subcategory = rule.subcategory
        }

        var root = rule
        var ancestors = Set<UUID>([rule.id])
        while let id = root.parent {
            guard ancestors.insert(id).inserted,
                  let node = rules.first(where: { $0.id == id && $0.hasApplied }) else {
                throw RuleOperationError(L10n.text("找不到有效的依據規則，請返回上一層確認。", "No valid parent rule was found. Go back and check the rule."))
            }
            root = node
        }
        // For a child edit the engine only needs ancestors as its date anchors and
        // the edited subtree. Sibling branches must not enter the reconciliation.
        let included = branchIDs.union(ancestors)
        let available = rules.filter { included.contains($0.id) && $0.hasApplied }
        let desired = try RuleEngine.plan(root: root, rules: available).filter { branchIDs.contains($0.ruleID) }
        let previous = snapshot.occurrences.filter { branchIDs.contains($0.ruleID) }
        return RuleReconciliation(desired: desired, previous: previous, ruleIDs: branchIDs, rules: rules)
    }

    private func preview(_ rule: Rule) throws -> RuleEventPreviewResult {
        try requireCalendarMaintenance()
        var rules = snapshot.rules.filter { $0.id != rule.id }
        rules.append(rule)
        let tree = ruleTreeRows(roots: [rule], rules: rules)
        do {
            let plan = try resolve(rule)
            let events = try calendar.previewEvents(ruleIDs: plan.ruleIDs, desired: plan.desired, previous: plan.previous)
            return RuleEventPreviewResult(rules: tree, events: events, warning: nil)
        } catch {
            let ids = Set(tree.map(\.id))
            let previous = Dictionary(grouping: snapshot.occurrences.filter { ids.contains($0.ruleID) }, by: \.ruleID)
            guard !previous.isEmpty else { throw error }
            let existing = try tree.flatMap { row in
                try calendar.existingPreviewEvents(for: row.id, previous: previous[row.id, default: []])
            }
            return RuleEventPreviewResult(
                rules: tree, events: existing,
                warning: L10n.text("目前只能查看已確認的既有事件，無法預覽這次變更。\n\(error.localizedDescription)", "Only confirmed existing events can be shown. These changes could not be previewed.\n\(error.localizedDescription)")
            )
        }
    }

    private func isDeletedInCloud(_ id: UUID) -> Bool {
        cloudSession?.ledger.tombstones.contains(id) == true
    }

    private func apply(_ rule: Rule, expected: Rule?) async throws -> Rule {
        try requireCalendarMaintenance()
        guard !isDeletedInCloud(rule.id) else { throw CloudRuleError.ruleDeleted }
        let account = cloudSession?.accountID
        do {
            guard snapshot.rules.first(where: { $0.id == rule.id }) == expected else {
                throw CloudRuleError.conflict
            }
            let plan = try resolve(rule)
            var updated = snapshot
            updated.rules = plan.rules
            try await performMutation(updated, scope: plan.ruleIDs, desired: plan.desired,
                                      previous: plan.previous, eventRuleIDs: plan.ruleIDs)
            if let account { UserDefaults.standard.removeObject(forKey: cloudLocalKey("rules.cloudDraft.\(account).\(rule.id)")) }
            return snapshot.rules.first { $0.id == rule.id } ?? rule
        } catch {
            // The claim can race another device's deletion. performMutation reloads
            // the ledger on failure; never keep an obsolete draft after a tombstone.
            if isDeletedInCloud(rule.id) {
                if let account { UserDefaults.standard.removeObject(forKey: cloudLocalKey("rules.cloudDraft.\(account).\(rule.id)")) }
                throw CloudRuleError.ruleDeleted
            }
            if let account { saveDraft(rule, account: account) }
            throw error
        }
    }

    private func batchPlan(_ edit: BatchEdit) throws -> (plan: RuleReconciliation, rows: [BatchDurationRule]) {
        guard edit.classification != nil || edit.duration != nil else {
            throw RuleOperationError(L10n.text("請指定要調整的項目。", "Choose what you want to change."))
        }
        let selected = rootRules.filter { edit.ruleIDs.contains($0.id) }
        let tree = try selectedTreeIDs(edit.ruleIDs)
        if let duration = edit.duration, !(1...999).contains(duration.count) || duration.unit == .week {
            throw RuleOperationError(L10n.text("請輸入有效的重複期間。", "Enter a valid repeat period."))
        }
        var desired: [PlannedOccurrence] = []
        var previous: [PlannedOccurrence] = []
        var affected: Set<UUID> = []
        var updates: [UUID: Rule] = [:]
        var rows: [BatchDurationRule] = []
        for var rule in selected {
            guard let duration = edit.duration else { break }
            rule.endMode = .duration
            rule.endCount = duration.count
            rule.endUnit = duration.unit
            do {
                let cutoff = try RuleEngine.cutoff(for: rule)
                if rule.hasApplied {
                    let branch = try resolve(rule)
                    guard affected.isDisjoint(with: branch.ruleIDs) else {
                        throw RuleOperationError(L10n.text("選取的規則包含重疊的分支。", "The selected rules include overlapping branches."))
                    }
                    desired += branch.desired
                    previous += branch.previous
                    affected.formUnion(branch.ruleIDs)
                } else {
                    _ = try RuleEngine.plan(root: rule, rules: [rule])
                }
                updates[rule.id] = rule
                let local = RuleEngine.civilCalendar(for: rule)
                let civilCutoff = gregorianCalendar.date(from: local.dateComponents([.year, .month, .day], from: cutoff)) ?? cutoff
                rows.append(.init(id: rule.id, title: rule.displayName, cutoff: civilCutoff, isDraft: !rule.hasApplied))
            } catch {
                throw RuleOperationError(L10n.text("「\(rule.displayName)」：\(error.localizedDescription)", "\(rule.displayName): \(error.localizedDescription)"))
            }
        }
        var rules = snapshot.rules.map { updates[$0.id] ?? $0 }
        if let classification = edit.classification {
            let category = classification.category.trimmingCharacters(in: .whitespacesAndNewlines)
            let subcategory = classification.subcategory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !category.isEmpty else { throw RuleOperationError(L10n.text("請指定移動後的分類。", "Choose the destination category.")) }
            for index in rules.indices where tree.contains(rules[index].id) {
                rules[index].category = category
                rules[index].subcategory = subcategory
            }
        }
        return (RuleReconciliation(desired: desired, previous: previous, ruleIDs: affected, rules: rules), rows)
    }

    private func previewBatch(_ edit: BatchEdit) throws -> BatchDurationPreview {
        try requireCalendarMaintenance()
        let batch = try batchPlan(edit)
        let plan = batch.plan
        let changes = try batchCalendarChanges(plan)
        return BatchDurationPreview(rules: batch.rows, changes: changes,
                                    hasChanges: plan.rules != snapshot.rules || !changes.isEmpty)
    }

    private func batchCalendarChanges(_ plan: RuleReconciliation) throws -> [CalendarChange] {
        guard !plan.ruleIDs.isEmpty else { return [] }
        return try calendar.preview(desired: plan.desired, previous: plan.previous, ruleIDs: plan.ruleIDs)
    }

    private func applyBatch(_ edit: BatchEdit) async throws {
        try requireCalendarMaintenance()
        let scope = try selectedTreeIDs(edit.ruleIDs)
        try assertWritable(scope)
        let plan = try batchPlan(edit).plan
        if plan.rules == snapshot.rules, try batchCalendarChanges(plan).isEmpty { return }
        var updated = snapshot
        updated.rules = plan.rules
        try await performMutation(updated, scope: scope, desired: plan.desired,
                                  previous: plan.previous, eventRuleIDs: plan.ruleIDs)
    }

    private var batchCategories: [BatchCategoryOption] {
        selectableCategories(rootRules.map(\.category)).map { name in
            let children = rootRules.filter { $0.category == name && !$0.subcategory.isEmpty }
            return BatchCategoryOption(name: name, subcategories: uniqueNames(children.map(\.subcategory)))
        }
    }

    private func selectedTreeIDs(_ selected: Set<UUID>) throws -> Set<UUID> {
        guard loaded, !selected.isEmpty,
              selected.isSubset(of: Set(rootRules.map(\.id))) else {
            throw RuleOperationError(L10n.text("請重新選擇要處理的根規則。", "Select the top-level rules again."))
        }
        let branches = Dictionary(grouping: snapshot.rules, by: \.parent)
        var ids = selected
        var pending = Array(ids)
        while let parent = pending.popLast() {
            for child in branches[parent] ?? [] where ids.insert(child.id).inserted {
                pending.append(child.id)
            }
        }
        return ids
    }

    private func previewRemoval(_ selected: Set<UUID>) throws -> BatchRemovalPreview {
        try previewRemoval(selected, allowChild: false)
    }

    private func previewRemoval(_ selected: Set<UUID>, allowChild: Bool) throws -> BatchRemovalPreview {
        try requireCalendarMaintenance()
        let rules = try removalRows(selected, allowChild: allowChild)
        let ids = Set(rules.map(\.id))
        let appliedIDs = Set(snapshot.rules.filter { ids.contains($0.id) && $0.hasApplied }.map(\.id))
        try assertWritable(ids, eventRuleIDs: appliedIDs)
        let previous = snapshot.occurrences.filter { appliedIDs.contains($0.ruleID) }
        if allowChild {
            let details = try calendar.previewBranchRemoval(previous: previous, ruleIDs: appliedIDs)
            return BatchRemovalPreview(rules: rules, events: details.removals, retained: details.retained)
        }
        let events = appliedIDs.isEmpty ? [] : try calendar.previewRemoval(previous: previous, ruleIDs: appliedIDs)
        return BatchRemovalPreview(rules: rules, events: events)
    }

    private func removalRows(_ selected: Set<UUID>, allowChild: Bool) throws -> [BatchRemovalRule] {
        let eligible = allowChild ? snapshot.rules : rootRules
        let roots = eligible.filter { selected.contains($0.id) }
        guard loaded, !selected.isEmpty, roots.count == selected.count, !allowChild || selected.count == 1 else {
            throw RuleOperationError(L10n.text("找不到要移除的規則，請返回清單重新選擇。", "The rules to delete could not be found. Return to the list and select again."))
        }
        return ruleTreeRows(roots: roots, rules: snapshot.rules)
    }

    private func removeSelected(_ selected: Set<UUID>, _ expected: BatchRemovalPreview) async throws {
        try await removeSelected(selected, expected, allowChild: false)
    }

    private func removeSelected(_ selected: Set<UUID>, _ expected: BatchRemovalPreview, allowChild: Bool) async throws {
        let ids = Set(expected.rules.map(\.id))
        let appliedIDs = Set(snapshot.rules.filter { ids.contains($0.id) && $0.hasApplied }.map(\.id))
        try assertWritable(ids, eventRuleIDs: appliedIDs)
        let current = try previewRemoval(selected, allowChild: allowChild)
        guard current.rules == expected.rules, current.events == expected.events else { throw CalendarIntegrationError.removalSelectionChanged }
        var updated = snapshot
        updated.rules.removeAll { ids.contains($0.id) }
        updated.occurrences.removeAll { ids.contains($0.ruleID) }
        try await performMutation(updated, scope: ids, previous: snapshot.occurrences.filter { appliedIDs.contains($0.ruleID) },
                                  eventRuleIDs: appliedIDs, removal: expected.events)
    }

    private func birthdayStatus(_ candidate: BirthdayCandidate) -> BirthdayDuplicateStatus {
        let sameContact = rootRules.filter {
            $0.birthdaySource?.contactID == candidate.source.contactID &&
            $0.birthdaySource?.isLunar == candidate.source.isLunar
        }
        if sameContact.contains(where: { $0.birthdaySource == candidate.source }) { return .imported }
        if !sameContact.isEmpty { return .changed }
        let possibleTitles = candidate.duplicateTitles
        if rootRules.contains(where: { rule in
            guard rule.birthdaySource == nil,
                  possibleTitles.contains(rule.name.trimmingCharacters(in: .whitespacesAndNewlines)),
                  rule.period == .year, rule.weekdayPattern == nil else { return false }
            if candidate.isLunar {
                return rule.kind == .lunar && rule.lunarMonth == candidate.month &&
                       rule.lunarDay == candidate.day && rule.lunarIsLeap == candidate.isLeapMonth
            }
            return rule.kind == .gregorian &&
                   gregorianCalendar.component(.month, from: rule.start) == candidate.month &&
                   gregorianCalendar.component(.day, from: rule.start) == candidate.day
        }) { return .possibleDuplicate }
        return .available
    }

    private func importBirthdays(_ candidates: [BirthdayCandidate], years: Int, target: String, applyNow: Bool,
                                 category: String, subcategory: String, preferNickname: Bool) async throws {
        try requireCalendarMaintenance()
        guard loaded, (1...999).contains(years), !candidates.isEmpty else {
            throw RuleOperationError(L10n.text("請選擇要匯入的生日並填寫有效的期間。", "Select birthdays to import and enter a valid repeat period."))
        }
        let category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let subcategory = subcategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !category.isEmpty else { throw RuleOperationError(L10n.text("請輸入生日規則的分類。", "Enter a category for the birthday rules.")) }
        guard calendar.destinations.contains(where: { $0.id == target && $0.isWritable }) else {
            throw RuleOperationError(L10n.text("目的行事曆已不可用，請重新選擇。", "The destination calendar is no longer available. Choose another calendar."))
        }
        var updated = snapshot
        var imported: [Rule] = []
        var planned: [PlannedOccurrence] = []
        guard Set(candidates.map(\.id)).count == candidates.count else {
            throw RuleOperationError(L10n.text("選取清單有重複的生日，請返回確認。", "The selection contains duplicate birthdays. Go back and review it."))
        }
        for candidate in candidates {
            switch birthdayStatus(candidate) {
            case .imported:
                throw RuleOperationError(L10n.text("「\(candidate.name)」已匯入，請重新選擇。", "\(candidate.name) has already been imported. Choose a different entry."))
            case .available, .possibleDuplicate, .changed:
                break
            }
            var rule = Rule(name: candidate.eventTitle(preferNickname: preferNickname), kind: candidate.isLunar ? .lunar : .gregorian,
                            date: "", lunarMonth: candidate.month, lunarDay: candidate.day,
                            lunarIsLeap: candidate.isLeapMonth,
                            category: category, subcategory: subcategory)
            rule.birthdaySource = candidate.source
            rule.endMode = .duration
            rule.endCount = years
            rule.endUnit = .year
            if !candidate.isLunar {
                var year = gregorianCalendar.component(.year, from: Date())
                var foundDate: Date?
                for _ in 0..<9 {
                    if let day = gregorianCalendar.date(from: DateComponents(year: year, month: candidate.month, day: candidate.day)),
                       gregorianCalendar.component(.month, from: day) == candidate.month,
                       gregorianCalendar.component(.day, from: day) == candidate.day,
                       day >= gregorianCalendar.startOfDay(for: Date()) {
                        foundDate = day
                        break
                    }
                    year += 1
                }
                guard let foundDate else {
                    throw RuleOperationError(L10n.text("無法判讀「\(candidate.name)」的生日日期。", "Could not read the birthday for \(candidate.name)."))
                }
                rule.start = foundDate
                // Birthdays are fixed month/day, not the final day of every February.
                rule.monthEnd = false
            }
            rule.target = target
            if applyNow {
                rule.hasApplied = true
                do {
                    planned += try RuleEngine.plan(root: rule, rules: [rule])
                } catch {
                    throw RuleOperationError(L10n.text("「\(candidate.name)」：\(error.localizedDescription)", "\(candidate.name): \(error.localizedDescription)"))
                }
            }
            imported.append(rule)
        }
        updated.rules.append(contentsOf: imported)
        let ids = Set(imported.map(\.id))
        try await performMutation(updated, scope: ids, desired: planned, eventRuleIDs: applyNow ? ids : [])
        if !applyNow, imported.count == 1, let only = imported.first {
            path.append(.edit(only, isNew: true))
        }
    }

    private var toolsRow: some View {
        HStack {
            Button {
                isShowingBatch = true
            } label: {
                Label {
                    Text(L10n.text("批次調整", "Batch Edit"))
                } icon: {
                    Image(systemName: "checklist")
                        .padding(.leading, 1) // Account for the checklist and title glyphs independently.
                }
                .frame(minHeight: 44)
            }
            .disabled(!calendar.hasFullAccess || !loaded || rootRules.isEmpty)
            .accessibilityIdentifier("start-batch")
            Spacer(minLength: 8)
            Button(action: showAppleCalendar) {
                Label(L10n.text("行事曆", "Calendar"), systemImage: "calendar")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("open-apple-calendar")
        }
        .font(.subheadline.weight(.semibold))
    }

    private var intro: some View {
        Label(L10n.text("在這裡訂規則，在原本的行事曆看結果。", "Set up rules here and see the events in the calendar you already use."), systemImage: "point.3.connected.trianglepath.dotted")
            .font(.subheadline)
            .foregroundStyle(slate)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(slate.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
    }

    private var emptyState: some View {
        VStack(alignment: .trailing, spacing: 0) {
            addRuleButton
            ContentUnavailableView {
                Label(L10n.text("還沒有規則", "No Rules Yet"), systemImage: "calendar.badge.plus")
            } description: {
                Text(L10n.text("新增一條日期規則，或從通訊錄選擇生日匯入。", "Add a rule or import birthdays from Contacts."))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var addRuleButton: some View {
        Button { isAdding = true } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(!calendar.hasFullAccess)
        .accessibilityLabel(L10n.text("新增規則", "New Rule"))
        .accessibilityIdentifier("add-rule")
    }

    private func category(_ title: String, rules: [Rule], isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                groupLabel(.init(category: title))
                    .padding(.leading, 3)
                if isFirst { addRuleButton }
            }
            let subcategories = uniqueNames(rules.map(\.subcategory).filter { !$0.isEmpty })
            let groupOrder = subcategories + (rules.contains { $0.subcategory.isEmpty } ? [""] : [])
            ForEach(groupOrder, id: \.self) { subcategory in
                let group = rules.filter { $0.subcategory == subcategory }
                VStack(alignment: .leading, spacing: 0) {
                    if !subcategory.isEmpty {
                        groupLabel(.init(category: title, subcategory: subcategory))
                            .padding(.horizontal, 8)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(group) { rule in
                        if !subcategory.isEmpty || rule.id != group.first?.id {
                            Divider().padding(.leading, 15)
                        }
                        NavigationLink(value: Route.edit(rule, isNew: !rule.hasApplied)) {
                            ruleRow(rule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(card, in: RoundedRectangle(cornerRadius: 18))
                .padding(.leading, 22)
            }
        }
    }

    private func groupLabel(_ key: GroupAppearanceKey) -> some View {
        let appearance = groupAppearance(key)
        return HStack(spacing: 6) {
            Button {
                appearanceGroup = key
            } label: {
                Image(systemName: appearance.symbol(or: key.defaultSymbol))
                    .foregroundStyle(appearance.tint(or: .secondary))
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!calendar.hasFullAccess)
            .accessibilityLabel(L10n.text("調整\(key.title)圖示與顏色", "Change icon and color for \(key.title)"))
            .accessibilityIdentifier(key.subcategory == nil ? "category-appearance" : "subcategory-appearance")
            Text(key.title)
                .font(key.subcategory == nil ? .headline : .footnote.weight(.semibold))
                .foregroundStyle(key.subcategory == nil ? .primary : .secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
    }

    private func ruleRow(_ rule: Rule) -> some View {
        HStack(spacing: 11) {
            Image(systemName: rule.displayAppearance.symbol(or: rule.defaultSymbol))
                .foregroundStyle(rule.displayAppearance.tint(or: slate))
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(rule.displayAppearance.tint(or: slate).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            let next = snapshot.occurrences.lazy.filter { $0.ruleID == rule.id && $0.start > Date() }.min { $0.start < $1.start }
            let status = freezeReason(rule.id).map { L10n.text("凍結：", "Frozen: ") + $0 }
                ?? pendingReason(rule.id)
                ?? (rule.hasApplied
                ? next.map { occurrence in
                    let civil = occurrence.isAllDay ? gregorianCalendar : RuleEngine.civilCalendar(for: rule)
                    let day = L10n.text("下次 ", "Next: ") + dateCaption(occurrence.start, calendar: civil)
                    return occurrence.isAllDay ? day : "\(day) \(timeCaption(occurrence.start, calendar: civil))"
                } ?? L10n.text("無後續日期", "No Upcoming Date")
                : L10n.text("未套用", "Not Applied"))
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
            VStack(alignment: .leading, spacing: 4) {
                layout {
                    Text(rule.displayName)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    Text(rule.homeRecurrenceCaption)
                        .accessibilityLabel(rule.recurrenceCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(status)
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(minHeight: 57)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var addSheet: some View {
        NavigationStack {
            List {
                ForEach(RuleKind.allCases) { kind in
                    Button {
                        guard calendar.hasFullAccess else { return }
                        var rule = Rule(name: "", kind: kind, date: kind.dates.first ?? "", category: "")
                        if kind == .solar {
                            rule.pinSolarTimeZone()
                            rule.start = RuleEngine.civilCalendar(for: rule).startOfDay(for: Date())
                            rule.useSolarDefaultDuration()
                        }
                        isAdding = false
                        path.append(.edit(rule, isNew: true))
                    } label: {
                        Label { VStack(alignment: .leading, spacing: 4) {
                            Text(kind.displayLabel).foregroundStyle(.primary)
                            Text(kind.subtitle).font(.caption).foregroundStyle(.secondary)
                        } } icon: { Image(systemName: kind.symbol) }
                    }
                }
            }
            .navigationTitle(L10n.text("新增規則", "New Rule"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("取消", "Cancel")) { isAdding = false } } }
        }
        .tint(slate)
    }

}

private struct AppearanceEditSheet: View {
    let title: String
    let defaultSymbol: String
    let onSave: (RuleAppearance) async throws -> Void
    @State private var saving = false
    @State private var choice: RuleAppearance
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    init(title: String, initial: RuleAppearance, defaultSymbol: String,
         onSave: @escaping (RuleAppearance) async throws -> Void) {
        self.title = title
        self.defaultSymbol = defaultSymbol
        self.onSave = onSave
        _choice = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                AppearancePicker(title: title, appearance: $choice, defaultSymbol: defaultSymbol, defaultColor: slate)
                    .padding(20)
            }
            .navigationTitle(L10n.text("圖示與顏色", "Icon and Color"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("完成", "Done")) {
                        guard !saving else { return }
                        saving = true
                        let value = choice
                        Task { @MainActor in
                            defer { saving = false }
                            do {
                                try await onSave(value)
                                dismiss()
                            } catch { failure = error.localizedDescription }
                        }
                    }
                    .disabled(saving)
                }
            }
            .alert(L10n.text("無法儲存外觀", "Could Not Save Appearance"), isPresented: Binding(
                get: { failure != nil }, set: { if !$0 { failure = nil } }
            )) {
                Button(L10n.text("好", "OK"), role: .cancel) { failure = nil }
            } message: { Text(failure ?? "") }
        }
    }
}

private func ruleTreeRows(roots: [Rule], rules: [Rule]) -> [BatchRemovalRule] {
    let children = Dictionary(grouping: rules, by: \.parent)
    var pending = roots.reversed().map { (rule: $0, depth: 0) }
    var visited = Set<UUID>()
    var rows: [BatchRemovalRule] = []
    while let (rule, depth) = pending.popLast() {
        guard visited.insert(rule.id).inserted else { continue }
        rows.append(.init(id: rule.id, title: rule.displayName, depth: depth))
        pending.append(contentsOf: children[rule.id, default: []].reversed().map { ($0, depth + 1) })
    }
    return rows
}

private struct RuleEditor: View {
    @State private var rule: Rule
    @State private var baseline: Rule?
    @State private var emptyCutoffSchedule: Rule?
    @State private var exitBaseline: Rule
    @State private var pendingDiscard = false
    @State private var exitAction: ExitAction?
    private enum ExitAction { case apply, discard }
    @State private var operationError: String?
    @State private var connecting = false
    @State private var collapsedBranches: Set<UUID> = []
    @State private var editingAppearance = false
    @State private var showingDeletion = false
    @State private var didDelete = false
    @State private var followsSuggestedTitle: Bool
    @State private var followsSuggestedCategory: Bool
    @State private var followsCategoryDestination: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    let parent: Rule?
    let allRules: [Rule]
    private let isFreshRule: Bool
    @ObservedObject var calendar: CalendarIntegration
    let preview: (Rule) throws -> RuleEventPreviewResult
    let onApply: (Rule, Rule?) async throws -> Rule
    let onApplied: () -> Void
    let previewDeletion: (UUID) throws -> BatchRemovalPreview
    let onDelete: (UUID, BatchRemovalPreview) async throws -> Void
    let onDeleted: () -> Void
    let onSaveAppearance: (UUID, RuleAppearance) async throws -> Bool
    let frozenReason: String?
    let thawTitle: String?
    let hiddenRuleIDs: Set<UUID>
    let onThaw: (() -> Void)?
    @State private var applying = false
    @State private var compareBaseline: Rule?
    let onOpenChild: (Rule, Bool) -> Void

    init(initial: Rule, isNew: Bool, parent: Rule?, allRules: [Rule], calendar: CalendarIntegration,
         preview: @escaping (Rule) throws -> RuleEventPreviewResult, onApply: @escaping (Rule, Rule?) async throws -> Rule,
         onApplied: @escaping () -> Void,
         previewDeletion: @escaping (UUID) throws -> BatchRemovalPreview,
         onDelete: @escaping (UUID, BatchRemovalPreview) async throws -> Void,
         onDeleted: @escaping () -> Void,
         onSaveAppearance: @escaping (UUID, RuleAppearance) async throws -> Bool,
         frozenReason: String?, hiddenRuleIDs: Set<UUID>, thawTitle: String?, onThaw: (() -> Void)?,
         onOpenChild: @escaping (Rule, Bool) -> Void) {
        let isFresh = isNew && !allRules.contains { $0.id == initial.id }
        self.isFreshRule = isFresh
        let shouldSuggest = isFresh && initial.name.isEmpty
        let shouldSuggestCategory = isFresh && initial.category.isEmpty
        var startingRule = initial
        if shouldSuggest, let suggestion = startingRule.suggestedTitle { startingRule.name = suggestion }
        if shouldSuggestCategory, let suggestion = startingRule.suggestedCategory { startingRule.category = suggestion }
        _followsSuggestedTitle = State(initialValue: shouldSuggest)
        _followsSuggestedCategory = State(initialValue: shouldSuggestCategory)
        _followsCategoryDestination = State(initialValue: isFresh && parent == nil && initial.target.isEmpty)
        _rule = State(initialValue: startingRule)
        _baseline = State(initialValue: isNew ? nil : initial)
        _compareBaseline = State(initialValue: isFresh ? nil : initial)
        _exitBaseline = State(initialValue: startingRule)
        self.parent = parent
        self.allRules = allRules
        self.calendar = calendar
        self.preview = preview
        self.onApply = onApply
        self.onApplied = onApplied
        self.previewDeletion = previewDeletion
        self.onDelete = onDelete
        self.onDeleted = onDeleted
        self.onSaveAppearance = onSaveAppearance
        self.frozenReason = frozenReason
        self.thawTitle = thawTitle
        self.hiddenRuleIDs = hiddenRuleIDs
        self.onThaw = onThaw
        self.onOpenChild = onOpenChild
    }

    private struct TreeRow: Identifiable {
        let item: Rule
        let depth: Int
        let hasChildren: Bool
        var id: UUID { item.id }
    }

    private var ruleCalendar: Calendar {
        var current = rule
        var visited = Set<UUID>()
        while let id = current.parent, visited.insert(id).inserted,
              let ancestor = allRules.first(where: { $0.id == id }) { current = ancestor }
        return RuleEngine.civilCalendar(for: current)
    }

    private var children: [Rule] { allRules.filter { $0.parent == rule.id } }

    private var visibleTreeRows: [TreeRow] {
        let branches = Dictionary(grouping: allRules, by: \.parent)
        func walk(_ parentID: UUID, depth: Int) -> [TreeRow] {
            (branches[parentID] ?? []).flatMap { node in
                let hasChildren = !(branches[node.id] ?? []).isEmpty
                let row = TreeRow(item: node, depth: depth, hasChildren: hasChildren)
                return hasChildren && !collapsedBranches.contains(node.id)
                    ? [row] + walk(node.id, depth: depth + 1)
                    : [row]
            }
        }
        return walk(rule.id, depth: 0)
    }

    private var dirty: Bool { baseline != rule }
    private var hasUnsavedChanges: Bool { exitBaseline != rule }
    private var hasTitle: Bool { !rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var trimmedCategory: String { rule.category.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var suggestedDestinationID: String {
        guard followsCategoryDestination else { return "" }
        return categoryCalendarPresets(rules: allRules, destinations: calendar.destinations)[trimmedCategory] ?? ""
    }
    private var destinationID: String {
        if rule.hasApplied { return rule.target }
        return parent?.target ?? (followsCategoryDestination ? suggestedDestinationID : rule.target)
    }
    private var previewRule: Rule {
        var submitted = rule
        submitted.target = destinationID
        return submitted
    }
    private var hasDestination: Bool { calendar.destinations.contains { $0.id == destinationID && $0.isWritable } }
    private var canApply: Bool { frozenReason == nil && !applying && hasTitle && (parent != nil || !trimmedCategory.isEmpty) && hasDestination }
    private var isDestinationLocked: Bool { parent != nil || baseline?.hasApplied == true }
    private var chosenDestination: String {
        let id = destinationID
        if let destination = calendar.destinations.first(where: { $0.id == id }) {
            return destination.isWritable ? destination.displayTitle : L10n.text("\(destination.displayTitle)（唯讀）", "\(destination.displayTitle) (read-only)")
        }
        return id.isEmpty ? L10n.text("尚未選擇", "Not Selected") : L10n.text("已無法使用", "No Longer Available")
    }
    private var availablePeriods: [PeriodUnit] {
        switch rule.kind {
        case .gregorian: PeriodUnit.allCases
        case .lunar: [.year, .month]
        case .solar: [.year]
        }
    }
    private var categoryOptions: [String] {
        selectableCategories(allRules.filter { $0.parent == nil }.map(\.category))
    }
    private var subcategoryOptions: [String] {
        uniqueNames(allRules.filter {
            $0.parent == nil && $0.category == trimmedCategory && !$0.subcategory.isEmpty
        }.map(\.subcategory))
    }
    private var allowsMonthEnd: Bool {
        rule.kind == .gregorian && (rule.period == .year || rule.period == .month) && rule.weekdayPattern == nil &&
        gregorianCalendar.component(.day, from: rule.start) == gregorianCalendar.range(of: .day, in: .month, for: rule.start)?.last
    }

    var body: some View {
        Form {
            Group {
            if let parent {
                Section {
                    LabeledContent(L10n.text("依據規則", "Parent Rule"), value: parent.displayName)
                    Picker(L10n.text("相對日期", "Relative Date"), selection: $rule.position) {
                        ForEach(RelativePosition.allCases) { Text($0.displayLabel).tag($0) }
                    }
                    if rule.position != .same {
                        Stepper(L10n.text("間隔：\(rule.offsetDays) 天", "Offset: \(rule.offsetDays) \(PeriodUnit.day.displayLabel(count: rule.offsetDays))"), value: $rule.offsetDays, in: 1...999)
                    }
                } header: { Text(L10n.text("延伸日期", "Follow-up Date")) }
            } else {
                rootDate
            }

            Section {
                HStack(spacing: 9) {
                    Button {
                        editingAppearance = true
                    } label: {
                        Image(systemName: rule.displayAppearance.symbol(or: rule.defaultSymbol))
                            .foregroundStyle(rule.displayAppearance.tint(or: slate))
                            .frame(width: 44, height: 44)
                            .background(rule.displayAppearance.tint(or: slate).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.text("調整規則圖示與顏色", "Change the Rule’s Icon and Color"))
                    .accessibilityIdentifier("rule-appearance")
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.text("事件標題（必填）", "Event Title (required)"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(hasTitle ? Color.primary : requiredFieldTint)
                            .accessibilityHidden(true)
                        TextField(L10n.text("輸入事件標題", "Enter an event title"), text: Binding(
                            get: { rule.name },
                            set: {
                                followsSuggestedTitle = false
                                rule.name = $0
                            }
                        ))
                            .accessibilityLabel(L10n.text("事件標題（必填）", "Event Title (required)"))
                            .accessibilityIdentifier("rule-title")
                    }
                }
                if parent == nil {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                    layout {
                        CategoryEntryField(selection: Binding(
                            get: { rule.category },
                            set: {
                                followsSuggestedCategory = false
                                rule.category = $0
                            }
                        ), options: categoryOptions, isSubcategory: false,
                                           fieldID: "rule-category", menuID: "category-options")
                        CategoryEntryField(selection: $rule.subcategory, options: subcategoryOptions, isSubcategory: true,
                                           fieldID: "rule-subcategory", menuID: "subcategory-options")
                    }
                }
                calendarFields
            }

            if parent == nil { cutoff }

            Section {
                Toggle(L10n.text("整日", "All Day"), isOn: Binding(
                    get: { rule.timing == .allDay },
                    set: { rule.timing = $0 ? .allDay : .timed }
                ))
                .accessibilityIdentifier("all-day-toggle")
                if rule.timing == .timed {
                    RuleDateField(title: L10n.text("開始時間", "Start Time"), selection: $rule.startTime, kind: .time, civilCalendar: ruleCalendar)
                        .id("single-event-time")
                }
                if rule.timing == .allDay {
                    Stepper(L10n.text("持續期間：\(rule.durationDays) 日", "Duration: \(rule.durationDays) \(PeriodUnit.day.displayLabel(count: rule.durationDays))"), value: $rule.durationDays, in: 1...365)
                        .accessibilityIdentifier("single-event-days")
                } else {
                    Stepper(L10n.text("持續期間：\(hoursLabel) 小時", "Duration: \(hoursLabel) \(rule.durationHalfHours == 2 ? "hour" : "hours")"), value: $rule.durationHalfHours, in: 1...48)
                        .accessibilityIdentifier("single-event-hours")
                }
            } header: { Text(L10n.text("單次事件", "Each Event")) }
            }
            .disabled(frozenReason != nil)

            Section {
                if children.isEmpty {
                    Text(L10n.text("尚無子規則", "No Child Rules Yet")).foregroundStyle(.secondary)
                }
                ForEach(visibleTreeRows.filter { !hiddenRuleIDs.contains($0.id) }) { row in
                    treeRow(row)
                }
                Button {
                    var child = Rule(name: "", kind: rule.kind, date: rule.date, category: rule.category, subcategory: rule.subcategory, parent: rule.id)
                    child.startTime = ruleCalendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? child.startTime
                    child.target = rule.target
                    onOpenChild(child, true)
                } label: {
                    Label(L10n.text("新增子規則", "Add Child Rule"), systemImage: "plus")
                }
                .disabled(baseline == nil || frozenReason != nil)
            } header: { Text(L10n.text("子規則", "Child Rules")) }
              footer: { Text(baseline == nil ? L10n.text("先套用這條規則，才能新增它的子規則。", "Apply this rule before adding child rules.") : L10n.text("可編輯直接子規則；縮排的下游項目僅供查看。", "You can edit direct child rules here. Deeper levels are shown for reference.")) }
            if calendar.hasFullAccess {
                EventPreview(rule: previewRule, savedRules: allRules, civilCalendar: ruleCalendar, load: preview)
            }
            if !isFreshRule && frozenReason == nil {
                Section {
                    Button { showingDeletion = true } label: {
                        Label(L10n.text("刪除規則", "Delete Rule"), systemImage: "trash")
                            .foregroundStyle(requiredFieldTint)
                    }
                    .accessibilityIdentifier("delete-rule")
                }
            }
        }
        .onChange(of: rule.suggestedTitle) { _, suggestion in
            if followsSuggestedTitle { rule.name = suggestion ?? "" }
        }
        .onChange(of: rule.suggestedCategory) { _, suggestion in
            if followsSuggestedCategory { rule.category = suggestion ?? "" }
        }
        .disabled(applying)
        .safeAreaInset(edge: .top) {
            if let frozenReason {
                HStack {
                    Label(frozenReason, systemImage: "lock")
                    Spacer()
                    if let onThaw {
                        Button(thawTitle ?? L10n.text("解除凍結", "Unfreeze"), action: onThaw)
                    }
                }.font(.footnote).padding().background(.regularMaterial)
            }
        }
        .navigationTitle(baseline == nil ? L10n.text("新增規則", "New Rule") : L10n.text("編輯規則", "Edit Rule"))
        .sheet(isPresented: $editingAppearance) {
            AppearanceEditSheet(title: rule.displayName, initial: rule.displayAppearance,
                                defaultSymbol: rule.defaultSymbol) { appearance in
                let value = appearance.isDefault ? nil : appearance
                guard rule.appearance != value else { return }
                let alreadySaved = try await onSaveAppearance(rule.id, appearance)
                rule.appearance = value
                if alreadySaved {
                    baseline?.appearance = value
                    compareBaseline?.appearance = value
                    exitBaseline.appearance = value
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hasUnsavedChanges)
        .toolbar {
            if hasUnsavedChanges {
                ToolbarItem(placement: .topBarLeading) {
                    Button { pendingDiscard = true } label: {
                        Label(L10n.text("返回", "Back"), systemImage: "chevron.left")
                    }
                    .accessibilityIdentifier("guarded-back")
                }
            }
            if dirty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("套用", "Apply"), action: applyAndReturn)
                    .fontWeight(.semibold)
                    .disabled(!canApply)
                    .accessibilityIdentifier("apply-rule")
                }
            }
        }
        .sheet(isPresented: $showingDeletion, onDismiss: {
            if didDelete {
                didDelete = false
                onDeleted()
            }
        }) {
            RuleDeletionPreview(civilCalendar: ruleCalendar, hasUnsavedChanges: hasUnsavedChanges,
                                load: { try previewDeletion(rule.id) }) { expected in
                try await onDelete(rule.id, expected)
                didDelete = true
                showingDeletion = false
            }
        }
        .sheet(isPresented: $pendingDiscard, onDismiss: handleExitAction) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.text("尚有變更未套用，要如何處理？", "Apply your changes before leaving?"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    if !canApply {
                        Text(missingRequiredPrompt)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Button {
                        exitAction = .apply
                        pendingDiscard = false
                    } label: {
                        Text(L10n.text("套用並返回", "Apply and Go Back")).frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApply)
                    Button(role: .destructive) {
                        exitAction = .discard
                        pendingDiscard = false
                    } label: {
                        Text(L10n.text("捨棄變更", "Discard Changes")).frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    Button {
                        pendingDiscard = false
                    } label: {
                        Text(L10n.text("繼續編輯", "Keep Editing")).frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(24)
            }
            .presentationDetents([.medium, .large])
        }
        .alert(L10n.text("無法完成操作", "Could Not Complete the Action"), isPresented: Binding(
            get: { operationError != nil }, set: { if !$0 { operationError = nil } }
        )) {
            Button(L10n.text("好", "OK"), role: .cancel) { operationError = nil }
        } message: { Text(operationError ?? "") }
    }

    private var missingRequiredPrompt: String {
        var missing: [String] = []
        if !hasTitle { missing.append(L10n.text("事件標題", "Event Title")) }
        if parent == nil && trimmedCategory.isEmpty { missing.append(L10n.text("分類", "Category")) }
        if !hasDestination { missing.append(L10n.text("指定行事曆", "Destination Calendar")) }
        return L10n.text("請繼續編輯，補齊\(missing.joined(separator: "、"))後再套用。", "Keep editing and fill in \(missing.joined(separator: ", ")) before applying.")
    }

    private func handleExitAction() {
        let action = exitAction
        exitAction = nil
        switch action {
        case .apply: applyAndReturn()
        case .discard: dismiss()
        case nil: break
        }
    }

    private func applyAndReturn() {
        guard canApply else {
            operationError = frozenReason ?? missingRequiredPrompt
            return
        }
        applying = true
        var submitted = rule
        submitted.target = destinationID
        let old = compareBaseline
        Task { @MainActor in
            defer { applying = false }
            do {
                let saved = try await onApply(submitted, old)
                rule = saved
                baseline = saved
                compareBaseline = saved
                exitBaseline = saved
                onApplied()
            } catch {
                operationError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var calendarFields: some View {
            if showCalendarConnectButton(calendar) {
                Button {
                    connecting = true
                    Task {
                        defer { connecting = false }
                        do {
                            try await calendar.connectCalendars()
                            #if targetEnvironment(simulator)
                            let writable = calendar.destinations.filter(\.isWritable)
                            if !isDestinationLocked, destinationID.isEmpty, writable.count == 1 {
                                followsCategoryDestination = false
                                rule.target = writable[0].id
                            }
                            #endif
                        } catch {
                            operationError = error.localizedDescription
                        }
                    }
                } label: {
                    if connecting {
                        ProgressView(L10n.text("正在連接行事曆…", "Connecting to Calendar…"))
                    } else {
                        Label(L10n.text("連接行事曆", "Connect Calendar"), systemImage: "calendar.badge.plus")
                    }
                }
                .disabled(connecting)
                .accessibilityIdentifier("connect-calendar")
            }
            if isDestinationLocked || calendar.destinations.isEmpty {
                LabeledContent {
                    Text(chosenDestination)
                } label: {
                    Text(L10n.text("指定行事曆（必填）", "Destination Calendar (required)"))
                        .foregroundStyle(hasDestination ? Color.primary : requiredFieldTint)
                }
            } else {
                CalendarDestinationField(title: L10n.text("指定行事曆（必填）", "Destination Calendar (required)"), selectedTitle: chosenDestination,
                                         selectedID: destinationID, isValid: hasDestination,
                                         destinations: calendar.destinations) {
                    followsCategoryDestination = false
                    rule.target = $0
                }
                    .accessibilityIdentifier("rule-destination")
            }
            if calendar.hasFullAccess, !calendar.destinations.contains(where: \.isWritable), !connecting {
                Text(L10n.text("目前沒有可寫入的行事曆。請在 Apple 行事曆中加入可編輯的行事曆，再回來選擇。", "No writable calendars are available. Add an editable calendar in Apple Calendar, then return to select it."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
    }

    private func treeRow(_ row: TreeRow) -> some View {
        let isCollapsed = collapsedBranches.contains(row.id)
        return HStack(spacing: 6) {
            if row.hasChildren {
                Button {
                    if isCollapsed {
                        collapsedBranches.remove(row.id)
                    } else {
                        collapsedBranches.insert(row.id)
                    }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(minWidth: 36, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isCollapsed ? L10n.text("展開\(row.item.displayName)", "Expand \(row.item.displayName)") : L10n.text("收合\(row.item.displayName)", "Collapse \(row.item.displayName)"))
            } else {
                Image(systemName: row.depth == 0 ? "circle.fill" : "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 36)
                    .accessibilityHidden(true)
            }
            if row.depth == 0 {
                Button {
                    onOpenChild(row.item, false)
                } label: {
                    HStack {
                        treeLabel(row)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(L10n.text("編輯這條子規則", "Edit this child rule"))
            } else {
                treeLabel(row)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, CGFloat(min(row.depth, 6)) * 15)
    }

    private func treeLabel(_ row: TreeRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: row.item.displayAppearance.symbol(or: row.item.defaultSymbol))
                .foregroundStyle(row.item.displayAppearance.tint(or: slate))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.item.displayName)
                Text(row.item.recurrenceCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var rootDate: some View {
        Section {
            Picker(L10n.text("類型", "Type"), selection: $rule.kind) {
                ForEach(RuleKind.allCases) { Text($0.displayLabel).tag($0) }
            }
            .onChange(of: rule.kind) { previousKind, kind in
                rule.date = kind.dates.first ?? ""
                if !availablePeriods.contains(rule.period) { rule.period = .year }
                if kind != .gregorian {
                    rule.weekdayPattern = nil
                    rule.weeklyWeekday = nil
                }
                if kind == .solar {
                    if isFreshRule && rule.solarTimeZoneIdentifier == nil { rule.pinSolarTimeZone() }
                    rule.useSolarDefaultDuration()
                } else if previousKind == .solar, rule.solarTimeZoneIdentifier != nil {
                    var solar = rule
                    solar.kind = .solar
                    let source = RuleEngine.civilCalendar(for: solar)
                    func localComponents(_ date: Date) -> Date {
                        gregorianCalendar.date(from: source.dateComponents([.year, .month, .day, .hour, .minute], from: date)) ?? date
                    }
                    rule.start = localComponents(rule.start)
                    rule.endDate = localComponents(rule.endDate)
                    rule.startTime = localComponents(rule.startTime)
                    rule.solarTimeZoneIdentifier = nil
                }
            }
            if rule.kind == .lunar {
                if rule.period == .year {
                    Picker(L10n.text("農曆月", "Lunar Month"), selection: $rule.lunarMonth) {
                        ForEach(1...12, id: \.self) { Text(L10n.text("\($0) 月", "Month \($0)")).tag($0) }
                    }
                }
                Picker(L10n.text("農曆日", "Lunar Day"), selection: $rule.lunarDay) {
                    ForEach(1...30, id: \.self) { Text(L10n.text("\($0) 日", "Day \($0)")).tag($0) }
                }
                if rule.period == .year {
                    Toggle(L10n.text("優先使用閏月", "Prefer the Leap Month"), isOn: $rule.lunarIsLeap)
                } else {
                    Toggle(L10n.text("包含閏月", "Include Leap Months"), isOn: Binding(
                        get: { rule.includeLeapMonths ?? true },
                        set: { rule.includeLeapMonths = $0 ? nil : false }
                    ))
                }
            } else if rule.kind == .solar {
                Picker(L10n.text("節氣", "Solar Term"), selection: $rule.date) {
                    ForEach(RuleKind.solar.dates, id: \.self) { Text(SolarTerms.displayName($0)).tag($0) }
                }
            }
            RuleDateField(title: L10n.text("起始日", "Start Date"), selection: $rule.start, civilCalendar: ruleCalendar)
                .onChange(of: rule.start) { oldStart, _ in
                    if allowsMonthEnd { rule.monthEnd = true }
                    if rule.kind == .solar && baseline == nil && rule.endMode == .duration {
                        var previousDefault = rule
                        previousDefault.start = oldStart
                        previousDefault.useSolarDefaultDuration()
                        if previousDefault.endUnit == rule.endUnit && previousDefault.endCount == rule.endCount {
                            rule.useSolarDefaultDuration()
                        }
                    }
                }
            Picker(L10n.text("週期", "Repeat Cycle"), selection: $rule.period) {
                ForEach(availablePeriods) { Text($0.displayLabel()).tag($0) }
            }
            .onChange(of: rule.period) { previous, period in
                if period != .year && period != .month {
                    rule.weekdayPattern = nil
                } else if previous != period, let pattern = rule.weekdayPattern {
                    rule.weekdayPattern = WeekdayPattern(month: nil, ordinal: pattern.ordinal, weekday: pattern.weekday)
                }
                if period != .week { rule.weeklyWeekday = nil }
            }
            Stepper(L10n.text("間隔：每 \(rule.interval) \(rule.period.rawValue)", "Repeat every \(rule.interval) \(rule.period.displayLabel(count: rule.interval))"), value: $rule.interval, in: 1...999)
            if rule.kind == .gregorian {
                if rule.period == .year || rule.period == .month {
                    weekdayCondition
                } else if rule.period == .week {
                    weekdayPicker(selection: Binding(
                        get: { rule.weeklyWeekday ?? gregorianCalendar.component(.weekday, from: rule.start) },
                        set: { rule.weeklyWeekday = $0 }
                    ))
                }
                if let summary = weekdaySummary {
                    Text(summary).font(.subheadline).foregroundStyle(.secondary)
                    LabeledContent(L10n.text("下次日期", "Next Date"), value: nextWeekdayDateCaption)
                }
            }
            if allowsMonthEnd {
                Toggle(L10n.text("固定在月底", "Repeat on the Last Day of the Month"), isOn: $rule.monthEnd)
            }
        } header: { Text(L10n.text("日期與週期", "Date and Recurrence")) }
          footer: {
              if rule.kind == .solar {
                  Text(L10n.text("內建資料涵蓋 \(SolarTerms.supportedYears.lowerBound)～\(SolarTerms.supportedYears.upperBound) 年，無須連網。", "Available offline for \(SolarTerms.supportedYears.lowerBound)–\(SolarTerms.supportedYears.upperBound)."))
              } else if allowsMonthEnd {
                  Text(L10n.text("例如 6/30 起每月重複，固定在月底時，下一筆是 7/31。", "For example, a monthly rule starting on June 30 repeats on July 31 when set to the last day of the month."))
              }
          }
    }

    @ViewBuilder private var weekdayCondition: some View {
        Picker(L10n.text("日期條件", "Date Pattern"), selection: Binding(
            get: { rule.weekdayPattern != nil },
            set: { selected in
                if selected {
                    if rule.weekdayPattern == nil {
                        rule.weekdayPattern = WeekdayPattern(
                            month: nil,
                            ordinal: 1,
                            weekday: gregorianCalendar.component(.weekday, from: rule.start)
                        )
                    }
                } else {
                    rule.weekdayPattern = nil
                }
            }
        )) {
            Text(rule.period == .year ? L10n.text("固定月日", "Fixed Month and Day") : L10n.text("固定日期", "Fixed Date")).tag(false)
            Text(L10n.text("固定星期幾", "Fixed Weekday")).tag(true)
        }
        if let pattern = rule.weekdayPattern {
            HStack {
                Picker(L10n.text("第幾個", "Occurrence in Month"), selection: conditionValue(\.ordinal)) {
                    ForEach(1...4, id: \.self) { Text(L10n.text("第 \($0) 個", "\(L10n.ordinal($0))")).tag($0) }
                }
                .labelsHidden()
                weekdayPicker(selection: conditionValue(\.weekday)).labelsHidden()
            }
            if rule.period == .year, let preservedMonth = pattern.month,
               preservedMonth != gregorianCalendar.component(.month, from: rule.start) {
                Text(L10n.text("此規則保留原先指定的 \(preservedMonth) 月。", "This rule keeps its original month: \(preservedMonth)."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func weekdayPicker(selection: Binding<Int>) -> some View {
        Picker(L10n.text("星期幾", "Weekday"), selection: selection) {
            ForEach(1...7, id: \.self) { Text(weekdayName($0)).tag($0) }
        }
    }

    private func weekdayName(_ number: Int) -> String {
        if L10n.isEnglish {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = L10n.locale
            return (1...7).contains(number) ? calendar.weekdaySymbols[number - 1] : "Weekday"
        }
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        return (1...7).contains(number) ? "星期\(names[number - 1])" : "星期幾"
    }

    private var weekdaySummary: String? {
        if L10n.isEnglish { return rule.period == .week || rule.weekdayPattern != nil ? rule.recurrenceCaption : nil }
        let interval = rule.interval == 1 ? "每\(rule.period.rawValue)" : "每 \(rule.interval) \(rule.period.rawValue)"
        if rule.period == .week {
            let weekday = weekdayName(rule.weeklyWeekday ?? gregorianCalendar.component(.weekday, from: rule.start))
            return rule.interval == 1 ? "每\(weekday)" : "\(interval)的\(weekday)"
        }
        guard let pattern = rule.weekdayPattern else { return nil }
        if rule.period == .year {
            let month = pattern.month ?? gregorianCalendar.component(.month, from: rule.start)
            return "\(interval) \(month) 月的第 \(pattern.ordinal) 個\(weekdayName(pattern.weekday))"
        }
        return "\(interval)的第 \(pattern.ordinal) 個\(weekdayName(pattern.weekday))"
    }

    private var nextWeekdayDateCaption: String {
        var root = rule
        root.timing = .allDay
        root.durationDays = 1
        let today = gregorianCalendar.startOfDay(for: Date())
        do {
            let next = try RuleEngine.plan(root: root, rules: [root])
                .first(where: { $0.start >= today })?.start
            return next.map { dateCaption($0) } ?? L10n.text("期間內沒有下次日期", "No upcoming date in this period")
        } catch {
            return L10n.text("無法換算", "Cannot Calculate")
        }
    }

    private func conditionValue(_ keyPath: KeyPath<WeekdayPattern, Int>) -> Binding<Int> {
        Binding {
            rule.weekdayPattern?[keyPath: keyPath] ?? 1
        } set: { value in
            guard let pattern = rule.weekdayPattern else { return }
            rule.weekdayPattern = WeekdayPattern(
                month: pattern.month,
                ordinal: keyPath == \WeekdayPattern.ordinal ? value : pattern.ordinal,
                weekday: keyPath == \WeekdayPattern.weekday ? value : pattern.weekday
            )
        }
    }

    private var cutoffSchedule: Rule {
        var input = rule
        // Names and appearance do not affect the date result. Keep typing from recalculating it.
        input.name = ""
        input.category = ""
        input.subcategory = ""
        input.appearance = nil
        input.target = ""
        return input
    }

    private var cutoff: some View {
        Section {
            Picker(L10n.text("截止方式", "End Condition"), selection: $rule.endMode) {
                ForEach(EndMode.allCases) { Text($0.displayLabel).tag($0) }
            }
            if rule.endMode == .duration {
                Picker(L10n.text("重複期間單位", "Repeat Period Unit"), selection: $rule.endUnit) {
                    ForEach(PeriodUnit.allCases.filter { $0 != .week }) { Text($0.displayLabel()).tag($0) }
                }
                Stepper(L10n.text("重複期間：\(rule.endCount) \(rule.endUnit.rawValue)", "Repeat period: \(rule.endCount) \(rule.endUnit.displayLabel(count: rule.endCount))"), value: $rule.endCount, in: 1...999)
                if let date = try? RuleEngine.cutoff(for: rule) {
                    LabeledContent(L10n.text("換算截止日", "Calculated End Date"), value: dateCaption(date, calendar: ruleCalendar))
                } else {
                    LabeledContent(L10n.text("換算截止日", "Calculated End Date"), value: L10n.text("無法換算", "Cannot Calculate"))
                }
            } else {
                RuleDateField(title: L10n.text("截止日期", "End Date"), selection: $rule.endDate, civilCalendar: ruleCalendar)
            }
        } header: { Text(L10n.text("規則截止", "Rule End")) }
          footer: {
              VStack(alignment: .leading, spacing: 4) {
                  Text(L10n.text("截止包含指定日期當天。", "The end date is included."))
                  if emptyCutoffSchedule == cutoffSchedule {
                      Text(L10n.text("這段期間內沒有事件，請調整起始日、週期或截止日。",
                                     "No events fall in this period. Adjust the start date, recurrence, or end date."))
                          .foregroundStyle(requiredFieldTint)
                          .accessibilityIdentifier("rule-cutoff-no-events")
                  }
              }
          }
        .task(id: cutoffSchedule) {
            let input = cutoffSchedule
            guard !Task.isCancelled else { return }
            let isEmpty = (try? RuleEngine.plan(root: input, rules: [input]).isEmpty) == true
            guard !Task.isCancelled else { return }
            emptyCutoffSchedule = isEmpty ? input : nil
        }
    }

    private var hoursLabel: String {
        let whole = rule.durationHalfHours / 2
        return rule.durationHalfHours.isMultiple(of: 2) ? "\(whole)" : "\(whole).5"
    }
}

private struct RuleEventPreviewResult {
    let rules: [BatchRemovalRule]
    let events: [CalendarPreviewEvent]
    let warning: String?
}

private struct EventPreview: View {
    let rule: Rule
    let savedRules: [Rule]
    let civilCalendar: Calendar
    let load: (Rule) throws -> RuleEventPreviewResult
    @State private var expanded = false
    @State private var loadedRule: Rule?
    @State private var result: Result<RuleEventPreviewResult, Error>?

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                if loadedRule == rule, let result {
                    switch result {
                    case .failure(let error):
                        Label(error.localizedDescription, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                        Button(L10n.text("重新整理", "Refresh"), action: refresh)
                    case .success(let preview):
                        if let warning = preview.warning {
                            Label(warning, systemImage: "exclamationmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        let eventsByRule = Dictionary(grouping: preview.events, by: \.ruleID)
                        RulePreviewTree(rows: preview.rules, titleShownInEvents: { row in
                            eventsByRule[row.id]?.contains { $0.title == row.title } == true
                        }) { row in
                            if let events = eventsByRule[row.id], !events.isEmpty {
                                ForEach(events) { event in
                                    RulePreviewEventRow(event: event, civilCalendar: civilCalendar)
                                }
                            } else {
                                Text(L10n.text("沒有可預覽的事件", "No Events to Preview"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    ProgressView(L10n.text("正在讀取事件…", "Loading events…"))
                }
            } label: {
                Label(L10n.text("預覽事件", "Preview Events"), systemImage: "list.bullet.rectangle")
            }
            .accessibilityIdentifier("preview-events")
        } footer: {
            if expanded {
                Text(L10n.text("這裡列出本規則及子規則已寫入行事曆的事件，以及尚未套用的變更。按「套用」後才會更新行事曆。", "This preview shows saved events and unapplied changes for this rule and its child rules. Your calendar is updated only when you tap Apply."))
            }
        }
        .onChange(of: expanded) { _, open in
            if open, loadedRule != rule { refresh() }
        }
        .onChange(of: rule) { _, _ in invalidate() }
        .onChange(of: savedRules) { _, _ in invalidate() }
    }

    private func invalidate() {
        loadedRule = nil
        result = nil
        if expanded { refresh() }
    }

    private func refresh() {
        let submitted = rule
        result = Result {
            let preview = try load(submitted)
            let events = preview.events.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
            return RuleEventPreviewResult(rules: preview.rules, events: events, warning: preview.warning)
        }
        loadedRule = submitted
    }

}

private struct RulePreviewTree<Rows: View>: View {
    let rows: [BatchRemovalRule]
    let titleShownInEvents: (BatchRemovalRule) -> Bool
    @ViewBuilder let content: (BatchRemovalRule) -> Rows
    @State private var collapsed: Set<UUID> = []

    private var visible: [BatchRemovalRule] {
        var hiddenBelow: Int?
        return rows.filter { row in
            if let depth = hiddenBelow, row.depth > depth { return false }
            hiddenBelow = collapsed.contains(row.id) ? row.depth : nil
            return true
        }
    }

    var body: some View {
        ForEach(visible) { row in
            let margin = CGFloat(min(row.depth, 5)) * 12
            VStack(alignment: .leading, spacing: 8) {
                if let index = rows.firstIndex(where: { $0.id == row.id }),
                   index + 1 < rows.count, rows[index + 1].depth > row.depth {
                    Button {
                        if !collapsed.insert(row.id).inserted { collapsed.remove(row.id) }
                    } label: {
                        Label(titleShownInEvents(row) ? L10n.text("子規則", "Child Rules") : row.title,
                              systemImage: collapsed.contains(row.id) ? "chevron.right" : "chevron.down")
                            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(collapsed.contains(row.id)
                        ? L10n.text("展開子規則：\(row.title)", "Expand child rules: \(row.title)")
                        : L10n.text("收合子規則：\(row.title)", "Collapse child rules: \(row.title)"))
                } else if !titleShownInEvents(row) {
                    Text(row.title)
                        .accessibilityAddTraits(.isHeader)
                }
                content(row)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.leading, margin)
            .padding(.vertical, 4)
        }
    }
}

private struct RuleDeletionPreview: View {
    let civilCalendar: Calendar
    let hasUnsavedChanges: Bool
    let load: () throws -> BatchRemovalPreview
    let remove: (BatchRemovalPreview) async throws -> Void
    @State private var removing = false
    @Environment(\.dismiss) private var dismiss
    @State private var preview: BatchRemovalPreview?
    @State private var failure: String?
    @State private var canReload = true

    var body: some View {
        NavigationStack {
            List {
                if let failure {
                    Section {
                        Label(failure, systemImage: "exclamationmark.circle")
                        if canReload {
                            Button(L10n.text("重新預覽", "Preview Again"), action: refresh)
                        }
                    }
                }
                if let preview {
                    Section {
                        Text(L10n.text("將刪除 \(preview.ruleCount) 條規則及 \(preview.eventCount) 筆尚未開始的事件。",
                                       "Rules to delete: \(preview.ruleCount). Upcoming events to delete: \(preview.eventCount)."))
                        Text(L10n.text("已開始或已過去的事件會保留。收合不影響刪除範圍。", "Events that already started or ended will be kept. Collapsing a branch does not change what will be deleted."))
                            .foregroundStyle(.secondary)
                        if hasUnsavedChanges {
                            Text(L10n.text("這條規則尚未套用的修改也會捨棄。", "Unapplied edits to this rule will also be discarded."))
                                .foregroundStyle(.secondary)
                        }
                    }
                    let byRule = Dictionary(grouping: preview.events, by: \.ruleID)
                    let retainedByRule = Dictionary(grouping: preview.retained, by: \.ruleID)
                    Section {
                        RulePreviewTree(rows: preview.rules, titleShownInEvents: { row in
                            byRule[row.id]?.contains { $0.title == row.title } == true
                                || retainedByRule[row.id]?.contains { $0.title == row.title } == true
                        }) { row in
                            if let kept = retainedByRule[row.id] {
                                ForEach(kept) { event in
                                    RulePreviewEventRow(event: event, civilCalendar: civilCalendar)
                                }
                            }
                            if let events = byRule[row.id], !events.isEmpty {
                                ForEach(events) { event in
                                    let zone = event.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
                                    let displayCalendar = zone.map { zone in
                                        var calendar = civilCalendar
                                        calendar.timeZone = zone
                                        return calendar
                                    } ?? civilCalendar
                                    RulePreviewEventRow(event: .init(id: event.id, ruleID: event.ruleID, title: event.title,
                                                                    start: event.start, end: event.end, isAllDay: event.isAllDay,
                                                                    isPast: false, kind: .remove), civilCalendar: displayCalendar)
                                }
                            } else {
                                Text(L10n.text("沒有待移除的事件", "No Events to Delete"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if failure == nil {
                    ProgressView(L10n.text("正在讀取事件…", "Loading events…"))
                }
            }
            .navigationTitle(L10n.text("刪除預覽", "Deletion Preview"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(L10n.text("取消", "Cancel"), role: .cancel) { dismiss() }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    Button(L10n.text("確認刪除", "Confirm Deletion"), role: .destructive, action: confirm)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(preview == nil || removing)
                        .accessibilityIdentifier("confirm-delete-rule")
                }
                .font(.body.weight(.semibold))
                .padding(.horizontal)
                .background(.regularMaterial)
            }
        }
        .task { if preview == nil && failure == nil { refresh() } }
    }

    private func refresh() {
        do {
            preview = try load()
            failure = nil
        } catch {
            preview = nil
            failure = error.localizedDescription
        }
    }

    private func confirm() {
        guard let preview, !removing else { return }
        removing = true
        Task { @MainActor in
            defer { removing = false }
            do { try await remove(preview) }
            catch {
                self.preview = nil
                failure = error.localizedDescription
                if let calendarError = error as? CalendarIntegrationError, case .writeFailed = calendarError {
                    canReload = false
                } else { canReload = true }
            }
        }
    }
}

private struct RulePreviewEventRow: View {
    let event: CalendarPreviewEvent
    let civilCalendar: Calendar

    var body: some View {
        let status: (label: String, color: Color)? = switch event.kind {
        case .unchanged: nil
        case .insert: (L10n.text("將新增", "To Add"), readableTint(light: 0x456B52, dark: 0x91AA98))
        case .update: (L10n.text("將修改", "To Update"), readableTint(light: 0x536780, dark: 0x98A9BF))
        case .remove: (L10n.text("將移除", "To Remove"), requiredFieldTint)
        }
        let revisedTime: Bool
        if case .update = event.kind, let oldStart = event.previousStart {
            revisedTime = oldStart != event.start || event.previousEnd != event.end || event.previousIsAllDay != event.isAllDay
        } else {
            revisedTime = false
        }
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.subheadline.weight(.semibold))
                if revisedTime, let oldStart = event.previousStart {
                    Text(L10n.text("原：\(eventTime(start: oldStart, end: event.previousEnd ?? oldStart, allDay: event.previousIsAllDay ?? event.isAllDay))", "Before: \(eventTime(start: oldStart, end: event.previousEnd ?? oldStart, allDay: event.previousIsAllDay ?? event.isAllDay))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(revisedTime ? L10n.text("改為：", "After: ") : "")\(eventTime(start: event.start, end: event.end, allDay: event.isAllDay))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let status {
                Text(status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.color)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
        .foregroundStyle(event.isPast ? Color.secondary : Color.primary)
        .opacity(event.isPast ? 0.65 : 1)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func eventTime(start: Date, end: Date, allDay: Bool) -> String {
        let date = dateCaption(start, calendar: allDay ? gregorianCalendar : civilCalendar)
        if allDay {
            let lastDay = gregorianCalendar.date(byAdding: .day, value: -1, to: end) ?? end
            return lastDay > start ? L10n.text("\(date) 至 \(dateCaption(lastDay))", "\(date) to \(dateCaption(lastDay))") : date
        }
        let startTime = timeCaption(start, calendar: civilCalendar)
        guard end > start else { return "\(date) \(startTime)" }
        let endDate = civilCalendar.isDate(start, inSameDayAs: end) ? "" : "\(dateCaption(end, calendar: civilCalendar)) "
        return L10n.text("\(date) \(startTime) 至 \(endDate)\(timeCaption(end, calendar: civilCalendar))", "\(date) \(startTime) to \(endDate)\(timeCaption(end, calendar: civilCalendar))")
    }
}

@MainActor
func showCalendarConnectButton(_ calendar: CalendarIntegration) -> Bool {
    #if targetEnvironment(simulator)
    calendar.hasFullAccess && calendar.destinations.isEmpty
    #else
    false
    #endif
}

/// Lists read-only destinations for context without exposing them as selection actions.
struct CalendarDestinationField: View {
    let title: String
    let selectedTitle: String
    let selectedID: String
    let isValid: Bool
    let destinations: [CalendarDestination]
    let select: (String) -> Void

    var body: some View {
        Menu {
            let writable = destinations.filter(\.isWritable)
            let readOnly = destinations.filter { !$0.isWritable }
            if !writable.isEmpty {
                Section(L10n.text("可寫入", "Writable")) {
                    ForEach(writable) { destination in
                        Button { select(destination.id) } label: {
                            if destination.id == selectedID {
                                Label(destination.displayTitle, systemImage: "checkmark")
                            } else {
                                Text(destination.displayTitle)
                            }
                        }
                    }
                }
            }
            if !readOnly.isEmpty {
                Section(L10n.text("唯讀，不能選擇", "Read-Only (Unavailable)")) {
                    ForEach(readOnly) { destination in
                        Button { } label: { Text(destination.displayTitle) }
                            .disabled(true)
                    }
                }
            }
        } label: {
            LabeledContent {
                HStack(spacing: 5) {
                    Text(selectedTitle)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .accessibilityHidden(true)
                }
                .multilineTextAlignment(.trailing)
            } label: {
                Text(title).foregroundStyle(isValid ? Color.primary : requiredFieldTint)
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(selectedTitle)
    }
}

private struct CalStitchSettingsView: View {
    @Binding var hideFrozen: Bool
    @AppStorage("settings.defaultTimeZoneIdentifier") private var overrideIdentifier = ""

    private var installedVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let version, let build { return "\(version) (\(build))" }
        return version ?? build ?? "—"
    }

    private var currentIdentifier: String {
        overrideIdentifier.isEmpty ? TimeZone.autoupdatingCurrent.identifier : overrideIdentifier
    }

    private func documentationURL(_ page: String) -> URL {
        let base = URL(string: "https://peiyu66.github.io/CalStitch/")!
        let language = L10n.isEnglish ? base.appendingPathComponent("en", isDirectory: true) : base
        return language.appendingPathComponent(page)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(installedVersion).monospacedDigit()
                } label: {
                    Text(L10n.text("版本", "Version"))
                }
                .accessibilityIdentifier("installed-version")
            }

            Section {
                Toggle(L10n.text("隱藏凍結的規則", "Hide Frozen Rules"), isOn: $hideFrozen)
            }

            Section {
                NavigationLink {
                    TimeZoneOptionsView(overrideIdentifier: $overrideIdentifier)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(L10n.text("預設時區", "Default Time Zone"))
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(currentIdentifier)
                            if overrideIdentifier.isEmpty {
                                Text(L10n.text("使用本機時區", "Use Device Time Zone")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .multilineTextAlignment(.trailing)
                    }
                }
                .accessibilityIdentifier("default-time-zone")
            } footer: {
                Text(L10n.text("適用於新建的節氣規則，不會變更既有規則。", "Applies to new solar term rules. Existing rules are not changed."))
            }

            Section {
                Link(destination: documentationURL("privacy.html")) {
                    Label(L10n.text("隱私權聲明", "Privacy Policy"), systemImage: "hand.raised")
                }
                .accessibilityIdentifier("privacy-statement")
                Link(destination: documentationURL("support.html")) {
                    Label(L10n.text("支援", "Support"), systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("support")
            }
        }
        .navigationTitle(L10n.text("設定", "Settings"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TimeZoneOptionsView: View {
    @Binding var overrideIdentifier: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private struct Option: Identifiable {
        let id: String
        var components: [String] { id.split(separator: "/").map(String.init) }
        var area: String { components.count > 1 ? components[0] : "" }
        var place: String { components.last ?? id }
        var region: String? {
            if components.count > 2 {
                return components.dropFirst().dropLast().joined(separator: " / ")
                    .replacingOccurrences(of: "_", with: " ")
            }
            // IANA zone.tab explicitly groups these seven zone records under Alaska.
            switch id {
            case "America/Anchorage", "America/Juneau", "America/Sitka", "America/Metlakatla",
                 "America/Yakutat", "America/Nome", "America/Adak": return "Alaska"
            default: return nil
            }
        }
    }

    private static let allOptions = TimeZone.knownTimeZoneIdentifiers.map { Option(id: $0) }.sorted { lhs, rhs in
        let left = [lhs.area, lhs.region ?? lhs.place, lhs.place, lhs.id]
        let right = [rhs.area, rhs.region ?? rhs.place, rhs.place, rhs.id]
        for (a, b) in zip(left, right) {
            let comparison = a.compare(b, options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            if comparison != .orderedSame { return comparison == .orderedAscending }
        }
        return lhs.id < rhs.id
    }

    private var options: [Option] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return Self.allOptions }
        return Self.allOptions.filter { item in
            item.id.localizedStandardContains(search) ||
                item.id.replacingOccurrences(of: "_", with: " ").localizedStandardContains(search) ||
                (item.region?.localizedStandardContains(search) ?? false)
        }
    }

    private var sections: [String: [Option]] {
        Dictionary(grouping: options) { item in
            String((item.area.isEmpty ? item.id : item.area).prefix(1)).uppercased()
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            let groups = sections
            let letters = groups.keys.sorted()
            VStack(spacing: 0) {
                List {
                    Section {
                        option(L10n.text("使用本機時區", "Use Device Time Zone"), detail: TimeZone.autoupdatingCurrent.identifier,
                               identifier: "")
                    }
                    if letters.isEmpty {
                        Text(L10n.text("找不到符合的時區", "No Matching Time Zones")).foregroundStyle(.secondary)
                    }
                    ForEach(letters, id: \.self) { letter in
                        Section {
                            ForEach(groups[letter] ?? []) { item in
                                option(item.id, detail: item.region, identifier: item.id)
                                    .padding(.trailing, 23)
                                    .id(item.id)
                            }
                        } header: {
                            Text(letter)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .overlay(alignment: .trailing) {
                    if !letters.isEmpty {
                        ViewThatFits(in: .vertical) {
                            indexButtons(letters, groups: groups, proxy: proxy)
                            ScrollView(.vertical) { indexButtons(letters, groups: groups, proxy: proxy) }
                        }
                        .padding(.trailing, 5)
                        .accessibilityIdentifier("time-zone-index")
                    }
                }
                .clipped()
                timeZoneSearchBar
            }
        }
        .navigationTitle(L10n.text("預設時區", "Default Time Zone"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var timeZoneSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            TextField(L10n.text("搜尋城市或時區", "Search cities or time zones"), text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .accessibilityIdentifier("time-zone-search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("清除搜尋", "Clear Search"))
            }
        }
        .font(.body)
        .padding(.leading, 15)
        .padding(.trailing, query.isEmpty ? 15 : 4)
        .frame(minHeight: 46)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func indexButtons(_ letters: [String], groups: [String: [Option]], proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            ForEach(letters, id: \.self) { letter in
                Button {
                    if let first = groups[letter]?.first { proxy.scrollTo(first.id, anchor: .top) }
                } label: {
                    Text(letter)
                        .font(.caption2.weight(.semibold))
                        .frame(width: 26, height: 23)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel(L10n.text("跳到 \(letter)", "Jump to \(letter)"))
            }
        }
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
    }

    private func option(_ name: String, detail: String?, identifier: String) -> some View {
        let selected = overrideIdentifier == identifier
        return Button {
            overrideIdentifier = identifier
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).foregroundStyle(.primary)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark").accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SelectionMark: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .accessibilityHidden(true)
    }
}

private struct OrphanCleanupView: View {
    @ObservedObject var calendar: CalendarIntegration
    let existingRuleIDs: () throws -> Set<UUID>
    let beforeRemove: () async throws -> Void
    @State private var removing = false
    @Environment(\.dismiss) private var dismiss
    @State private var preview: CalendarOrphanPreview?
    @State private var selection: Set<String> = []
    @State private var failure: String?
    @State private var confirmation = false
    @State private var connecting = false
    @State private var removedCount: Int?

    private var selected: [CalendarOrphanEvent] {
        preview?.events.filter { selection.contains($0.id) } ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L10n.text("只顯示有 CalStitch 標記，但在這台裝置找不到原規則的事件。若事件來自另一台裝置，請先確認不再需要。", "Only events tagged by CalStitch that have no matching rule on this device are shown. If an event came from another device, make sure it is no longer needed."))
                        .font(.footnote)
                    if let preview {
                        Text(L10n.text("搜尋範圍：\(dateCaption(preview.start)) 至 \(dateCaption(preview.through))", "Search range: \(dateCaption(preview.start)) to \(dateCaption(preview.through))"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let removedCount {
                        Text(L10n.text("已刪除 \(removedCount) 筆事件", "Deleted \(removedCount) \(removedCount == 1 ? "event" : "events")"))
                    }
                    if let failure {
                        Text(failure).foregroundStyle(.red)
                    }
                    if !calendar.hasFullAccess {
                        Button {
                            connecting = true
                            Task {
                                defer { connecting = false }
                                do {
                                    try await calendar.connectCalendars()
                                    refresh()
                                } catch { failure = error.localizedDescription }
                            }
                        } label: {
                            if connecting { ProgressView(L10n.text("正在連接行事曆…", "Connecting to Calendar…")) }
                            else { Label(L10n.text("連接行事曆", "Connect Calendar"), systemImage: "calendar.badge.plus") }
                        }
                        .disabled(connecting)
                    } else if failure != nil {
                        Button(L10n.text("重試", "Retry"), action: refresh)
                    }
                }
                if let preview {
                    eventSection(L10n.text("已過去", "Past"), events: preview.events.filter(\.isPast))
                    eventSection(L10n.text("未到來", "Upcoming"), events: preview.events.filter { !$0.isPast })
                }
            }
            .navigationTitle(L10n.text("清除遺留事件", "Clean Up Leftover Events"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.text("關閉", "Close")) { dismiss() } }
                if !selected.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .destructive) { confirmation = true } label: {
                            Text(L10n.text("刪除（\(selected.count)）", "Delete (\(selected.count))")).foregroundStyle(.red)
                        }
                        .accessibilityIdentifier("delete-orphan-events")
                    }
                }
            }
            .task { if calendar.hasFullAccess { refresh() } }
            .refreshable { if calendar.hasFullAccess { refresh() } }
            .alert(L10n.text("刪除 \(selected.count) 筆遺留事件？", "Delete \(selected.count) leftover \(selected.count == 1 ? "event" : "events")?"), isPresented: $confirmation) {
                Button(L10n.text("取消", "Cancel"), role: .cancel) {}
                Button(L10n.text("刪除", "Delete"), role: .destructive, action: removeSelected)
            } message: {
                let names = Set(selected.map(\.calendarTitle)).sorted().joined(separator: L10n.text("、", ", "))
                Text(L10n.text("將從「\(names)」刪除勾選的事件，不會刪除規則。", "The selected events will be deleted from \(names). Rules will not be deleted."))
            }
        }
    }

    private func eventSection(_ title: String, events: [CalendarOrphanEvent]) -> some View {
        let ids = Set(events.map(\.id))
        let allSelected = !ids.isEmpty && ids.isSubset(of: selection)
        return Section {
            if events.isEmpty {
                Text(L10n.text("沒有符合的事件", "No Matching Events")).foregroundStyle(.secondary)
            } else {
                Button {
                    if allSelected { selection.subtract(ids) }
                    else { selection.formUnion(ids) }
                } label: {
                    HStack(spacing: 12) {
                        SelectionMark(isSelected: allSelected)
                        Text(L10n.text("全選", "Select All"))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(allSelected ? [.isSelected] : [])
                .accessibilityLabel(allSelected ? L10n.text("取消全選\(title)", "Deselect all in \(title)") : L10n.text("全選\(title)", "Select all in \(title)"))
                ForEach(events) { event in
                    let checked = selection.contains(event.id)
                    Button {
                        if !selection.insert(event.id).inserted { selection.remove(event.id) }
                    } label: {
                        HStack(spacing: 12) {
                            SelectionMark(isSelected: checked)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title).foregroundStyle(.primary)
                                Text(event.isAllDay ? dateCaption(event.start)
                                     : "\(dateCaption(event.start)) \(timeCaption(event.start))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(event.calendarTitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityAddTraits(checked ? .isSelected : [])
                }
            }
        } header: { Text(title) }
    }

    private func refresh() {
        selection.removeAll()
        failure = nil
        do {
            preview = try calendar.previewOrphans(existingRuleIDs: existingRuleIDs())
        } catch {
            preview = nil
            failure = error.localizedDescription
        }
    }

    private func removeSelected() {
        guard let preview, !selected.isEmpty else { return }
        let items = selected
        guard !removing else { return }
        removing = true
        Task { @MainActor in
            defer { removing = false }
            do {
                try await beforeRemove()
            try calendar.removeOrphans(items, from: preview, existingRuleIDs: existingRuleIDs())
            removedCount = items.count
            refresh()
        } catch {
            removedCount = nil
            refresh()
            failure = error.localizedDescription
        }
    }
    }
}

private struct CloudThawProposal: Equatable {
    let accountID: String
    let operation: CloudRuleOperation?
    let expired: Set<UUID>
    let affected: Set<UUID>
    let deleted: Bool
    let locations: [UUID: String]
    let previous: [PlannedOccurrence]
    let observed: [PlannedOccurrence]
}

private struct FrozenRuleReview: View {
    let rule: Rule
    let original: String?
    let inspect: () async throws -> CloudThawProposal
    let confirm: (CloudThawProposal) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var proposal: CloudThawProposal?
    @State private var processing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(rule.displayName).font(.headline)
                    if let original {
                        LabeledContent(L10n.text("原行事曆", "Original Calendar"), value: original)
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
                }
                if let proposal {
                    if proposal.deleted {
                        Text(L10n.text("雲端已確認刪除。確認後不會恢復這條規則或事件。", "iCloud confirms the rule was deleted. Confirming will not restore it or its events."))
                    }
                    if !proposal.observed.isEmpty {
                        Section(L10n.text("已核對的事件", "Verified Events")) {
                            ForEach(Array(proposal.observed.enumerated()), id: \.offset) { _, event in
                                VStack(alignment: .leading) {
                                    Text(event.title)
                                    Text(dateCaption(event.start)).font(.caption)
                                }
                            }
                        }
                    }
                    Section {
                        Button(proposal.deleted ? L10n.text("確認刪除狀態", "Acknowledge Deletion") : L10n.text("確認接手", "Confirm Takeover")) {
                            guard !processing else { return }
                            processing = true
                            Task {
                                defer { processing = false }
                                do { try await confirm(proposal); dismiss() }
                                catch { errorMessage = error.localizedDescription; self.proposal = nil }
                            }
                        }.disabled(processing)
                    } footer: {
                        if !proposal.deleted { Text(L10n.text("解除凍結後，你可以在這台裝置修改或刪除規則。行事曆事件不會立即變更。",
                                       "After unfreezing, you can edit or delete the rule on this device. Calendar events will not change immediately.")) }
                    }
                }
            }
            .navigationTitle(L10n.text("解除凍結", "Unfreeze Rule"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("取消", "Cancel")) { dismiss() }.disabled(processing)
                }
            }
            .task {
                do { proposal = try await inspect(); errorMessage = nil }
                catch { proposal = nil; errorMessage = error.localizedDescription }
            }
        }
        .interactiveDismissDisabled(processing)
    }
}
