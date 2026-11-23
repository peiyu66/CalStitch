import Foundation

enum L10n {
    static var isEnglish: Bool {
        #if FORCE_ENGLISH_PREVIEW
        true
        #else
        (Bundle.main.preferredLocalizations.first ?? "zh-Hant").lowercased().hasPrefix("en")
        #endif
    }

    static func text(_ chinese: @autoclosure () -> String, _ english: @autoclosure () -> String) -> String {
        isEnglish ? english() : chinese()
    }

    static var locale: Locale {
        guard isEnglish else { return Locale(identifier: "zh_TW@hours=h12") }
        let device = Locale.autoupdatingCurrent
        var components = Locale.Components(languageCode: "en", languageRegion: device.region ?? "US")
        components.hourCycle = device.hourCycle
        return Locale(components: components)
    }

    static func date(_ day: Date, timeZone: TimeZone, includesWeekday: Bool) -> String {
        if !isEnglish {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let p = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
            let civil = "\(p.year ?? 0)年\(p.month ?? 0)月\(p.day ?? 0)日"
            let names = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
            guard includesWeekday, let weekday = p.weekday, (1...7).contains(weekday) else { return civil }
            return "\(civil)（\(names[weekday - 1])）"
        }
        return format(day, timeZone: timeZone, template: includesWeekday ? "EEEEyMMMd" : "yMMMd")
    }

    static func time(_ time: Date, timeZone: TimeZone) -> String {
        if !isEnglish {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let p = calendar.dateComponents([.hour, .minute], from: time)
            let hour = p.hour ?? 0
            return "\(hour < 12 ? "上午" : "下午") \(String(format: "%02d:%02d", hour % 12 == 0 ? 12 : hour % 12, p.minute ?? 0))"
        }
        return format(time, timeZone: timeZone, template: "jm")
    }

    private static func format(_ date: Date, timeZone: TimeZone, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    static func category(_ stored: String) -> String {
        guard isEnglish else { return stored }
        return ["生日": "Birthdays", "節氣": "Solar Terms", "祭祀": "Rites",
                "節日": "Holidays", "家人": "Family", "生活": "Life",
                "生日與紀念日": "Birthdays and Anniversaries"][stored] ?? stored
    }

    static func ordinal(_ number: Int) -> String {
        let suffix: String
        if (11...13).contains(number % 100) { suffix = "th" }
        else { suffix = [1: "st", 2: "nd", 3: "rd"][number % 10] ?? "th" }
        return "\(number)\(suffix)"
    }
}
