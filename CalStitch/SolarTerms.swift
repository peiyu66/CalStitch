import Foundation

/// Civil dates at 120° E (UTC+8), extracted from the Taipei Astronomical Museum's
/// 2021–2030 simplified astronomical almanac. The table stores only day-of-month;
/// the terms are ordered from January through December, two per month.
enum SolarTerms {
    static let attribution = "節氣日期來源：臺北市立天文科學教育館《2021–2030 簡易曆象表》"
    static let sourceURL = URL(string: "https://tam.gov.taipei/News_Content.aspx?n=2D5F18609004C0CE&s=AC19298B0509F078&sms=3AABB000A3E78431")!
    static let supportedYears = 2026...2030
    static let names = [
        "小寒", "大寒", "立春", "雨水", "驚蟄", "春分", "清明", "穀雨",
        "立夏", "小滿", "芒種", "夏至", "小暑", "大暑", "立秋", "處暑",
        "白露", "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至"
    ]

    // Source copyright permissions: https://tam.gov.taipei/News_Content.aspx?n=949BF761EF9FC23D&s=2090B6F3C89E4D89
    // The date-only transformation does not imply endorsement by the museum.
    private static let daysByYear: [Int: [Int]] = [
        2026: [5, 20, 4, 18, 5, 20, 5, 20, 5, 21, 5, 21, 7, 23, 7, 23, 7, 23, 8, 23, 7, 22, 7, 22],
        2027: [5, 20, 4, 19, 6, 21, 5, 20, 6, 21, 6, 21, 7, 23, 8, 23, 8, 23, 8, 23, 7, 22, 7, 22],
        2028: [6, 20, 4, 19, 5, 20, 4, 19, 5, 20, 5, 21, 6, 22, 7, 22, 7, 22, 8, 23, 7, 22, 6, 21],
        2029: [5, 20, 3, 18, 5, 20, 4, 20, 5, 21, 5, 21, 7, 22, 7, 23, 7, 23, 8, 23, 7, 22, 7, 21],
        2030: [5, 20, 4, 18, 5, 20, 5, 20, 5, 21, 5, 21, 7, 23, 7, 23, 7, 23, 8, 23, 7, 22, 7, 22]
    ]

    static func date(for name: String, year: Int, calendar: Calendar) -> Date? {
        guard calendar.identifier == .gregorian,
              let index = names.firstIndex(of: name),
              let days = daysByYear[year] else { return nil }
        return calendar.date(from: DateComponents(year: year, month: index / 2 + 1, day: days[index]))
    }
}
