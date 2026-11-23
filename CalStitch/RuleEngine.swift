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
    // All-day start/end remain Taipei-encoded floating dates; timed values are absolute.
    var timeZoneIdentifier: String? = nil
}

enum RuleEngine {
    enum PlanningError: LocalizedError {
        case invalidRange, tooMany, invalidRule, unsupported(String)
        var errorDescription: String? {
            switch self {
            case .invalidRange: L10n.text("截止日期不得早於起始日。", "The end date cannot be before the start date.")
            case .tooMany: L10n.text("這條規則涵蓋的日期或事件太多，請縮短期間後再試。", "This rule covers too many days or events. Shorten the date range and try again.")
            case .invalidRule: L10n.text("規則的日期、時間或關聯結構無法計算。", "CalStitch could not calculate the dates, times, or linked rules.")
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

    static func civilCalendar(for rule: Rule) -> Calendar {
        guard rule.kind == .solar, let identifier = rule.solarTimeZoneIdentifier,
              let zone = TimeZone(identifier: identifier) else { return civil }
        var calendar = civil
        calendar.timeZone = zone
        return calendar
    }

    static func cutoff(for rule: Rule) throws -> Date {
        if rule.kind == .solar, let identifier = rule.solarTimeZoneIdentifier,
           TimeZone(identifier: identifier) == nil {
            throw PlanningError.unsupported(L10n.text("找不到原規則的時區，請重新設定。", "This rule’s time zone is unavailable. Choose another time zone."))
        }
        let calendar = civilCalendar(for: rule)
        let pinned = rule.kind == .solar && rule.solarTimeZoneIdentifier != nil
        let start = calendar.startOfDay(for: rule.start)
        let cutoff: Date
        switch rule.endMode {
        case .date:
            cutoff = calendar.startOfDay(for: rule.endDate)
        case .duration:
            guard (1...36_600).contains(rule.endCount) else { throw PlanningError.tooMany }
            let anniversary: Date
            switch rule.endUnit {
            case .day, .week:
                anniversary = try adding(.day, rule.endCount * (rule.endUnit == .week ? 7 : 1), to: start, calendar: calendar)
            case .month, .year:
                anniversary = try monthShift(from: start, count: rule.endCount, unit: rule.endUnit, forceMonthEnd: false, rejectShortMonth: true, calendar: calendar)
            }
            cutoff = try adding(.day, -1, to: anniversary, calendar: calendar)
        }
        guard cutoff >= start else { throw PlanningError.invalidRange }
        return pinned ? calendar.startOfDay(for: cutoff) : cutoff
    }

    static func plan(root: Rule, rules: [Rule]) throws -> [PlannedOccurrence] {
        guard root.parent == nil, (1...36_600).contains(root.interval) else { throw PlanningError.invalidRule }
        let calendar = civilCalendar(for: root)
        let pinnedZone = root.kind == .solar ? root.solarTimeZoneIdentifier : nil
        let start = calendar.startOfDay(for: root.start)
        let last = try cutoff(for: root)
        func shiftDay(_ day: Date, by count: Int) throws -> Date {
            let shifted = try adding(.day, count, to: day, calendar: calendar)
            // Some zones skip midnight at DST transitions. Restore the actual civil boundary
            // after offsetting from a day that began at a non-midnight local wall time.
            return pinnedZone == nil ? shifted : calendar.startOfDay(for: shifted)
        }
        let exclusive = try shiftDay(last, by: 1)
        guard let span = calendar.dateComponents([.day], from: start, to: exclusive).day,
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
            days = try solarDays(root: root, start: start, last: last, calendar: calendar)
        }

        let children = Dictionary(grouping: rules.filter { $0.id != root.id }, by: \.parent)
        var output: [PlannedOccurrence] = []
        var visited = Set<UUID>()
        func add(_ rule: Rule, day: Date, ordinal: Int) throws {
            guard visited.insert(rule.id).inserted, visited.count <= 128 else { throw PlanningError.invalidRule }
            defer { visited.remove(rule.id) }
            guard day >= start, day < exclusive else {
                throw PlanningError.unsupported(L10n.text("「\(rule.name)」的日期超出根規則的起訖範圍。此情況目前無法套用。", "“\(rule.name)” falls outside the top-level rule’s date range. This rule cannot be applied."))
            }
            guard output.count < occurrenceLimit else { throw PlanningError.tooMany }
            let begin: Date
            let end: Date
            switch rule.timing {
            case .allDay:
                guard (1...3660).contains(rule.durationDays) else { throw PlanningError.invalidRule }
                let localEnd = try shiftDay(day, by: rule.durationDays)
                if pinnedZone != nil {
                    // Calendar integrations store civil all-day dates independently of a timezone.
                    begin = try floatingDate(day, from: calendar)
                    end = try floatingDate(localEnd, from: calendar)
                } else {
                    begin = day
                    end = localEnd
                }
            case .timed:
                guard (1...17_520).contains(rule.durationHalfHours) else { throw PlanningError.invalidRule }
                let hour = calendar.component(.hour, from: rule.startTime)
                let minute = calendar.component(.minute, from: rule.startTime)
                guard let timed = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                      calendar.isDate(timed, inSameDayAs: day),
                      calendar.component(.hour, from: timed) == hour,
                      calendar.component(.minute, from: timed) == minute else { throw PlanningError.invalidRule }
                begin = timed
                end = begin.addingTimeInterval(Double(rule.durationHalfHours) * 1800)
            }
            output.append(.init(ruleID: rule.id, key: String(ordinal), title: rule.name, start: begin, end: end,
                                isAllDay: rule.timing == .allDay, calendarID: rule.target, timeZoneIdentifier: pinnedZone))
            for child in children[rule.id] ?? [] {
                guard (0...3660).contains(child.offsetDays) else { throw PlanningError.invalidRule }
                let delta: Int
                switch child.position {
                case .before: delta = -child.offsetDays
                case .same: delta = 0
                case .after: delta = child.offsetDays
                }
                try add(child, day: shiftDay(day, by: delta), ordinal: ordinal)
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
            throw PlanningError.unsupported(L10n.text("第幾個星期幾的規則只適用於按年或按月重複。", "Rules for a numbered weekday, such as the second Sunday, can repeat only yearly or monthly."))
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

    private static func solarDays(root: Rule, start: Date, last: Date, calendar: Calendar) throws -> [Date] {
        guard root.period == .year else {
            throw PlanningError.unsupported(L10n.text("節氣規則目前只支援按年重複。", "Solar term rules can repeat only yearly."))
        }
        guard SolarTerms.names.contains(root.date) else { throw PlanningError.invalidRule }
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: last)
        let coverage = SolarTerms.supportedYears
        func term(_ year: Int) throws -> Date {
            let date: Date?
            if root.solarTimeZoneIdentifier == nil {
                date = SolarTerms.date(for: root.date, year: year, calendar: civil)
            } else {
                date = SolarTerms.instant(for: root.date, year: year).map { calendar.startOfDay(for: $0) }
            }
            guard let date else {
                throw PlanningError.unsupported(L10n.text("節氣日期目前只涵蓋 \(coverage.lowerBound) 至 \(coverage.upperBound) 年；請調整規則的起訖日期。", "Solar term dates are available from \(coverage.lowerBound) to \(coverage.upperBound). Adjust the rule’s date range."))
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
        guard root.period == .year || root.period == .month else {
            throw PlanningError.unsupported(L10n.text("農曆規則目前只支援按月或按年重複。", "Lunar rules can repeat only monthly or yearly."))
        }
        guard (1...12).contains(root.lunarMonth), (1...30).contains(root.lunarDay) else {
            throw PlanningError.invalidRule
        }

        func shift(_ date: Date, days: Int) throws -> Date {
            civil.startOfDay(for: try adding(.day, days, to: date))
        }
        func lunarDay(_ date: Date) throws -> (month: LunarMonth, day: Int) {
            // Convert at civil noon to avoid changes in historical midnight conventions.
            guard let noon = civil.date(bySettingHour: 12, minute: 0, second: 0, of: date) else {
                throw PlanningError.invalidRule
            }
            let parts = lunar.dateComponents([.era, .year, .month, .day, .isLeapMonth], from: noon)
            guard let era = parts.era, let year = parts.year,
                  let month = parts.month, let day = parts.day else {
                throw PlanningError.invalidRule
            }
            return (LunarMonth(era: era, year: year, month: month, leap: parts.isLeapMonth == true), day)
        }

        let startingDay = try lunarDay(start)
        var first = try shift(start, days: 1 - startingDay.day)
        var candidates: [Date] = []
        var ordinal = 0
        while first < exclusive {
            let current = try lunarDay(first)
            guard current.day == 1 else { throw PlanningError.invalidRule }

            // After 29 civil days, a short month has ended; a long one is on day 30.
            let dayAfter29 = try shift(first, days: 29)
            let probe = try lunarDay(dayAfter29)
            let count: Int
            let nextFirst: Date
            let next: LunarMonth
            if probe.month == current.month {
                guard probe.day == 30 else { throw PlanningError.invalidRule }
                count = 30
                nextFirst = try shift(dayAfter29, days: 1)
                let nextDay = try lunarDay(nextFirst)
                guard nextDay.day == 1, nextDay.month != current.month else { throw PlanningError.invalidRule }
                next = nextDay.month
            } else {
                guard probe.day == 1 else { throw PlanningError.invalidRule }
                count = 29
                nextFirst = dayAfter29
                next = probe.month
            }

            let matches: Bool
            if root.period == .month {
                matches = !current.month.leap || (root.includeLeapMonths ?? true)
            } else if current.month.month != root.lunarMonth {
                matches = false
            } else if !root.lunarIsLeap {
                matches = !current.month.leap
            } else if current.month.leap {
                matches = true
            } else {
                // A same-name leap month immediately follows its regular month.
                // Even if it falls beyond this rule's cutoff, don't fall back erroneously.
                matches = !(next.era == current.month.era && next.year == current.month.year
                            && next.month == current.month.month && next.leap)
            }

            if matches {
                let day = try shift(first, days: min(root.lunarDay, count) - 1)
                if day >= start && day < exclusive {
                    if ordinal.isMultiple(of: root.interval) {
                        candidates.append(day)
                        guard candidates.count <= occurrenceLimit else { throw PlanningError.tooMany }
                    }
                    ordinal += 1
                }
            }
            first = nextFirst
        }
        return candidates
    }

    private struct LunarMonth: Equatable {
        var era: Int
        var year: Int
        var month: Int
        var leap: Bool
    }

    private static func floatingDate(_ date: Date, from calendar: Calendar) throws -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let floating = civil.date(from: components) else { throw PlanningError.invalidRule }
        return floating
    }

    private static func monthShift(from date: Date, count: Int, unit: PeriodUnit, forceMonthEnd: Bool, rejectShortMonth: Bool = false, calendar: Calendar = civil) throws -> Date {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let day = parts.day,
              let first = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: 1)) else {
            throw PlanningError.invalidRule
        }
        let monthDelta = count * (unit == .year ? 12 : 1)
        let candidate = try adding(.month, monthDelta, to: first, calendar: calendar)
        guard let maximum = calendar.range(of: .day, in: .month, for: candidate)?.last else { throw PlanningError.invalidRule }
        if rejectShortMonth && day > maximum {
            throw PlanningError.unsupported(L10n.text("按期間換算時沒有對應的截止日，請改用指定截止日期。", "No matching end date exists for this duration. Choose an end date instead."))
        }
        return try adding(.day, (forceMonthEnd ? maximum : min(day, maximum)) - 1, to: candidate, calendar: calendar)
    }

    private static func adding(_ component: Calendar.Component, _ value: Int, to date: Date, calendar: Calendar = civil) throws -> Date {
        guard let result = calendar.date(byAdding: component, value: value, to: date) else { throw PlanningError.invalidRule }
        return result
    }
}
