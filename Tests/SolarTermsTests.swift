import Foundation

// swiftc CalStitch/SolarTerms.swift Tests/SolarTermsTests.swift -o /tmp/calstitch-solar-tests
// /tmp/calstitch-solar-tests
@main
struct SolarTermsTests {
    static func main() {
        var taipei = Calendar(identifier: .gregorian)
        taipei.timeZone = TimeZone(identifier: "Asia/Taipei")!

        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
        }

        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            taipei.date(from: DateComponents(year: year, month: month, day: day))!
        }

        check(SolarTerms.supportedYears == 1901...2100, "Unexpected coverage")
        check(SolarTerms.names.count == 24 && Set(SolarTerms.names).count == 24, "Unexpected term names")
        var checkedRecords = 0
        for year in SolarTerms.supportedYears {
            var previous: Date?
            for (offset, term) in SolarTerms.names.enumerated() {
                guard let value = SolarTerms.date(for: term, year: year, calendar: taipei) else {
                    fatalError("Missing \(year) \(term)")
                }
                let parts = taipei.dateComponents([.year, .month, .day], from: value)
                check(parts.year == year && parts.month == offset / 2 + 1, "Wrong month for \(year) \(term)")
                if let previous {
                    check(value > previous, "Incorrect order for \(year) \(term)")
                }
                previous = value
                checkedRecords += 1
            }
        }
        check(checkedRecords == 4_800, "Expected 4,800 records")

        // Dates from the DE440s calculation audit (including two endpoints and one
        // historical IANA Taipei offset that differs from fixed UTC+08).
        for (term, year, month, day) in [
            ("小寒", 1901, 1, 6), ("冬至", 1901, 12, 22),
            ("立夏", 1944, 5, 6), ("冬至", 2031, 12, 22), ("冬至", 2100, 12, 22)
        ] {
            check(SolarTerms.date(for: term, year: year, calendar: taipei) == date(year, month, day),
                  "Incorrect date for \(year) \(term)")
        }
        check(SolarTerms.date(for: "小寒", year: 1900, calendar: taipei) == nil, "Accepted a year before coverage")
        check(SolarTerms.date(for: "冬至", year: 2101, calendar: taipei) == nil, "Accepted a year after coverage")
        check(SolarTerms.date(for: "未知", year: 2031, calendar: taipei) == nil, "Accepted an unknown term")
        check(SolarTerms.date(for: "冬至", year: 2031, calendar: Calendar(identifier: .chinese)) == nil,
              "Accepted a non-Gregorian calendar")
        print("SolarTerms: verified 4,800 records, exact dates, and coverage boundaries.")
    }
}
