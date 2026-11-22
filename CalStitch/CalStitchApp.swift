import SwiftUI

@main
struct CalStitchApp: App {
    var body: some Scene {
        WindowGroup { RulesHome() }
    }
}

private let slate = Color(red: 67/255, green: 88/255, blue: 119/255)
private let paper = Color(uiColor: .systemGroupedBackground)
private let card = Color(uiColor: .secondarySystemGroupedBackground)

private func uniqueNames(_ names: [String]) -> [String] {
    var seen = Set<String>()
    return names.filter { seen.insert($0).inserted }
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

    var symbol: String {
        switch self {
        case .lunar: "moon"
        case .solar: "sun.max"
        case .gregorian: "calendar"
        }
    }

    var subtitle: String {
        switch self {
        case .lunar: "依農曆月日選擇基準日期"
        case .solar: "從二十四節氣選擇"
        case .gregorian: "依西元日期設定"
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
}

enum EndMode: String, CaseIterable, Identifiable, Codable {
    case duration = "持續期間", date = "指定截止日期"
    var id: Self { self }
    var displayLabel: String { self == .duration ? "重複期間" : rawValue }
}

enum EventTiming: String, CaseIterable, Identifiable, Codable {
    case allDay = "整日", timed = "指定時間"
    var id: Self { self }
}

enum RelativePosition: String, CaseIterable, Identifiable, Codable {
    case before = "之前", same = "同一天", after = "之後"
    var id: Self { self }
}

struct Rule: Hashable, Identifiable, Codable {
    var id = UUID()
    var name: String
    var kind: RuleKind
    var date: String
    var lunarMonth = 1
    var lunarDay = 1
    var lunarIsLeap = false
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

    var displayName: String { name.isEmpty ? "未命名規則" : name }
    var displayAppearance: RuleAppearance { appearance ?? .init() }
    var defaultSymbol: String {
        category.contains("生日") || subcategory.contains("生日") ? "birthday.cake" : kind.symbol
    }

    var suggestedTitle: String? {
        guard parent == nil else { return nil }
        if kind == .solar { return SolarTerms.names.contains(date) ? date : nil }
        guard kind == .gregorian, period == .year, interval == 1,
              let pattern = weekdayPattern, pattern.ordinal == 2, pattern.weekday == 1,
              (pattern.month ?? gregorianCalendar.component(.month, from: start)) == 5 else { return nil }
        return "母親節"
    }

    var suggestedCategory: String? {
        guard parent == nil, birthdaySource == nil else { return nil }
        switch kind {
        case .solar: return "節氣"
        case .lunar: return "祭祀"
        case .gregorian: return suggestedTitle == "母親節" ? "節日" : nil
        }
    }

    var recurrenceCaption: String {
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

    mutating func useSolarDefaultDuration() {
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

private struct GroupAppearanceKey: Codable, Hashable, Identifiable {
    let category: String
    var subcategory: String? = nil
    var id: Self { self }
    var title: String { subcategory ?? category }
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

func dateCaption(_ date: Date) -> String {
    let parts = gregorianCalendar.dateComponents([.year, .month, .day, .weekday], from: date)
    let civilDate = "\(parts.year ?? 0)年\(parts.month ?? 0)月\(parts.day ?? 0)日"
    let weekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
    guard let weekday = parts.weekday, (1...7).contains(weekday) else { return civilDate }
    return "\(civilDate)（\(weekdays[weekday - 1])）"
}

private let taiwanClockLocale = Locale(identifier: "zh_TW@hours=h12")
private func timeCaption(_ date: Date) -> String {
    let parts = gregorianCalendar.dateComponents([.hour, .minute], from: date)
    let hour = parts.hour ?? 0
    let hour12 = hour % 12 == 0 ? 12 : hour % 12
    return "\(hour < 12 ? "上午" : "下午") \(String(format: "%02d:%02d", hour12, parts.minute ?? 0))"
}

private struct RuleDateField: View {
    enum Kind { case date, time }
    let title: String
    @Binding var selection: Date
    var kind: Kind = .date
    @State private var showingPicker = false
    @State private var draft = Date()

    var body: some View {
        Button {
            draft = selection
            showingPicker = true
        } label: {
            LabeledContent(title, value: kind == .date ? dateCaption(selection) : timeCaption(selection))
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
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showingPicker = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            selection = draft
                            showingPicker = false
                        }
                    }
                }
            }
            .environment(\.locale, taiwanClockLocale)
            .presentationDetents([.medium, .large])
        }
    }
}

private enum Route: Hashable {
    case edit(Rule, isNew: Bool)
}

private struct RulesHome: View {
    @StateObject private var calendar = CalendarIntegration()
    @State private var path: [Route] = []
    @State private var isAdding = false
    @State private var contactPickerRequest: UUID?
    @State private var birthdaySelection: BirthdayPickerSelection?
    @State private var selectingBirthdayGroup = false
    @State private var isSelectingBatch = false
    @State private var batchSelection: Set<UUID> = []
    @State private var isShowingBatch = false
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
                        Text("行事曆規則")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !isSelectingBatch { toolsRow }
                    }
                    if loaded && showGettingStarted && !isSelectingBatch { intro }
                    if !loaded && !loadFailed {
                        ProgressView("正在讀取規則…")
                    } else if loadFailed {
                        Button("重新讀取規則", action: load)
                    } else if rootRules.isEmpty {
                        emptyState
                    }
                    let names = uniqueNames(rootRules.map(\.category))
                    ForEach(names, id: \.self) { name in
                        category(name, rules: rootRules.filter { $0.category == name }, isFirst: name == names.first)
                    }
                    if loaded && !isSelectingBatch {
                        Button {
                            contactPickerRequest = UUID()
                        } label: {
                            Label("從通訊錄匯入生日", systemImage: "person.crop.rectangle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 3)
                        Button {
                            selectingBirthdayGroup = true
                        } label: {
                            Label("依群組匯入生日", systemImage: "person.2")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
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
                ToolbarItem(placement: .topBarLeading) {
                    if isSelectingBatch {
                        Button("取消") {
                            batchSelection.removeAll()
                            isSelectingBatch = false
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelectingBatch {
                    Button {
                        isShowingBatch = true
                    } label: {
                        Text("調整 \(batchSelection.count) 條規則")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(batchSelection.isEmpty)
                    .padding(16)
                    .background(.bar)
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .edit(let rule, let isNew):
                    RuleEditor(initial: snapshot.rules.first { $0.id == rule.id } ?? rule, isNew: isNew,
                               parent: snapshot.rules.first { $0.id == rule.parent },
                               allRules: snapshot.rules, calendar: calendar,
                               preview: preview, onApply: apply, onApplied: returnAfterApply,
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
                                   status: birthdayStatus, onImport: importBirthdays)
            }
            .sheet(isPresented: $selectingBirthdayGroup) {
                BirthdayGroupImportView(calendar: calendar, categories: batchCategories,
                                        status: birthdayStatus, onImport: importBirthdays)
            }
            .sheet(isPresented: $isShowingBatch) {
                BatchActionsView(selectedCount: batchSelection.count,
                                 categories: batchCategories,
                                 durationPreview: previewBatch, durationApply: applyBatch,
                                 move: moveSelected, removalPreview: previewRemoval, remove: removeSelected)
            }
            .sheet(item: $appearanceGroup) { key in
                AppearanceEditSheet(title: key.title, initial: groupAppearance(key),
                                    defaultSymbol: key.defaultSymbol) { newAppearance in
                    try saveGroupAppearance(newAppearance, for: key)
                }
            }
            .alert("無法完成操作", isPresented: Binding(
                get: { toolbarError != nil }, set: { if !$0 { toolbarError = nil } }
            )) {
                Button("好", role: .cancel) { toolbarError = nil }
            } message: { Text(toolbarError ?? "") }
        }
        .tint(slate)
        .onChange(of: snapshot.rules) { _, _ in snapshot.pruneGroupAppearances() }
        .overlay(alignment: .bottom) {
            if appliedNotice != nil {
                Label("已套用", systemImage: "checkmark.circle.fill")
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

    private func groupAppearance(_ key: GroupAppearanceKey) -> RuleAppearance {
        snapshot.groupAppearances?.first { $0.key == key }?.value ?? .init()
    }

    private func saveGroupAppearance(_ appearance: RuleAppearance, for key: GroupAppearanceKey) throws {
        guard rootRules.contains(where: { $0.category == key.category && (key.subcategory == nil || $0.subcategory == key.subcategory) }) else {
            throw RuleOperationError("找不到這個分類。")
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
        AccessibilityNotification.Announcement("已套用").post()
    }

    private func showAppleCalendar() {
        guard let url = URL(string: "calshow:") else { return }
        openURL(url) { accepted in
            if !accepted {
                toolbarError = "此裝置無法開啟 Apple 行事曆。請手動開啟「行事曆」App。"
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
            toolbarError = "讀取已儲存的規則失敗。原資料沒有覆寫。請重新開啟 App 或再試一次。\n\(error.localizedDescription)"
        }
    }

    private func resolve(_ input: Rule) throws -> RuleReconciliation {
        guard loaded else { throw RuleOperationError("規則尚未讀取，請返回列表後重試。") }
        var rule = input
        rule.name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.category = rule.category.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.subcategory = rule.subcategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.name.isEmpty else {
            throw RuleOperationError("事件標題為必填，請返回規則主頁填寫。")
        }
        guard rule.parent != nil || !rule.category.isEmpty else {
            throw RuleOperationError("分類為必填，請返回規則主頁填寫或選擇分類。")
        }
        if let parent = snapshot.rules.first(where: { $0.id == rule.parent }) {
            guard parent.hasApplied else { throw RuleOperationError("請先套用依據規則。") }
            rule.target = parent.target
            rule.category = parent.category
            rule.subcategory = parent.subcategory
        }
        guard !rule.target.isEmpty else { throw RuleOperationError("目的行事曆為必填。請返回規則主頁，先連接行事曆並選擇目的地。") }
        if let saved = snapshot.rules.first(where: { $0.id == rule.id }),
           saved.hasApplied && saved.target != rule.target {
            throw RuleOperationError("這條規則已套用，不能更換目的行事曆。")
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
                throw RuleOperationError("找不到有效的依據規則，請返回上一層確認。")
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
        do {
            let plan = try resolve(rule)
            let rows = try calendar.previewEvents(for: rule.id, desired: plan.desired, previous: plan.previous)
            return RuleEventPreviewResult(events: rows, warning: nil)
        } catch {
            let previous = snapshot.occurrences.filter { $0.ruleID == rule.id }
            guard !previous.isEmpty else { throw error }
            let existing = try calendar.existingPreviewEvents(for: rule.id, previous: previous)
            return RuleEventPreviewResult(
                events: existing,
                warning: "目前只能查看已確認的既有事件，無法預覽這次變更。\n\(error.localizedDescription)"
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
            throw RuleOperationError("裝置目前無法儲存規則。未變更行事曆，請確認裝置空間後再試。")
        }
        let committed = try calendar.apply(desired: plan.desired, previous: plan.previous, ruleIDs: plan.ruleIDs)
        updated.occurrences += committed
        do {
            try updated.write()
        } catch {
            throw RuleOperationError("行事曆已寫入，但規則未能儲存。請先檢查裝置空間與行事曆，不要重複套用。\n\(error.localizedDescription)")
        }
        snapshot = updated
        return updated.rules.first { $0.id == rule.id } ?? rule
    }

    private func batchPlan(years: Int) throws -> (plan: RuleReconciliation, rows: [BatchDurationRule]) {
        guard loaded, (1...999).contains(years), !batchSelection.isEmpty else {
            throw RuleOperationError("請選取至少一條規則，並輸入正整數年數。")
        }
        let selected = rootRules.filter { batchSelection.contains($0.id) }
        guard selected.count == batchSelection.count else {
            throw RuleOperationError("選取的規則已變更，請返回列表重新選取。")
        }
        var desired: [PlannedOccurrence] = []
        var previous: [PlannedOccurrence] = []
        var affected: Set<UUID> = []
        var updates: [UUID: Rule] = [:]
        var rows: [BatchDurationRule] = []
        for var rule in selected {
            rule.endMode = .duration
            rule.endCount = years
            rule.endUnit = .year
            do {
                let cutoff = try RuleEngine.cutoff(for: rule)
                if rule.hasApplied {
                    let branch = try resolve(rule)
                    guard affected.isDisjoint(with: branch.ruleIDs) else {
                        throw RuleOperationError("選取的規則包含重疊的分支。")
                    }
                    desired += branch.desired
                    previous += branch.previous
                    affected.formUnion(branch.ruleIDs)
                } else {
                    _ = try RuleEngine.plan(root: rule, rules: [rule])
                }
                updates[rule.id] = rule
                rows.append(.init(id: rule.id, title: rule.displayName, cutoff: cutoff, isDraft: !rule.hasApplied))
            } catch {
                throw RuleOperationError("「\(rule.displayName)」：\(error.localizedDescription)")
            }
        }
        let rules = snapshot.rules.map { updates[$0.id] ?? $0 }
        return (RuleReconciliation(desired: desired, previous: previous, ruleIDs: affected, rules: rules), rows)
    }

    private func previewBatch(years: Int) throws -> BatchDurationPreview {
        let batch = try batchPlan(years: years)
        let plan = batch.plan
        let changes = plan.ruleIDs.isEmpty ? [] : try calendar.preview(
            desired: plan.desired, previous: plan.previous, ruleIDs: plan.ruleIDs
        )
        return BatchDurationPreview(rules: batch.rows, changes: changes)
    }

    private func applyBatch(years: Int) throws {
        let plan = try batchPlan(years: years).plan
        var updated = snapshot
        updated.rules = plan.rules
        if !plan.ruleIDs.isEmpty {
            do {
                var staging = updated
                staging.occurrences += plan.desired
                try staging.preflightWrite()
            } catch {
                throw RuleOperationError("不能儲存規則，行事曆沒有變更。請確認裝置空間後再試。")
            }
            let committed = try calendar.apply(desired: plan.desired, previous: plan.previous, ruleIDs: plan.ruleIDs)
            updated.occurrences.removeAll { plan.ruleIDs.contains($0.ruleID) }
            updated.occurrences += committed
        }
        do {
            try updated.write()
        } catch {
            throw RuleOperationError(plan.ruleIDs.isEmpty
                ? "不能儲存規則，行事曆沒有變更。請確認裝置空間後再試。"
                : "行事曆已寫入，但規則未能儲存。請先檢查裝置空間與行事曆，不要重複套用。")
        }
        snapshot = updated
        batchSelection.removeAll()
        isSelectingBatch = false
    }

    private var batchCategories: [BatchCategoryOption] {
        uniqueNames(rootRules.map(\.category)).map { name in
            let children = rootRules.filter { $0.category == name && !$0.subcategory.isEmpty }
            return BatchCategoryOption(name: name, subcategories: uniqueNames(children.map(\.subcategory)))
        }
    }

    private func selectedTreeIDs() throws -> Set<UUID> {
        guard loaded, !batchSelection.isEmpty,
              batchSelection.isSubset(of: Set(rootRules.map(\.id))) else {
            throw RuleOperationError("請重新選擇要處理的根規則。")
        }
        let branches = Dictionary(grouping: snapshot.rules, by: \.parent)
        var ids = batchSelection
        var pending = Array(ids)
        while let parent = pending.popLast() {
            for child in branches[parent] ?? [] where ids.insert(child.id).inserted {
                pending.append(child.id)
            }
        }
        return ids
    }

    private func finishBatch() {
        batchSelection.removeAll()
        isSelectingBatch = false
    }

    private func moveSelected(category: String, subcategory: String) throws {
        let ids = try selectedTreeIDs()
        let category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let subcategory = subcategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !category.isEmpty else { throw RuleOperationError("請指定移動後的分類。") }
        var updated = snapshot
        for index in updated.rules.indices where ids.contains(updated.rules[index].id) {
            updated.rules[index].category = category
            updated.rules[index].subcategory = subcategory
        }
        try updated.write()
        snapshot = updated
        finishBatch()
    }

    private func previewRemoval() throws -> BatchRemovalPreview {
        let ids = try selectedTreeIDs()
        let appliedIDs = Set(snapshot.rules.filter { ids.contains($0.id) && $0.hasApplied }.map(\.id))
        let changes = appliedIDs.isEmpty ? [] : try calendar.preview(
            desired: [], previous: snapshot.occurrences.filter { appliedIDs.contains($0.ruleID) }, ruleIDs: appliedIDs
        )
        return BatchRemovalPreview(ruleCount: ids.count, eventCount: changes.count)
    }

    private func removeSelected() throws {
        let ids = try selectedTreeIDs()
        let appliedIDs = Set(snapshot.rules.filter { ids.contains($0.id) && $0.hasApplied }.map(\.id))
        var updated = snapshot
        updated.rules.removeAll { ids.contains($0.id) }
        updated.occurrences.removeAll { ids.contains($0.ruleID) }
        if !appliedIDs.isEmpty {
            try updated.preflightWrite()
            let previous = snapshot.occurrences.filter { appliedIDs.contains($0.ruleID) }
            _ = try calendar.apply(desired: [], previous: previous, ruleIDs: appliedIDs)
        }
        do {
            try updated.write()
        } catch {
            throw RuleOperationError(appliedIDs.isEmpty
                ? "未能移除規則。請確認裝置空間後重試。"
                : "已處理行事曆，但無法儲存本機規則。請保留畫面並先確認裝置空間。")
        }
        snapshot = updated
        finishBatch()
    }

    private func birthdayStatus(_ candidate: BirthdayCandidate) -> BirthdayDuplicateStatus {
        let sameContact = rootRules.filter {
            $0.birthdaySource?.contactID == candidate.source.contactID &&
            $0.birthdaySource?.isLunar == candidate.source.isLunar
        }
        if sameContact.contains(where: { $0.birthdaySource == candidate.source }) { return .imported }
        if !sameContact.isEmpty { return .changed }
        let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if rootRules.contains(where: { rule in
            guard rule.name.trimmingCharacters(in: .whitespacesAndNewlines) == name,
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

    private func importBirthdays(_ candidates: [BirthdayCandidate], years: Int, target: String?,
                                 category: String, subcategory: String) throws {
        guard loaded, (1...999).contains(years), !candidates.isEmpty else {
            throw RuleOperationError("請選擇要匯入的生日並填寫有效的期間。")
        }
        let category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let subcategory = subcategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !category.isEmpty else { throw RuleOperationError("請輸入生日規則的分類。") }
        let target = target.flatMap { value -> String? in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : clean
        }
        if let target, !calendar.destinations.contains(where: { $0.id == target && $0.isWritable }) {
            throw RuleOperationError("目的行事曆已不可用，請重新選擇。")
        }
        var updated = snapshot
        var imported: [Rule] = []
        var planned: [PlannedOccurrence] = []
        guard Set(candidates.map(\.id)).count == candidates.count else {
            throw RuleOperationError("選取清單有重複的生日，請返回確認。")
        }
        for candidate in candidates {
            switch birthdayStatus(candidate) {
            case .imported:
                throw RuleOperationError("「\(candidate.name)」已匯入，請重新選擇。")
            case .available, .possibleDuplicate, .changed:
                break
            }
            var rule = Rule(name: candidate.name, kind: candidate.isLunar ? .lunar : .gregorian,
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
                    throw RuleOperationError("無法判讀「\(candidate.name)」的生日日期。")
                }
                rule.start = foundDate
                // Birthdays are fixed month/day, not the final day of every February.
                rule.monthEnd = false
            }
            if let target {
                rule.target = target
                rule.hasApplied = true
                do {
                    planned += try RuleEngine.plan(root: rule, rules: [rule])
                } catch {
                    throw RuleOperationError("「\(candidate.name)」：\(error.localizedDescription)")
                }
            }
            imported.append(rule)
        }
        updated.rules.append(contentsOf: imported)
        if target != nil {
            do {
                var staging = updated
                staging.occurrences += planned
                try staging.preflightWrite()
            } catch {
                throw RuleOperationError("無法儲存匯入的規則，行事曆沒有變更。請確認裝置空間。")
            }
            let ids = Set(imported.map(\.id))
            _ = try calendar.preview(desired: planned, previous: [], ruleIDs: ids)
            updated.occurrences += try calendar.apply(desired: planned, previous: [], ruleIDs: ids)
        }
        do {
            try updated.write()
        } catch {
            throw RuleOperationError(target == nil
                ? "未能儲存匯入的生日，行事曆沒有變更。請確認裝置空間後重試。"
                : "已寫入行事曆，但本機規則未能儲存。請先確認裝置空間及行事曆，不要重複匯入。")
        }
        snapshot = updated
        if target == nil, imported.count == 1, let only = imported.first {
            path.append(.edit(only, isNew: true))
        }
    }

    private var toolsRow: some View {
        HStack {
            Button {
                batchSelection.removeAll()
                isSelectingBatch = true
            } label: {
                Label("批次調整", systemImage: "checklist")
                    .frame(minHeight: 44)
            }
            .disabled(!loaded || rootRules.isEmpty)
            .accessibilityIdentifier("start-batch")
            Spacer(minLength: 8)
            Button(action: showAppleCalendar) {
                Label("行事曆", systemImage: "calendar")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("open-apple-calendar")
        }
        .font(.subheadline.weight(.semibold))
    }

    private var intro: some View {
        Label("在這裡訂規則，在原本的行事曆看結果。", systemImage: "point.3.connected.trianglepath.dotted")
            .font(.subheadline)
            .foregroundStyle(slate)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(slate.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
    }

    private var emptyState: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if !isSelectingBatch { addRuleButton }
            ContentUnavailableView {
                Label("還沒有規則", systemImage: "calendar.badge.plus")
            } description: {
                Text("新增一條日期規則，或從通訊錄選擇生日匯入。")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var addRuleButton: some View {
        Button { isAdding = true } label: {
            Image(systemName: "plus.circle")
                .font(.title2.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("新增規則")
        .accessibilityIdentifier("add-rule")
    }

    private func category(_ title: String, rules: [Rule], isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if isSelectingBatch {
                groupCheck(title, ids: Set(rules.map(\.id)), isTop: true)
            } else {
                HStack(spacing: 8) {
                    groupLabel(.init(category: title))
                        .padding(.leading, 3)
                    if isFirst { addRuleButton }
                }
            }
            ForEach(uniqueNames(rules.map(\.subcategory)), id: \.self) { subcategory in
                let group = rules.filter { $0.subcategory == subcategory }
                VStack(alignment: .leading, spacing: 0) {
                    if !subcategory.isEmpty {
                        if isSelectingBatch {
                            groupCheck(subcategory, ids: Set(group.map(\.id)), isTop: false)
                                .padding(.horizontal, 15)
                        } else {
                            groupLabel(.init(category: title, subcategory: subcategory))
                                .padding(.horizontal, 8)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                    ForEach(group) { rule in
                        if !subcategory.isEmpty || rule.id != group.first?.id {
                            Divider().padding(.leading, 15)
                        }
                        if isSelectingBatch {
                            Button {
                                if !batchSelection.insert(rule.id).inserted { batchSelection.remove(rule.id) }
                            } label: {
                                ruleRow(rule)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(batchSelection.contains(rule.id) ? .isSelected : [])
                        } else {
                            NavigationLink(value: Route.edit(rule, isNew: !rule.hasApplied)) {
                                ruleRow(rule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .background(card, in: RoundedRectangle(cornerRadius: 18))
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
            .accessibilityLabel("調整\(key.title)圖示與顏色")
            .accessibilityIdentifier(key.subcategory == nil ? "category-appearance" : "subcategory-appearance")
            Text(key.title)
                .font(key.subcategory == nil ? .headline : .footnote.weight(.semibold))
                .foregroundStyle(key.subcategory == nil ? .primary : .secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
    }

    private func groupCheck(_ name: String, ids: Set<UUID>, isTop: Bool) -> some View {
        let count = ids.intersection(batchSelection).count
        let full = count == ids.count
        let symbol = full ? "checkmark.circle.fill" : count > 0 ? "minus.circle.fill" : "circle"
        return Button {
            if full { batchSelection.subtract(ids) } else { batchSelection.formUnion(ids) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(slate).accessibilityHidden(true)
                Text(name).font(isTop ? .headline : .subheadline.weight(.semibold))
                Spacer()
                Text("\(count)/\(ids.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue("已選 \(count) 條，共 \(ids.count) 條")
        .accessibilityHint(full ? "取消選取這個分類" : "選取這個分類的所有規則")
    }

    private func ruleRow(_ rule: Rule) -> some View {
        HStack(spacing: 11) {
            if isSelectingBatch {
                Image(systemName: batchSelection.contains(rule.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(slate)
                    .accessibilityHidden(true)
            }
            Image(systemName: rule.displayAppearance.symbol(or: rule.defaultSymbol))
                .foregroundStyle(rule.displayAppearance.tint(or: slate))
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(rule.displayAppearance.tint(or: slate).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                let title = Text(rule.name).font(.subheadline.weight(.semibold))
                let next = snapshot.occurrences.lazy.filter { $0.ruleID == rule.id && $0.start > Date() }.map(\.start).min()
                let status = rule.hasApplied
                    ? next.map { "下次 " + dateCaption($0) } ?? "無後續日期"
                    : "未套用"
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        title.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        Text(status)
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    title
                }

                let summary = Text(rule.recurrenceCaption).font(.caption).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        summary.fixedSize(horizontal: true, vertical: false)
                        Text("起始 " + dateCaption(rule.start))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    // Allow wrapping for accessibility sizes instead of truncating the summary.
                    summary.fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isSelectingBatch {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
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
                        if kind == .solar { rule.useSolarDefaultDuration() }
                        isAdding = false
                        path.append(.edit(rule, isNew: true))
                    } label: {
                        Label { VStack(alignment: .leading, spacing: 4) {
                            Text(kind.rawValue).foregroundStyle(.primary)
                            Text(kind.subtitle).font(.caption).foregroundStyle(.secondary)
                        } } icon: { Image(systemName: kind.symbol) }
                    }
                }
            }
            .navigationTitle("新增規則")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { isAdding = false } } }
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
            .navigationTitle("圖示與顏色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        do {
                            try onSave(choice)
                            dismiss()
                        } catch {
                            failure = error.localizedDescription
                        }
                    }
                }
            }
            .alert("無法儲存外觀", isPresented: Binding(
                get: { failure != nil }, set: { if !$0 { failure = nil } }
            )) {
                Button("好", role: .cancel) { failure = nil }
            } message: { Text(failure ?? "") }
        }
    }
}

private struct RuleEditor: View {
    @State private var rule: Rule
    @State private var baseline: Rule?
    @State private var exitBaseline: Rule
    @State private var pendingDiscard = false
    @State private var exitAction: ExitAction?
    private enum ExitAction { case apply, discard }
    @State private var operationError: String?
    @State private var connecting = false
    @State private var collapsedBranches: Set<UUID> = []
    @State private var editingAppearance = false
    @State private var followsSuggestedTitle: Bool
    @State private var followsSuggestedCategory: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    let parent: Rule?
    let allRules: [Rule]
    @ObservedObject var calendar: CalendarIntegration
    let preview: (Rule) throws -> RuleEventPreviewResult
    let onApply: (Rule) throws -> Rule
    let onApplied: () -> Void
    let onSaveAppearance: (UUID, RuleAppearance) throws -> Bool
    let onOpenChild: (Rule, Bool) -> Void

    init(initial: Rule, isNew: Bool, parent: Rule?, allRules: [Rule], calendar: CalendarIntegration,
         preview: @escaping (Rule) throws -> RuleEventPreviewResult, onApply: @escaping (Rule) throws -> Rule,
         onApplied: @escaping () -> Void,
         onSaveAppearance: @escaping (UUID, RuleAppearance) throws -> Bool,
         onOpenChild: @escaping (Rule, Bool) -> Void) {
        let isFresh = isNew && !allRules.contains { $0.id == initial.id }
        let shouldSuggest = isFresh && initial.name.isEmpty
        let shouldSuggestCategory = isFresh && initial.category.isEmpty
        var startingRule = initial
        if shouldSuggest, let suggestion = startingRule.suggestedTitle { startingRule.name = suggestion }
        if shouldSuggestCategory, let suggestion = startingRule.suggestedCategory { startingRule.category = suggestion }
        _followsSuggestedTitle = State(initialValue: shouldSuggest)
        _followsSuggestedCategory = State(initialValue: shouldSuggestCategory)
        _rule = State(initialValue: startingRule)
        _baseline = State(initialValue: isNew ? nil : initial)
        _exitBaseline = State(initialValue: startingRule)
        self.parent = parent
        self.allRules = allRules
        self.calendar = calendar
        self.preview = preview
        self.onApply = onApply
        self.onApplied = onApplied
        self.onSaveAppearance = onSaveAppearance
        self.onOpenChild = onOpenChild
    }

    private struct TreeRow: Identifiable {
        let item: Rule
        let depth: Int
        let hasChildren: Bool
        var id: UUID { item.id }
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
    private var destinationID: String { parent?.target ?? rule.target }
    private var hasDestination: Bool { calendar.destinations.contains { $0.id == destinationID && $0.isWritable } }
    private var canApply: Bool { hasTitle && (parent != nil || !trimmedCategory.isEmpty) && hasDestination }
    private var isDestinationLocked: Bool { parent != nil || baseline?.hasApplied == true }
    private var chosenDestination: String {
        let id = destinationID
        if let destination = calendar.destinations.first(where: { $0.id == id }) {
            return destination.isWritable ? destination.displayTitle : "\(destination.displayTitle)（唯讀）"
        }
        return id.isEmpty ? "尚未選擇" : "已無法使用"
    }
    private var availablePeriods: [PeriodUnit] {
        switch rule.kind {
        case .gregorian: PeriodUnit.allCases
        case .lunar: [.year, .month]
        case .solar: [.year]
        }
    }
    private var categoryOptions: [String] {
        uniqueNames(allRules.filter { $0.parent == nil }.map(\.category))
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
                    LabeledContent("依據規則", value: parent.displayName)
                    Picker("相對日期", selection: $rule.position) {
                        ForEach(RelativePosition.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if rule.position != .same {
                        Stepper("間隔：\(rule.offsetDays) 天", value: $rule.offsetDays, in: 1...999)
                    }
                } header: { Text("延伸日期") }
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
                    .accessibilityLabel("調整規則圖示與顏色")
                    .accessibilityIdentifier("rule-appearance")
                    VStack(alignment: .leading, spacing: 5) {
                        Text("事件標題（必填）")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(hasTitle ? Color.primary : Color.red)
                            .accessibilityHidden(true)
                        TextField("輸入事件標題", text: Binding(
                            get: { rule.name },
                            set: {
                                followsSuggestedTitle = false
                                rule.name = $0
                            }
                        ))
                            .accessibilityLabel("事件標題（必填）")
                            .accessibilityIdentifier("rule-title")
                    }
                }
                if parent == nil {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
                    layout {
                        categoryEntry("分類", placeholder: "請輸入", selection: Binding(
                            get: { rule.category },
                            set: {
                                followsSuggestedCategory = false
                                rule.category = $0
                            }
                        ), options: categoryOptions)
                        categoryEntry("次類", placeholder: "可留空", selection: $rule.subcategory, options: subcategoryOptions, optional: true)
                    }
                }
                calendarFields
            }

            if parent == nil { cutoff }

            Section {
                Toggle("整日", isOn: Binding(
                    get: { rule.timing == .allDay },
                    set: { rule.timing = $0 ? .allDay : .timed }
                ))
                .accessibilityIdentifier("all-day-toggle")
                if rule.timing == .timed {
                    RuleDateField(title: "開始時間", selection: $rule.startTime, kind: .time)
                        .id("single-event-time")
                }
                if rule.timing == .allDay {
                    Stepper("持續期間：\(rule.durationDays) 日", value: $rule.durationDays, in: 1...365)
                        .accessibilityIdentifier("single-event-days")
                } else {
                    Stepper("持續期間：\(hoursLabel) 小時", value: $rule.durationHalfHours, in: 1...48)
                        .accessibilityIdentifier("single-event-hours")
                }
            } header: { Text("單次事件") }

            Section {
                NavigationLink {
                    EventPreview { try preview(rule) }
                } label: {
                    Label("預覽事件", systemImage: "list.bullet.rectangle")
                }
                .accessibilityIdentifier("preview-events")
            }

            Section {
                if children.isEmpty {
                    Text("尚無子規則").foregroundStyle(.secondary)
                }
                ForEach(visibleTreeRows) { row in
                    treeRow(row)
                }
                Button {
                    var child = Rule(name: "", kind: rule.kind, date: rule.date, category: rule.category, subcategory: rule.subcategory, parent: rule.id)
                    child.target = rule.target
                    onOpenChild(child, true)
                } label: {
                    Label("新增子規則", systemImage: "plus")
                }
                .disabled(baseline == nil)
            } header: { Text("子規則") }
              footer: { Text(baseline == nil ? "先套用這條規則，才能新增它的子規則。" : "可編輯直接子規則；縮排的下游項目僅供查看。") }
        }
        .onChange(of: rule.suggestedTitle) { _, suggestion in
            if followsSuggestedTitle { rule.name = suggestion ?? "" }
        }
        .onChange(of: rule.suggestedCategory) { _, suggestion in
            if followsSuggestedCategory { rule.category = suggestion ?? "" }
        }
        .navigationTitle(baseline == nil ? "新增規則" : "編輯規則")
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
                        Label("返回", systemImage: "chevron.left")
                    }
                    .accessibilityIdentifier("guarded-back")
                }
            }
            if dirty {
                ToolbarItem(placement: .confirmationAction) {
                    Button("套用", action: applyAndReturn)
                    .fontWeight(.semibold)
                    .disabled(!canApply)
                    .accessibilityIdentifier("apply-rule")
                }
            }
        }
        .sheet(isPresented: $pendingDiscard, onDismiss: handleExitAction) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("尚有變更未套用，要如何處理？")
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
                        Text("套用並返回").frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApply)
                    Button(role: .destructive) {
                        exitAction = .discard
                        pendingDiscard = false
                    } label: {
                        Text("捨棄變更").frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    Button {
                        pendingDiscard = false
                    } label: {
                        Text("繼續編輯").frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(24)
            }
            .presentationDetents([.medium, .large])
        }
        .alert("無法完成操作", isPresented: Binding(
            get: { operationError != nil }, set: { if !$0 { operationError = nil } }
        )) {
            Button("好", role: .cancel) { operationError = nil }
        } message: { Text(operationError ?? "") }
    }

    private var missingRequiredPrompt: String {
        var missing: [String] = []
        if !hasTitle { missing.append("事件標題") }
        if parent == nil && trimmedCategory.isEmpty { missing.append("分類") }
        if !hasDestination { missing.append("指定行事曆") }
        return "請繼續編輯，補齊\(missing.joined(separator: "、"))後再套用。"
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
            let saved = try onApply(rule)
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
                            if !isDestinationLocked, rule.target.isEmpty, writable.count == 1 {
                                rule.target = writable[0].id
                            }
                            #endif
                        } catch {
                            operationError = error.localizedDescription
                        }
                    }
                } label: {
                    if connecting {
                        ProgressView("正在連接行事曆…")
                    } else {
                        Label("連接行事曆", systemImage: "calendar.badge.plus")
                    }
                }
                .disabled(connecting)
                .accessibilityIdentifier("connect-calendar")
            }
            if isDestinationLocked || calendar.destinations.isEmpty {
                LabeledContent {
                    Text(chosenDestination)
                } label: {
                    Text("指定行事曆（必填）")
                        .foregroundStyle(hasDestination ? Color.primary : Color.red)
                }
            } else {
                CalendarDestinationField(title: "指定行事曆（必填）", selectedTitle: chosenDestination,
                                         selectedID: destinationID, isValid: hasDestination,
                                         destinations: calendar.destinations) { rule.target = $0 }
                    .accessibilityIdentifier("rule-destination")
            }
            if calendar.hasFullAccess, !calendar.destinations.contains(where: \.isWritable), !connecting {
                Text("目前沒有可寫入的行事曆。請在 Apple 行事曆中加入可編輯的行事曆，再回來選擇。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
    }

    private func categoryEntry(_ label: String, placeholder: String, selection: Binding<String>, options: [String], optional: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(optional ? label : "\(label)（必填）")
                .font(.caption.weight(.medium))
                .foregroundStyle(!optional && selection.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                 ? Color.red : Color.primary)
                .accessibilityHidden(true)
            HStack(spacing: 2) {
                TextField(placeholder, text: selection)
                    .lineLimit(1)
                    .accessibilityLabel(optional ? label : "\(label)（必填）")
                    .accessibilityIdentifier(optional ? "rule-subcategory" : "rule-category")
                Menu {
                    if optional {
                        Button("不分次類") { selection.wrappedValue = "" }
                    }
                    ForEach(options, id: \.self) { name in
                        Button {
                            selection.wrappedValue = name
                        } label: {
                            if selection.wrappedValue == name {
                                Label(name, systemImage: "checkmark")
                            } else {
                                Text(name)
                            }
                        }
                    }
                    if options.isEmpty && optional {
                        Text("這個分類沒有既有次類")
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!optional && options.isEmpty)
                .accessibilityLabel("選擇既有\(label)")
                .accessibilityIdentifier(optional ? "subcategory-options" : "category-options")
            }
            .padding(.leading, 9)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .accessibilityLabel(isCollapsed ? "展開\(row.item.displayName)" : "收合\(row.item.displayName)")
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
                .accessibilityHint("編輯這條子規則")
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
            Picker("類型", selection: $rule.kind) {
                ForEach(RuleKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .onChange(of: rule.kind) { _, kind in
                rule.date = kind.dates.first ?? ""
                if !availablePeriods.contains(rule.period) { rule.period = .year }
                if kind != .gregorian {
                    rule.weekdayPattern = nil
                    rule.weeklyWeekday = nil
                }
                if kind == .solar { rule.useSolarDefaultDuration() }
            }
            if rule.kind == .lunar {
                if rule.period == .year {
                    Picker("農曆月", selection: $rule.lunarMonth) {
                        ForEach(1...12, id: \.self) { Text("\($0) 月").tag($0) }
                    }
                }
                Picker("農曆日", selection: $rule.lunarDay) {
                    ForEach(1...30, id: \.self) { Text("\($0) 日").tag($0) }
                }
                if rule.lunarIsLeap {
                    Toggle("閏月生日", isOn: $rule.lunarIsLeap)
                }
            } else if rule.kind == .solar {
                Picker("節氣", selection: $rule.date) {
                    ForEach(RuleKind.solar.dates, id: \.self) { Text($0).tag($0) }
                }
                Link(SolarTerms.attribution, destination: SolarTerms.sourceURL)
                    .font(.footnote)
            }
            RuleDateField(title: "起始日", selection: $rule.start)
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
            Picker("週期", selection: $rule.period) {
                ForEach(availablePeriods) { Text($0.rawValue).tag($0) }
            }
            .onChange(of: rule.period) { previous, period in
                if period != .year && period != .month {
                    rule.weekdayPattern = nil
                } else if previous != period, let pattern = rule.weekdayPattern {
                    rule.weekdayPattern = WeekdayPattern(month: nil, ordinal: pattern.ordinal, weekday: pattern.weekday)
                }
                if period != .week { rule.weeklyWeekday = nil }
            }
            Stepper("間隔：每 \(rule.interval) \(rule.period.rawValue)", value: $rule.interval, in: 1...999)
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
                    LabeledContent("下次日期", value: nextWeekdayDateCaption)
                }
            }
            if allowsMonthEnd {
                Toggle("固定在月底", isOn: $rule.monthEnd)
            }
        } header: { Text("日期與週期") }
          footer: {
              if rule.kind == .solar {
                  Text("節氣一律以台灣日期為準。內建資料涵蓋 \(SolarTerms.supportedYears.lowerBound)～\(SolarTerms.supportedYears.upperBound) 年，無須連網。")
              } else if rule.kind == .lunar {
                  Text(rule.lunarIsLeap ? "目前無法套用閏月生日規則。" : "按月重複若遇到閏月，請先縮短期間；閏月排程方式尚未確定。")
              } else if allowsMonthEnd {
                  Text("例如 6/30 起每月重複，固定在月底時，下一筆是 7/31。")
              }
          }
    }

    @ViewBuilder private var weekdayCondition: some View {
        Picker("日期條件", selection: Binding(
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
            Text(rule.period == .year ? "固定月日" : "固定日期").tag(false)
            Text("固定星期幾").tag(true)
        }
        if let pattern = rule.weekdayPattern {
            HStack {
                Picker("第幾個", selection: conditionValue(\.ordinal)) {
                    ForEach(1...4, id: \.self) { Text("第 \($0) 個").tag($0) }
                }
                .labelsHidden()
                weekdayPicker(selection: conditionValue(\.weekday)).labelsHidden()
            }
            if rule.period == .year, let preservedMonth = pattern.month,
               preservedMonth != gregorianCalendar.component(.month, from: rule.start) {
                Text("此規則保留原先指定的 \(preservedMonth) 月。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func weekdayPicker(selection: Binding<Int>) -> some View {
        Picker("星期幾", selection: selection) {
            ForEach(1...7, id: \.self) { Text(weekdayName($0)).tag($0) }
        }
    }

    private func weekdayName(_ number: Int) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        return (1...7).contains(number) ? "星期\(names[number - 1])" : "星期幾"
    }

    private var weekdaySummary: String? {
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
            return next.map(dateCaption) ?? "期間內沒有下次日期"
        } catch {
            return "無法換算"
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

    private var cutoff: some View {
        Section {
            Picker("截止方式", selection: $rule.endMode) {
                ForEach(EndMode.allCases) { Text($0.displayLabel).tag($0) }
            }
            if rule.endMode == .duration {
                Picker("重複期間單位", selection: $rule.endUnit) {
                    ForEach(PeriodUnit.allCases.filter { $0 != .week }) { Text($0.rawValue).tag($0) }
                }
                Stepper("重複期間：\(rule.endCount) \(rule.endUnit.rawValue)", value: $rule.endCount, in: 1...999)
                if let date = try? RuleEngine.cutoff(for: rule) {
                    LabeledContent("換算截止日", value: dateCaption(date))
                } else {
                    LabeledContent("換算截止日", value: "無法換算")
                }
            } else {
                RuleDateField(title: "截止日期", selection: $rule.endDate)
            }
        } header: { Text("規則截止") }
          footer: { Text("截止包含指定日期當天。") }
    }

    private var hoursLabel: String {
        let whole = rule.durationHalfHours / 2
        return rule.durationHalfHours.isMultiple(of: 2) ? "\(whole)" : "\(whole).5"
    }
}

struct RuleEventPreviewResult {
    let events: [CalendarPreviewEvent]
    let warning: String?
}

private struct EventPreview: View {
    let load: () throws -> RuleEventPreviewResult
    @State private var events: [CalendarPreviewEvent]?
    @State private var warning: String?
    @State private var failure: String?

    var body: some View {
        List {
            Section {
                if let failure {
                    Label(failure, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                    Button("重新整理", action: refresh)
                } else if let events {
                    if let warning {
                        Label(warning, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if events.isEmpty {
                        Text("此規則沒有可預覽的事件")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(events) { event in eventRow(event) }
                    }
                } else {
                    ProgressView("正在讀取事件…")
                }
            } footer: {
                Text("這裡列出本規則已寫入行事曆的事件，以及尚未套用的變更。按「套用」後才會更新行事曆。")
            }
        }
        .navigationTitle("預覽事件")
        .navigationBarTitleDisplayMode(.inline)
        .task { refresh() }
    }

    private func refresh() {
        do {
            let result = try load()
            events = result.events.sorted {
                ($0.start, $0.id) < ($1.start, $1.id)
            }
            warning = result.warning
            failure = nil
        } catch {
            events = nil
            warning = nil
            failure = error.localizedDescription
        }
    }

    private func eventRow(_ event: CalendarPreviewEvent) -> some View {
        let status: (label: String, color: Color)? = switch event.kind {
        case .unchanged: nil
        case .insert: ("將新增", .green)
        case .update: ("將修改", slate)
        case .remove: ("將移除", .red)
        }
        let revisedTime: Bool
        if case .update = event.kind, let oldStart = event.previousStart {
            revisedTime = oldStart != event.start || event.previousEnd != event.end || event.previousIsAllDay != event.isAllDay
        } else {
            revisedTime = false
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(event.title).font(.subheadline.weight(.semibold))
            if revisedTime, let oldStart = event.previousStart {
                Text("原：\(eventTime(start: oldStart, end: event.previousEnd ?? oldStart, allDay: event.previousIsAllDay ?? event.isAllDay))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(revisedTime ? "改為：" : "")\(eventTime(start: event.start, end: event.end, allDay: event.isAllDay))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if let status {
                Text(status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.color)
            }
        }
        .foregroundStyle(event.isPast ? Color.secondary : Color.primary)
        .opacity(event.isPast ? 0.65 : 1)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func eventTime(start: Date, end: Date, allDay: Bool) -> String {
        let date = dateCaption(start)
        if allDay {
            let lastDay = gregorianCalendar.date(byAdding: .day, value: -1, to: end) ?? end
            return lastDay > start ? "\(date) 至 \(dateCaption(lastDay))" : date
        }
        guard end > start else { return "\(date) \(timeCaption(start))" }
        let endDate = gregorianCalendar.isDate(start, inSameDayAs: end) ? "" : "\(dateCaption(end)) "
        return "\(date) \(timeCaption(start)) 至 \(endDate)\(timeCaption(end))"
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
                Section("可寫入") {
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
                Section("唯讀，不能選擇") {
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
                Text(title).foregroundStyle(isValid ? Color.primary : Color.red)
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(selectedTitle)
    }
}
