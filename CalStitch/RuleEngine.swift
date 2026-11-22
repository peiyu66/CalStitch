import Foundation

/// Values use Foundation weekday numbering: Sunday = 1, Saturday = 7.
struct WeekdayPattern: Hashable, Codable {
    // Legacy annual patterns store a separate month; new ones follow the start date.
    var month: Int? = nil
    var ordinal: Int
    var weekday: Int
}

struct PlannedOccurrence: Hashable, Codable {
    var ruleID: UUID
    var key: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarID: String
}

enum RuleEngine {
    enum PlanningError: LocalizedError {
        case invalidRange, tooMany, invalidRule, unsupported(String)
        var errorDescription: String? {
            switch self {
            case .invalidRange: "截止日期不得早於起始日。"
            case .tooMany: "這條規則涵蓋的日期或事件太多，請縮短期間後再試。"
            case .invalidRule: "規則的日期、時間或關聯結構無法計算。"
            case let .unsupported(message): message
            }
        }
    }

    static let timeZone = TimeZone(identifier: "Asia/Taipei")!
    static let civil: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }()
    private static let lunar: Calendar = {
        var calendar = Calendar(identifier: .chinese)
        calendar.timeZone = timeZone
        return calendar
    }()
    private static let dayLimit = 36_600
    private static let occurrenceLimit = 10_000

    static func cutoff(for rule: Rule) throws -> Date {
        let start = civil.startOfDay(for: rule.start)
        let cutoff: Date
        switch rule.endMode {
        case .date:
            cutoff = civil.startOfDay(for: rule.endDate)
        case .duration:
            guard (1...36_600).contains(rule.endCount) else { throw PlanningError.tooMany }
            let anniversary: Date
            switch rule.endUnit {
            case .day, .week:
                anniversary = try adding(.day, rule.endCount * (rule.endUnit == .week ? 7 : 1), to: start)
            case .month, .year:
                anniversary = try monthShift(from: start, count: rule.endCount, unit: rule.endUnit, forceMonthEnd: false, rejectShortMonth: true)
            }
            cutoff = try adding(.day, -1, to: anniversary)
        }
        guard cutoff >= start else { throw PlanningError.invalidRange }
        return cutoff
    }

    static func plan(root: Rule, rules: [Rule]) throws -> [PlannedOccurrence] {
        guard root.parent == nil, (1...36_600).contains(root.interval) else { throw PlanningError.invalidRule }
        let start = civil.startOfDay(for: root.start)
        let last = try cutoff(for: root)
        let exclusive = try adding(.day, 1, to: last)
        guard let span = civil.dateComponents([.day], from: start, to: exclusive).day,
              span <= dayLimit else { throw PlanningError.tooMany }

        let days: [Date]
        switch root.kind {
        case .gregorian:
            if root.period == .week {
                days = try weeklyDays(root: root, start: start, exclusive: exclusive)
            } else if root.period != .day, let pattern = root.weekdayPattern {
                days = try weekdayPatternDays(root: root, pattern: pattern, start: start, exclusive: exclusive)
            } else {
                days = try gregorianDays(root: root, start: start, exclusive: exclusive)
            }
        case .lunar:
            days = try lunarDays(root: root, start: start, exclusive: exclusive)
        case .solar:
            days = try solarDays(root: root, start: start, last: last)
        }

        let children = Dictionary(grouping: rules.filter { $0.id != root.id }, by: \.parent)
        var output: [PlannedOccurrence] = []
        var visited = Set<UUID>()
        func add(_ rule: Rule, day: Date, ordinal: Int) throws {
            guard visited.insert(rule.id).inserted, visited.count <= 128 else { throw PlanningError.invalidRule }
            defer { visited.remove(rule.id) }
            guard day >= start, day < exclusive else {
                throw PlanningError.unsupported("「\(rule.name)」的日期超出根規則的起訖範圍。此情況目前無法套用。")
            }
            guard output.count < occurrenceLimit else { throw PlanningError.tooMany }
            let begin: Date
            let end: Date
            switch rule.timing {
            case .allDay:
                guard (1...3660).contains(rule.durationDays) else { throw PlanningError.invalidRule }
                begin = day
                end = try adding(.day, rule.durationDays, to: day)
            case .timed:
                guard (1...17_520).contains(rule.durationHalfHours) else { throw PlanningError.invalidRule }
                let hour = civil.component(.hour, from: rule.startTime)
                let minute = civil.component(.minute, from: rule.startTime)
                guard let timed = civil.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                      civil.isDate(timed, inSameDayAs: day),
                      civil.component(.hour, from: timed) == hour,
                      civil.component(.minute, from: timed) == minute else { throw PlanningError.invalidRule }
                begin = timed
                end = begin.addingTimeInterval(Double(rule.durationHalfHours) * 1800)
            }
            output.append(.init(ruleID: rule.id, key: String(ordinal), title: rule.name, start: begin, end: end,
                                isAllDay: rule.timing == .allDay, calendarID: rule.target))
            for child in children[rule.id] ?? [] {
                guard (0...3660).contains(child.offsetDays) else { throw PlanningError.invalidRule }
                let delta: Int
                switch child.position {
                case .before: delta = -child.offsetDays
                case .same: delta = 0
                case .after: delta = child.offsetDays
                }
                try add(child, day: adding(.day, delta, to: day), ordinal: ordinal)
            }
        }
        for (ordinal, day) in days.enumerated() { try add(root, day: day, ordinal: ordinal) }
        return output.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.ruleID.uuidString < $1.ruleID.uuidString
        }
    }

    private static func weekdayPatternDays(root: Rule, pattern: WeekdayPattern, start: Date, exclusive: Date) throws -> [Date] {
        guard root.period == .year || root.period == .month else {
            throw PlanningError.unsupported("第幾個星期幾的規則只適用於按年或按月重複。")
        }
        guard (1...4).contains(pattern.ordinal), (1...7).contains(pattern.weekday),
              let startMonth = civil.dateInterval(of: .month, for: start)?.start else {
            throw PlanningError.invalidRule
        }
        let annual = root.period == .year
        var month = startMonth
        if annual, let explicitMonth = pattern.month {
            guard (1...12).contains(explicitMonth),
                  let legacyMonth = civil.date(from: DateComponents(year: civil.component(.year, from: start),
                                                                   month: explicitMonth, day: 1)) else {
                throw PlanningError.invalidRule
            }
            month = legacyMonth
        }
        func occurrence(in month: Date) throws -> Date {
            let weekdayOffset = (pattern.weekday - civil.component(.weekday, from: month) + 7) % 7
            return try adding(.day, weekdayOffset + (pattern.ordinal - 1) * 7, to: month)
        }
        let unitMonths = annual ? 12 : 1
        if try occurrence(in: month) < start {
            // Monthly cadence remains tied to the start month, even when its date falls before start.
            // Annual retains the first eligible year behavior of existing saved rules.
            month = try adding(.month, annual ? unitMonths : root.interval, to: month)
        }
        var days: [Date] = []
        while month < exclusive {
            let date = try occurrence(in: month)
            if date >= exclusive { break }
            guard days.count < occurrenceLimit else { throw PlanningError.tooMany }
            days.append(date)
            month = try adding(.month, root.interval * unitMonths, to: month)
        }
        return days
    }

    private static func weeklyDays(root: Rule, start: Date, exclusive: Date) throws -> [Date] {
        let startWeekday = civil.component(.weekday, from: start)
        let weekday = root.weeklyWeekday ?? startWeekday
        guard (1...7).contains(weekday) else { throw PlanningError.invalidRule }
        var date = try adding(.day, (weekday - startWeekday + 7) % 7, to: start)
        var days: [Date] = []
        while date < exclusive {
            guard days.count < occurrenceLimit else { throw PlanningError.tooMany }
            days.append(date)
            date = try adding(.day, root.interval * 7, to: date)
        }
        return days
    }

    private static func gregorianDays(root: Rule, start: Date, exclusive: Date) throws -> [Date] {
        var days: [Date] = []
        let originalMonthEnd = civil.component(.day, from: start) == civil.range(of: .day, in: .month, for: start)?.last
        while days.count <= occurrenceLimit {
            let index = days.count * root.interval
            let day: Date
            if index == 0 { day = start }
            else if root.period == .day { day = try adding(.day, index, to: start) }
            else {
                day = try monthShift(from: start, count: index, unit: root.period,
                                     forceMonthEnd: originalMonthEnd && root.monthEnd)
            }
            if day >= exclusive { return days }
            guard let prior = days.last else { days.append(day); continue }
            guard day > prior else { throw PlanningError.invalidRule }
            days.append(day)
        }
        throw PlanningError.tooMany
    }

    private static func solarDays(root: Rule, start: Date, last: Date) throws -> [Date] {
        guard root.period == .year else {
            throw PlanningError.unsupported("節氣規則目前只支援按年重複。")
        }
        guard SolarTerms.names.contains(root.date) else { throw PlanningError.invalidRule }
        let startYear = civil.component(.year, from: start)
        let endYear = civil.component(.year, from: last)
        let coverage = SolarTerms.supportedYears
        func term(_ year: Int) throws -> Date {
            guard let date = SolarTerms.date(for: root.date, year: year, calendar: civil) else {
                throw PlanningError.unsupported("節氣日期目前只涵蓋 \(coverage.lowerBound) 至 \(coverage.upperBound) 年；請調整規則的起訖日期。")
            }
            return date
        }
        var year = startYear
        if try term(year) < start { year += 1 }
        var days: [Date] = []
        while year <= endYear {
            let date = try term(year)
            if date > last { break }
            days.append(date)
            year += root.interval
        }
        return days
    }

    private static func lunarDays(root: Rule, start: Date, exclusive: Date) throws -> [Date] {
        guard root.period == .year || root.period == .month else { throw PlanningError.unsupported("農曆規則目前只支援按月或按年重複。") }
        guard !root.lunarIsLeap else { throw PlanningError.unsupported("閏月生日的重複方式尚未決定，暫不能套用。") }
        guard (1...12).contains(root.lunarMonth), (1...30).contains(root.lunarDay) else { throw PlanningError.invalidRule }
        var days: [Date] = []
        // Civil-noon enumeration avoids midnight/time-zone shifts from date conversion.
        // Group by actual lunar months, including leap months as a separate identity.
        var cursor = start
        var ordinal = 0
        var prior: LunarMonth?
        var scheduled = false
        var sawDate = false
        func closeMonth() throws {
            if scheduled && !sawDate && root.lunarDay == 30 {
                throw PlanningError.unsupported("部分農曆月份沒有三十日，日期調整方式尚未決定，暫不能套用。")
            }
        }
        while cursor < exclusive {
            guard let noon = civil.date(bySettingHour: 12, minute: 0, second: 0, of: cursor) else { throw PlanningError.invalidRule }
            let parts = lunar.dateComponents([.era, .year, .month, .day, .isLeapMonth], from: noon)
            guard let era = parts.era, let year = parts.year, let month = parts.month, let day = parts.day else {
                throw PlanningError.invalidRule
            }
            let identity = LunarMonth(era: era, year: year, month: month, leap: parts.isLeapMonth == true)
            if prior != identity {
                if prior != nil { try closeMonth() }
                if identity.leap && root.period == .month {
                    throw PlanningError.unsupported("這段期間遇到農曆閏月，是否排入月週期尚未決定，暫不能套用。")
                }
                let candidate = !identity.leap && (root.period == .month || month == root.lunarMonth)
                scheduled = candidate && day <= root.lunarDay && ordinal % root.interval == 0
                if candidate && day <= root.lunarDay { ordinal += 1 }
                sawDate = false
                prior = identity
            }
            if scheduled && day == root.lunarDay {
                days.append(cursor)
                sawDate = true
                guard days.count <= occurrenceLimit else { throw PlanningError.tooMany }
            }
            // The cutoff may arrive before the lunar day; that is a normal excluded occurrence.
            cursor = try adding(.day, 1, to: cursor)
        }
        if let last = prior, scheduled && !sawDate && root.lunarDay == 30 {
            guard let noon = civil.date(bySettingHour: 12, minute: 0, second: 0, of: cursor) else { throw PlanningError.invalidRule }
            let parts = lunar.dateComponents([.era, .year, .month, .isLeapMonth], from: noon)
            if last.era != parts.era || last.year != parts.year || last.month != parts.month || last.leap != (parts.isLeapMonth == true) {
                try closeMonth()
            }
        }
        return days
    }

    private struct LunarMonth: Equatable {
        var era: Int
        var year: Int
        var month: Int
        var leap: Bool
    }

    private static func monthShift(from date: Date, count: Int, unit: PeriodUnit, forceMonthEnd: Bool, rejectShortMonth: Bool = false) throws -> Date {
        let parts = civil.dateComponents([.year, .month, .day], from: date)
        guard let day = parts.day,
              let first = civil.date(from: DateComponents(year: parts.year, month: parts.month, day: 1)) else {
            throw PlanningError.invalidRule
        }
        let monthDelta = count * (unit == .year ? 12 : 1)
        let candidate = try adding(.month, monthDelta, to: first)
        guard let maximum = civil.range(of: .day, in: .month, for: candidate)?.last else { throw PlanningError.invalidRule }
        if rejectShortMonth && day > maximum {
            throw PlanningError.unsupported("按期間換算時沒有對應的截止日，請改用指定截止日期。")
        }
        return try adding(.day, (forceMonthEnd ? maximum : min(day, maximum)) - 1, to: candidate)
    }

    private static func adding(_ component: Calendar.Component, _ value: Int, to date: Date) throws -> Date {
        guard let result = civil.date(byAdding: component, value: value, to: date) else { throw PlanningError.invalidRule }
        return result
    }
}
