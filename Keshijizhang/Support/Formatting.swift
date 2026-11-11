import Foundation

enum CN {
    static let locale = Locale(identifier: "zh_CN")

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.firstWeekday = 1
        return calendar
    }()

    private static let integerMoney: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let decimalMoney: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func startOfMonth(_ date: Date) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? startOfDay(date)
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    static func isSameMonth(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, equalTo: rhs, toGranularity: .month)
    }

    static func shiftMonth(_ date: Date, by delta: Int) -> Date {
        let start = startOfMonth(date)
        return calendar.date(byAdding: .month, value: delta, to: start) ?? start
    }

    /// Monday = 1 ... Sunday = 7.
    static func mondayBasedWeekday(_ date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    static func weekdayShort(_ index: Int) -> String {
        let names = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        guard index >= 1, index < names.count else { return "" }
        return names[index]
    }

    static func weekdayFull(_ index: Int) -> String {
        let names = ["", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"]
        guard index >= 1, index < names.count else { return "" }
        return names[index]
    }

    static func monthTitle(_ date: Date) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return "\(year)年\(month)月"
    }

    static func monthShort(_ date: Date) -> String {
        "\(calendar.component(.month, from: date))月"
    }

    static func dayNumber(_ date: Date) -> Int {
        calendar.component(.day, from: date)
    }

    static func fullDayTitle(_ date: Date) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month)月\(day)日 \(weekdayFull(mondayBasedWeekday(date)))"
    }

    static func listDay(_ date: Date) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month)月\(day)日 \(weekdayShort(mondayBasedWeekday(date)))"
    }

    static func monthDay(_ date: Date) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month)月\(day)日"
    }

    static func priceDay(_ date: Date) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(year)年\(month)月\(day)日"
    }

    static func selectionDay(_ date: Date, now: Date = Date()) -> String {
        if isSameDay(date, now) {
            return "\(monthDay(date)) 今天"
        }
        return listDay(date)
    }

    static func hm(_ minutes: Int) -> String {
        let hour = max(0, minutes) / 60
        let minute = max(0, minutes) % 60
        return String(format: "%d:%02d", hour, minute)
    }

    static func minutes(from date: Date) -> Int {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return hour * 60 + minute
    }

    static func date(on day: Date = Date(), minutes: Int) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        parts.second = 0
        return calendar.date(from: parts) ?? day
    }

    static func rangeLabel(_ start: Date, _ end: Date) -> String {
        "\(monthDay(start)) – \(monthDay(end))"
    }

    static func money(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        let isInteger = abs(rounded - rounded.rounded()) < 0.001
        let formatter = isInteger ? integerMoney : decimalMoney
        let body = formatter.string(from: NSNumber(value: rounded)) ?? "0"
        return "¥" + body
    }

    static func parseMoney(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0, value < 1_000_000 else {
            return nil
        }
        return (value * 100).rounded() / 100
    }

    static func daysInMonth(_ month: Date) -> [Date?] {
        let start = startOfMonth(month)
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: start)
        var cells: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        for offset in 0..<count {
            cells.append(calendar.date(byAdding: .day, value: offset, to: start))
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }
}

enum Money {
    static func cents(_ value: Double) -> Int {
        Int((value * 100).rounded())
    }

    static func yuan(_ cents: Int) -> Double {
        Double(cents) / 100
    }

    static func sum(_ values: [Double]) -> Double {
        yuan(values.reduce(0) { $0 + cents($1) })
    }
}

func round2(_ value: Double) -> Double {
    (value * 100).rounded() / 100
}
