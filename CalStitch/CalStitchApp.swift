import SwiftUI
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

    private static func url() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("CalStitch", isDirectory: true)
            .appendingPathComponent("rules-v1.json")
    }

    static func read() throws -> Self {
        let url = try Self.url()
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func preflightWrite() throws {
        let url = try Self.url()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".preflight-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try JSONEncoder().encode(self).write(to: temporary, options: .atomic)
    }

    func write() throws {
        let url = try Self.url()
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
                    if loaded && showGettingStarted { intro }
                    if !loaded && !loadFailed {
                        ProgressView(L10n.text("正在讀取規則…", "Loading rules…"))
                    } else if loadFailed {
                        Button(L10n.text("重新讀取規則", "Reload Rules"), action: load)
                    } else if rootRules.isEmpty {
                        emptyState
                    }
                    let names = uniqueNames(rootRules.map(\.category))
                    ForEach(names, id: \.self) { name in
                        category(name, rules: rootRules.filter { $0.category == name }, isFirst: name == names.first)
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
                    CalStitchSettingsView()
                case .edit(let rule, let isNew):
                    RuleEditor(initial: snapshot.rules.first { $0.id == rule.id } ?? rule, isNew: isNew,
                               parent: snapshot.rules.first { $0.id == rule.parent },
                               allRules: snapshot.rules, calendar: calendar,
                               preview: preview, onApply: apply, onApplied: returnAfterApply,
                               previewDeletion: { id in try previewRemoval([id], allowChild: true) },
                               onDelete: { id, expected in try removeSelected([id], expected, allowChild: true) },
                               onDeleted: { if !path.isEmpty { path.removeLast() } },
                               onSaveAppearance: saveRuleAppearance) { child, isNew in
                        path.append(.edit(child, isNew: isNew))
                    }
                }
            }
            .sheet(isPresented: $isAdding) { addSheet }
            .background {
                ContactPickerPresenter(request: contactPickerRequest) { selection in
                    contactPickerRequest = nil
                    birthdaySelection = selection
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
                    contactPickerRequest = UUID()
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
                OrphanCleanupView(calendar: calendar, existingRuleIDs: { Set(snapshot.rules.map(\.id)) })
            }
            .sheet(isPresented: $isShowingBatch) {
                BatchActionsView(rules: rootRules.map {
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
        .task {
            calendar.refreshCalendars()
            if !loaded && !loadFailed { load() }
            if !checkedBirthdaySettingsReturn {
                checkedBirthdaySettingsReturn = true
                if BirthdayGroupSettingsReturn.consume() { selectingBirthdayGroup = true }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { calendar.refreshCalendars() }
            if phase == .background { reachedBackground = true }
            if phase == .active && reachedBackground {
                showGettingStarted = rootRules.isEmpty
                reachedBackground = false
            }
        }
    }

    private var rootRules: [Rule] { snapshot.rules.filter { $0.parent == nil } }

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
        guard rootRules.contains(where: { $0.category == key.category && (key.subcategory == nil || $0.subcategory == key.subcategory) }) else {
            throw RuleOperationError(L10n.text("找不到這個分類。", "This category could not be found."))
        }
        var updated = snapshot
        var entries = updated.groupAppearances ?? []
        entries.removeAll { $0.key == key }
        if !appearance.isDefault { entries.append(.init(key: key, value: appearance)) }
        updated.groupAppearances = entries.isEmpty ? nil : entries
        try updated.write()
        snapshot = updated
    }

    private func saveRuleAppearance(_ id: UUID, _ appearance: RuleAppearance) throws -> Bool {
        guard let index = snapshot.rules.firstIndex(where: { $0.id == id }) else { return false }
        var updated = snapshot
        updated.rules[index].appearance = appearance.isDefault ? nil : appearance
        try updated.write()
        snapshot = updated
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

    private func load() {
        do {
            snapshot = try RuleSnapshot.read()
            showGettingStarted = rootRules.isEmpty
            loadFailed = false
            loaded = true
        } catch {
            loaded = false
            loadFailed = true
            toolbarError = L10n.text("讀取已儲存的規則失敗。原資料沒有覆寫。請重新開啟 App 或再試一次。\n\(error.localizedDescription)", "Could not load saved rules. Existing data was not overwritten. Reopen the app or try again.\n\(error.localizedDescription)")
        }
    }

    private func resolve(_ input: Rule) throws -> RuleReconciliation {
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
            rule.target = parent.target
            rule.category = parent.category
            rule.subcategory = parent.subcategory
        }
        guard !rule.target.isEmpty else { throw RuleOperationError(L10n.text("目的行事曆為必填。請返回規則主頁，先連接行事曆並選擇目的地。", "A destination calendar is required. Return to the rule, connect Calendar, and choose a destination.")) }
        if let saved = snapshot.rules.first(where: { $0.id == rule.id }),
           saved.hasApplied && saved.target != rule.target {
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

    private func apply(_ rule: Rule) throws -> Rule {
        let plan = try resolve(rule)
        var updated = snapshot
        updated.rules = plan.rules
        updated.occurrences.removeAll { plan.ruleIDs.contains($0.ruleID) }
        do {
            var staging = updated
            staging.occurrences += plan.desired
            try staging.preflightWrite()
        } catch {
            throw RuleOperationError(L10n.text("裝置目前無法儲存規則。未變更行事曆，請確認裝置空間後再試。", "The rule could not be saved. Calendar was not changed. Check available storage and try again."))
        }
        let committed = try calendar.apply(desired: plan.desired, previous: plan.previous, ruleIDs: plan.ruleIDs)
        updated.occurrences += committed
        do {
            try updated.write()
        } catch {
            throw RuleOperationError(L10n.text("行事曆已寫入，但規則未能儲存。請先檢查裝置空間與行事曆，不要重複套用。\n\(error.localizedDescription)", "Calendar was updated, but the rule could not be saved. Check available storage and your calendar before applying again.\n\(error.localizedDescription)"))
        }
        snapshot = updated
        return updated.rules.first { $0.id == rule.id } ?? rule
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

    private func applyBatch(_ edit: BatchEdit) throws {
        let plan = try batchPlan(edit).plan
        if plan.rules == snapshot.rules, try batchCalendarChanges(plan).isEmpty { return }
        var updated = snapshot
        updated.rules = plan.rules
        if !plan.ruleIDs.isEmpty {
            do {
                var staging = updated
                staging.occurrences += plan.desired
                try staging.preflightWrite()
            } catch {
                throw RuleOperationError(L10n.text("不能儲存規則，行事曆沒有變更。請確認裝置空間後再試。", "The rules could not be saved. Calendar was not changed. Check available storage and try again."))
            }
            let committed = try calendar.apply(desired: plan.desired, previous: plan.previous, ruleIDs: plan.ruleIDs)
            updated.occurrences.removeAll { plan.ruleIDs.contains($0.ruleID) }
            updated.occurrences += committed
        }
        do {
            try updated.write()
        } catch {
            throw RuleOperationError(plan.ruleIDs.isEmpty
                ? L10n.text("不能儲存規則，行事曆沒有變更。請確認裝置空間後再試。", "The rules could not be saved. Calendar was not changed. Check available storage and try again.")
                : L10n.text("行事曆已寫入，但規則未能儲存。請先檢查裝置空間與行事曆，不要重複套用。", "Calendar was updated, but the rules could not be saved. Check available storage and your calendar before applying again."))
        }
        snapshot = updated
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
        let rules = try removalRows(selected, allowChild: allowChild)
        let ids = Set(rules.map(\.id))
        let appliedIDs = Set(snapshot.rules.filter { ids.contains($0.id) && $0.hasApplied }.map(\.id))
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

    private func removeSelected(_ selected: Set<UUID>, _ expected: BatchRemovalPreview) throws {
        try removeSelected(selected, expected, allowChild: false)
    }

    private func removeSelected(_ selected: Set<UUID>, _ expected: BatchRemovalPreview, allowChild: Bool) throws {
        let current = try previewRemoval(selected, allowChild: allowChild)
        guard current.rules == expected.rules, current.events == expected.events else { throw CalendarIntegrationError.removalSelectionChanged }
        let ids = Set(expected.rules.map(\.id))
        let appliedIDs = Set(snapshot.rules.filter { ids.contains($0.id) && $0.hasApplied }.map(\.id))
        var updated = snapshot
        updated.rules.removeAll { ids.contains($0.id) }
        updated.occurrences.removeAll { ids.contains($0.ruleID) }
        if !appliedIDs.isEmpty {
            try updated.preflightWrite()
            let previous = snapshot.occurrences.filter { appliedIDs.contains($0.ruleID) }
            try calendar.applyRemoval(previous: previous, ruleIDs: appliedIDs, matching: expected.events)
        }
        do {
            try updated.write()
        } catch {
            throw RuleOperationError(appliedIDs.isEmpty
                ? L10n.text("未能移除規則。請確認裝置空間後重試。", "The rules could not be removed. Check available storage and try again.")
                : L10n.text("已處理行事曆，但無法儲存本機規則。請保留畫面並先確認裝置空間。", "Calendar was updated, but the local rules could not be saved. Keep this screen open and check available storage."))
        }
        snapshot = updated
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
                                 category: String, subcategory: String, preferNickname: Bool) throws {
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
        if applyNow {
            do {
                var staging = updated
                staging.occurrences += planned
                try staging.preflightWrite()
            } catch {
                throw RuleOperationError(L10n.text("無法儲存匯入的規則，行事曆沒有變更。請確認裝置空間。", "The imported rules could not be saved. Calendar was not changed. Check available storage."))
            }
            let ids = Set(imported.map(\.id))
            _ = try calendar.preview(desired: planned, previous: [], ruleIDs: ids)
            updated.occurrences += try calendar.apply(desired: planned, previous: [], ruleIDs: ids)
        }
        do {
            try updated.write()
        } catch {
            throw RuleOperationError(applyNow
                ? L10n.text("已寫入行事曆，但本機規則未能儲存。請先確認裝置空間及行事曆，不要重複匯入。", "Calendar was updated, but the local rules could not be saved. Check available storage and your calendar before importing again.")
                : L10n.text("未能儲存匯入的生日，行事曆沒有變更。請確認裝置空間後重試。", "The imported birthdays could not be saved. Calendar was not changed. Check available storage and try again."))
        }
        snapshot = updated
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
            .disabled(!loaded || rootRules.isEmpty)
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
            let status = rule.hasApplied
                ? next.map { occurrence in
                    let civil = occurrence.isAllDay ? gregorianCalendar : RuleEngine.civilCalendar(for: rule)
                    let day = L10n.text("下次 ", "Next: ") + dateCaption(occurrence.start, calendar: civil)
                    return occurrence.isAllDay ? day : "\(day) \(timeCaption(occurrence.start, calendar: civil))"
                } ?? L10n.text("無後續日期", "No Upcoming Date")
                : L10n.text("未套用", "Not Applied")
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
    let onSave: (RuleAppearance) throws -> Void
    @State private var choice: RuleAppearance
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    init(title: String, initial: RuleAppearance, defaultSymbol: String,
         onSave: @escaping (RuleAppearance) throws -> Void) {
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
                        do {
                            try onSave(choice)
                            dismiss()
                        } catch {
                            failure = error.localizedDescription
                        }
                    }
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
    let onApply: (Rule) throws -> Rule
    let onApplied: () -> Void
    let previewDeletion: (UUID) throws -> BatchRemovalPreview
    let onDelete: (UUID, BatchRemovalPreview) throws -> Void
    let onDeleted: () -> Void
    let onSaveAppearance: (UUID, RuleAppearance) throws -> Bool
    let onOpenChild: (Rule, Bool) -> Void

    init(initial: Rule, isNew: Bool, parent: Rule?, allRules: [Rule], calendar: CalendarIntegration,
         preview: @escaping (Rule) throws -> RuleEventPreviewResult, onApply: @escaping (Rule) throws -> Rule,
         onApplied: @escaping () -> Void,
         previewDeletion: @escaping (UUID) throws -> BatchRemovalPreview,
         onDelete: @escaping (UUID, BatchRemovalPreview) throws -> Void,
         onDeleted: @escaping () -> Void,
         onSaveAppearance: @escaping (UUID, RuleAppearance) throws -> Bool,
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
    private var destinationID: String { parent?.target ?? (followsCategoryDestination ? suggestedDestinationID : rule.target) }
    private var previewRule: Rule {
        var submitted = rule
        submitted.target = destinationID
        return submitted
    }
    private var hasDestination: Bool { calendar.destinations.contains { $0.id == destinationID && $0.isWritable } }
    private var canApply: Bool { hasTitle && (parent != nil || !trimmedCategory.isEmpty) && hasDestination }
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

            Section {
                if children.isEmpty {
                    Text(L10n.text("尚無子規則", "No Child Rules Yet")).foregroundStyle(.secondary)
                }
                ForEach(visibleTreeRows) { row in
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
                .disabled(baseline == nil)
            } header: { Text(L10n.text("子規則", "Child Rules")) }
              footer: { Text(baseline == nil ? L10n.text("先套用這條規則，才能新增它的子規則。", "Apply this rule before adding child rules.") : L10n.text("可編輯直接子規則；縮排的下游項目僅供查看。", "You can edit direct child rules here. Deeper levels are shown for reference.")) }
            EventPreview(rule: previewRule, savedRules: allRules, civilCalendar: ruleCalendar, load: preview)
            if !isFreshRule {
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
        .navigationTitle(baseline == nil ? L10n.text("新增規則", "New Rule") : L10n.text("編輯規則", "Edit Rule"))
        .sheet(isPresented: $editingAppearance) {
            AppearanceEditSheet(title: rule.displayName, initial: rule.displayAppearance,
                                defaultSymbol: rule.defaultSymbol) { appearance in
                let value = appearance.isDefault ? nil : appearance
                guard rule.appearance != value else { return }
                let alreadySaved = try onSaveAppearance(rule.id, appearance)
                rule.appearance = value
                if alreadySaved {
                    baseline?.appearance = value
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
                try onDelete(rule.id, expected)
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
            operationError = missingRequiredPrompt
            return
        }
        do {
            var submitted = rule
            submitted.target = destinationID
            let saved = try onApply(submitted)
            rule = saved
            baseline = saved
            exitBaseline = saved
            onApplied()
        } catch {
            operationError = error.localizedDescription
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
                        RulePreviewTree(rows: preview.rules) { row in
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
                        Label(row.title, systemImage: collapsed.contains(row.id) ? "chevron.right" : "chevron.down")
                            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(collapsed.contains(row.id)
                        ? L10n.text("展開子規則：\(row.title)", "Expand child rules: \(row.title)")
                        : L10n.text("收合子規則：\(row.title)", "Collapse child rules: \(row.title)"))
                } else {
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
    let remove: (BatchRemovalPreview) throws -> Void
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
                        RulePreviewTree(rows: preview.rules) { row in
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
                        .disabled(preview == nil)
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
        guard let preview else { return }
        do {
            try remove(preview)
        } catch {
            self.preview = nil
            failure = error.localizedDescription
            if let calendarError = error as? CalendarIntegrationError {
                switch calendarError {
                case .writeFailed: canReload = false
                default: canReload = true
                }
            } else {
                canReload = false
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
    calendar.destinations.isEmpty
    #else
    !calendar.hasFullAccess
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
    let existingRuleIDs: () -> Set<UUID>
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
        do {
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
