import Foundation

/// Date / period window pure functions (Foundation only: Calendar / Date / String)
///
/// Convention: local time zone (`TimeZone.current`) throughout, never UTC.
/// Calendar weeks start on Monday (Calendar.firstWeekday = 2).
public struct DateUtil {

    // MARK: - Internal calendar (Monday-first, local time zone)

    private static var gregorian: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        c.timeZone = TimeZone.current
        return c
    }

    // MARK: - Local date / current time

    /// Local time zone 'YYYY-MM-DD'
    public static func localDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: d)
    }

    /// Local ISO datetime 'YYYY-MM-DD HH:mm:ss'
    public static func isoDateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone.current
        return f.string(from: d)
    }

    /// Current local time
    public static func now() -> Date {
        Date()
    }

    // MARK: - Calendar week / month windows

    /// Calendar week: Mon 00:00:00 through Sun 23:59:59
    public static func weekRange(_ ref: Date) -> (start: Date, end: Date) {
        let c = gregorian
        let comps = c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: ref)
        let start = c.date(from: comps) ?? ref
        let end = c.date(byAdding: .day, value: 7, to: start)?
            .addingTimeInterval(-1) ?? ref
        return (start, end)
    }

    /// Calendar month: 1st 00:00:00 through last day 23:59:59
    public static func monthRange(_ ref: Date) -> (start: Date, end: Date) {
        let c = gregorian
        let comps = c.dateComponents([.year, .month], from: ref)
        let start = c.date(from: comps) ?? ref
        let end = c.date(byAdding: .month, value: 1, to: start)?
            .addingTimeInterval(-1) ?? ref
        return (start, end)
    }

    // MARK: - Period key

    /// Period key: weekly='YYYY-Www' (ISO) / monthly='YYYY-MM'; day-level types (daily / specific date / weekly on a given weekday) return nil
    public static func periodKey(type: TaskType, _ ref: Date) -> String? {
        let c = gregorian
        switch type {
        case .daily, .specificDate, .weeklyDay:
            return nil
        case .weekly:
            let comps = c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: ref)
            guard let y = comps.yearForWeekOfYear, let w = comps.weekOfYear else { return nil }
            return String(format: "%04d-W%02d", y, w)
        case .monthly:
            let comps = c.dateComponents([.year, .month], from: ref)
            guard let y = comps.year, let m = comps.month else { return nil }
            return String(format: "%04d-%02d", y, m)
        }
    }

    // MARK: - Whether a period has ended

    /// Reconstructs the period window's end from the periodKey to check whether it has ended
    private static func rangeForPeriod(type: TaskType, key: String) -> (start: Date, end: Date)? {
        let c = gregorian
        switch type {
        case .weekly:
            let parts = key.split(separator: "-")
            guard parts.count == 2,
                  let y = Int(parts[0]),
                  parts[1].hasPrefix("W"),
                  let w = Int(parts[1].dropFirst()) else { return nil }
            var comps = DateComponents()
            comps.yearForWeekOfYear = y
            comps.weekOfYear = w
            guard let start = c.date(from: comps) else { return nil }
            let end = c.date(byAdding: .day, value: 7, to: start)!.addingTimeInterval(-1)
            return (start, end)
        case .monthly:
            let parts = key.split(separator: "-")
            guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            var comps = DateComponents()
            comps.year = y
            comps.month = m
            guard let start = c.date(from: comps) else { return nil }
            let end = c.date(byAdding: .month, value: 1, to: start)!.addingTimeInterval(-1)
            return (start, end)
        default:
            return nil
        }
    }

    /// Whether the current period window has ended
    public static func isPeriodEnded(type: TaskType, key: String, now: Date) -> Bool {
        guard let (_, end) = rangeForPeriod(type: type, key: key) else { return false }
        return now > end
    }

    // MARK: - Chinese date formatting

    /// '2026-03-17' → '2026-03-17 周二' (Sunday shown as '周日')
    public static func formatCNDate(_ d: Date) -> String {
        let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let wd = gregorian.component(.weekday, from: d) // 1=Sun .. 7=Sat
        let cn = weekdays[(wd - 1 + 7) % 7]
        return localDate(d) + " " + cn
    }

    /// Parses 'YYYY-MM-DD' into a local Date (00:00:00)
    public static func parseLocalDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.date(from: s)
    }

    // MARK: - Weekday (Monday-first, matching the project's week convention)

    /// Weekday index: 1=Monday ... 7=Sunday
    ///
    /// Note `Calendar.component(.weekday)` is 1=Sun..7=Sat; converted here so Monday is 1.
    public static func weekdayISO(_ d: Date) -> Int {
        let wd = gregorian.component(.weekday, from: d) // 1=Sun .. 7=Sat
        return (wd + 5) % 7 + 1
    }

    /// Chinese weekday labels (indexed to match `weekdayISO`: [0] is Monday)
    public static let weekdayLabels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    /// Weekday index → Chinese label; returns an empty string when out of range
    public static func weekdayLabel(_ iso: Int) -> String {
        guard iso >= 1 && iso <= 7 else { return "" }
        return weekdayLabels[iso - 1]
    }

    /// Whether the task is due on `refDate`
    ///
    /// - daily: always true
    /// - weeklyDay: refDate's weekday == configured targetWeekday
    /// - specificDate: refDate == configured targetDate
    /// - weekly / monthly: always true (period tasks are shown per period, not judged due per day)
    public static func isDue(_ task: Task, refDate: Date) -> Bool {
        switch task.type {
        case .daily:
            return true
        case .weeklyDay:
            return task.targetWeekday == weekdayISO(refDate)
        case .specificDate:
            return task.targetDate == localDate(refDate)
        case .weekly, .monthly:
            return true
        }
    }

    // MARK: - Next due / due labels (for the persistent "all tasks" list)

    /// The task's next due local date (that day 00:00:00)
    ///
    /// - daily: today
    /// - weeklyDay: today if the weekday matches, else the next configured weekday (0..7 day scan)
    /// - specificDate: the configured targetDate itself (returned even if past; the caller checks expiry)
    /// - weekly: end of the current calendar week (Sunday)
    /// - monthly: end of the current calendar month
    public static func nextDue(_ task: Task, refDate: Date) -> Date {
        let c = gregorian
        let today = c.startOfDay(for: refDate)
        switch task.type {
        case .daily:
            return today
        case .weeklyDay:
            guard let target = task.targetWeekday, target >= 1, target <= 7 else {
                return today
            }
            if weekdayISO(today) == target { return today }
            for offset in 1...7 {
                let d = c.date(byAdding: .day, value: offset, to: today) ?? today
                if weekdayISO(d) == target { return d }
            }
            return today
        case .specificDate:
            guard let s = task.targetDate, let d = parseLocalDate(s) else { return today }
            return d
        case .weekly:
            return c.startOfDay(for: weekRange(refDate).end)
        case .monthly:
            return c.startOfDay(for: monthRange(refDate).end)
        }
    }

    /// Due label (paired with `nextDue`, used as list subtitle)
    ///
    /// - daily → due today
    /// - weeklyDay matching today → due today; tomorrow → tomorrow; N≥2 days → in N days
    /// - specificDate today → due today; past → expired; tomorrow → tomorrow; N≥2 days → in N days
    /// - weekly → N days left this week (including today)
    /// - monthly → N days left this month (including today)
    public static func dueLabel(_ task: Task, refDate: Date) -> String {
        let c = gregorian
        let today = c.startOfDay(for: refDate)
        let due = nextDue(task, refDate: refDate)
        let daysDiff = c.dateComponents([.day], from: today, to: due).day ?? 0

        switch task.type {
        case .daily:
            return "今天到期"
        case .weeklyDay:
            if daysDiff == 0 { return "今天到期" }
            if daysDiff == 1 { return "明天" }
            return "\(daysDiff) 天后"
        case .specificDate:
            if daysDiff < 0 { return "已过期" }
            if daysDiff == 0 { return "今天到期" }
            if daysDiff == 1 { return "明天" }
            return "\(daysDiff) 天后"
        case .weekly:
            let daysLeft = c.dateComponents(
                [.day], from: today,
                to: c.startOfDay(for: weekRange(refDate).end)
            ).day ?? 0
            return "本周剩 \(daysLeft + 1) 天"
        case .monthly:
            let daysLeft = c.dateComponents(
                [.day], from: today,
                to: c.startOfDay(for: monthRange(refDate).end)
            ).day ?? 0
            return "本月剩 \(daysLeft + 1) 天"
        }
    }

    // MARK: - Calendar grid / paging (for the calendar view)

    /// The 7 days of the calendar week containing the date (Mon ... Sun)
    public static func weekDays(_ ref: Date) -> [Date] {
        let start = weekRange(ref).start
        return (0..<7).compactMap { gregorian.date(byAdding: .day, value: $0, to: start) }
    }

    /// Calendar grid for a year/month: full weeks starting Monday, padded with adjacent-month days
    /// at both ends. Uses 5 or 6 rows (35 or 42 cells) as needed so month switches don't jump much in height.
    public static func monthGrid(year: Int, month: Int) -> [Date] {
        let first = date(year: year, month: month, day: 1)
        let start = weekRange(first).start
        let lead = gregorian.dateComponents([.day], from: start, to: first).day ?? 0
        let count = lead + daysInMonth(year: year, month: month)
        let rows = (count + 6) / 7
        return (0..<(rows * 7)).compactMap { gregorian.date(byAdding: .day, value: $0, to: start) }
    }

    /// Whether `d` falls in the given year/month (used to gray out grid padding days)
    public static func isInMonth(_ d: Date, year: Int, month: Int) -> Bool {
        let c = components(d)
        return c.year == year && c.month == month
    }

    /// Adds/subtracts N calendar months; clamps to month end when shorter (1/31 + 1 month → 2/28 or 2/29)
    public static func addingMonths(_ n: Int, to d: Date) -> Date {
        let c = gregorian
        guard let base = c.date(byAdding: .month, value: n, to: d) else { return d }
        let t = c.dateComponents([.year, .month], from: base)
        guard let y = t.year, let m = t.month else { return base }
        let day = min(c.component(.day, from: d), daysInMonth(year: y, month: m))
        return date(year: y, month: m, day: day)
    }

    /// Adds/subtracts N days
    public static func addingDays(_ n: Int, to d: Date) -> Date {
        gregorian.date(byAdding: .day, value: n, to: d) ?? d
    }

    /// The target weekday's date for a weekly-on-a-given-weekday task within the current calendar
    /// week (Monday start). E.g. weekday=3 (Wednesday) returns this Monday + 2 days.
    public static func occurrenceInWeek(weekday: Int, now: Date) -> Date {
        let start = weekRange(now).start
        return addingDays((weekday - 1), to: start)
    }

    // MARK: - Task end checks

    /// Whether the task has ended (no longer active after the end date). nil endDate means never expires.
    /// The end date itself still counts as active (active on <= end, ended only when > end).
    public static func isEnded(_ task: Task, on date: Date) -> Bool {
        guard let end = task.endDate else { return false }
        return localDate(date) > end
    }

    // MARK: - Year/month/day components (for UI date pickers)

    /// Extracts local year / month / day
    public static func components(_ d: Date) -> (year: Int, month: Int, day: Int) {
        let c = gregorian
        return (c.component(.year, from: d),
                c.component(.month, from: d),
                c.component(.day, from: d))
    }

    /// Days in a given year/month (Feb = 29 in leap years; century years per Gregorian rules)
    public static func daysInMonth(year: Int, month: Int) -> Int {
        let c = gregorian
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let first = c.date(from: comps),
              let range = c.range(of: .day, in: .month, for: first) else {
            return 31
        }
        return range.count
    }

    /// Builds a local Date from year/month/day (that day 00:00:00); invalid combinations fall back to now
    public static func date(year: Int, month: Int, day: Int) -> Date {
        let c = gregorian
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return c.date(from: comps) ?? Date()
    }
}
