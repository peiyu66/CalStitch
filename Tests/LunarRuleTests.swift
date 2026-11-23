import Foundation

// Compile with RuleEngine.swift, SolarTerms.swift, L10n.swift, and the Rule model.
@main
struct LunarRuleTests {
    static func main() throws {
        func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
            RuleEngine.civil.date(from: DateComponents(year: year, month: month, day: day))!
        }
        func check(_ rule: Rule, _ expected: [Date], _ label: String) throws {
            let plan = try RuleEngine.plan(root: rule, rules: [rule])
            precondition(plan.map(\.start) == expected, "\(label): \(plan.map(\.start)) != \(expected)")
            precondition(plan.map(\.key) == expected.indices.map(String.init), "Unexpected keys: \(label)")
        }

        // Published Gregorian/lunar table dates; 2025 has a leap sixth month.
        // https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2025e.pdf
        // https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2024e.pdf
        var monthly = Rule(name: "Monthly", kind: .lunar, date: "", lunarMonth: 6, lunarDay: 1,
                           category: "Tests", period: .month, start: day(2025, 6, 25),
                           endMode: .date, endDate: day(2025, 8, 23), target: "calendar")
        try check(monthly, [day(2025, 6, 25), day(2025, 7, 25), day(2025, 8, 23)], "Default includes leap")
        monthly.includeLeapMonths = false
        try check(monthly, [day(2025, 6, 25), day(2025, 8, 23)], "Disabled excludes leap")
        monthly.includeLeapMonths = true
        monthly.interval = 2
        try check(monthly, [day(2025, 6, 25), day(2025, 8, 23)], "Included leap counts toward interval")
        monthly.includeLeapMonths = false
        try check(monthly, [day(2025, 6, 25)], "Excluded leap does not count toward interval")
        monthly.includeLeapMonths = nil
        monthly.interval = 1
        monthly.lunarDay = 30
        monthly.start = day(2025, 5, 27)
        monthly.endDate = day(2025, 9, 21)
        try check(monthly, [day(2025, 6, 24), day(2025, 7, 24), day(2025, 8, 22), day(2025, 9, 21)], "Short months clamp then restore day 30")
        precondition(monthly.lunarDay == 30)
        monthly.endDate = day(2025, 8, 21)
        try check(monthly, [day(2025, 6, 24), day(2025, 7, 24)], "Clamped day after cutoff is not scheduled")

        var annual = Rule(name: "Annual", kind: .lunar, date: "", lunarMonth: 6, lunarDay: 1,
                          category: "Tests", start: day(2024, 1, 1),
                          endMode: .date, endDate: day(2025, 8, 23), target: "calendar")
        try check(annual, [day(2024, 7, 6), day(2025, 6, 25)], "Ordinary month ignores same-name leap")
        annual.lunarIsLeap = true
        annual.includeLeapMonths = false
        try check(annual, [day(2024, 7, 6), day(2025, 7, 25)], "Annual preference beats monthly setting; ordinary fallback")
        annual.endDate = day(2025, 7, 24)
        try check(annual, [day(2024, 7, 6)], "No fallback when leap exists past cutoff")
        annual.endDate = day(2025, 8, 23)
        annual.lunarDay = 30
        try check(annual, [day(2024, 8, 3), day(2025, 8, 22)], "Annual day 30 clamps in fallback and leap months")
        annual.interval = 2
        annual.lunarDay = 1
        try check(annual, [day(2024, 7, 6)], "Yearly interval still counts eligible years once")
        precondition(annual.lunarIsLeap)
        print("Lunar recurrence: 11 tests passed.")
    }
}
