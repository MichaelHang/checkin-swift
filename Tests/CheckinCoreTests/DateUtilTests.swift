import XCTest
import CheckinCore

/// DateUtil boundary tests: local dates / calendar weeks (Monday-start, cross-week, cross-year) /
/// calendar months (month end) / periodKey / isPeriodEnded / formatCNDate.
/// The original minimal placeholder tests (testLocalDate / testFormatCNDate) are kept; the rest are QA additions.
final class DateUtilTests: XCTestCase {

    // MARK: - Helpers

    private func date(_ ymd: String) -> Date {
        DateUtil.parseLocalDate(ymd)!
    }

    /// Returns (local date string, hour, minute, second)
    private func parts(_ d: Date) -> (ymd: String, h: Int, m: Int, s: Int) {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.hour, .minute, .second], from: d)
        return (DateUtil.localDate(d), comps.hour ?? -1, comps.minute ?? -1, comps.second ?? -1)
    }

    // MARK: - Original tests (kept)

    func testLocalDate() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fmt.timeZone = TimeZone.current
        let d = fmt.date(from: "2026-03-17 09:30:00")!
        XCTAssertEqual(DateUtil.localDate(d), "2026-03-17")
    }

    func testFormatCNDate() {
        let d = date("2026-03-17") // Tuesday
        XCTAssertEqual(DateUtil.formatCNDate(d), "2026-03-17 周二")
    }

    // MARK: - localDate

    func testLocalDateIgnoresTime() {
        let d = date("2026-12-31")
        let later = d.addingTimeInterval(86399) // 23:59:59 same day
        XCTAssertEqual(DateUtil.localDate(later), "2026-12-31")
    }

    // MARK: - weekRange

    func testWeekRangeMonday() {
        let r = DateUtil.weekRange(date("2026-07-20")) // Monday
        let s = parts(r.start), e = parts(r.end)
        XCTAssertEqual(s.ymd, "2026-07-20")
        XCTAssertTrue((s.h, s.m, s.s) == (0, 0, 0))
        XCTAssertEqual(e.ymd, "2026-07-26") // Sunday
        XCTAssertTrue((e.h, e.m, e.s) == (23, 59, 59))
    }

    func testWeekRangeSunday() {
        let r = DateUtil.weekRange(date("2026-07-26")) // Sunday, must fall in the same week
        let s = parts(r.start), e = parts(r.end)
        XCTAssertEqual(s.ymd, "2026-07-20")
        XCTAssertTrue((s.h, s.m, s.s) == (0, 0, 0))
        XCTAssertEqual(e.ymd, "2026-07-26")
        XCTAssertTrue((e.h, e.m, e.s) == (23, 59, 59))
    }

    func testWeekRangeWednesday() {
        let r = DateUtil.weekRange(date("2026-07-22")) // Wednesday
        let s = parts(r.start)
        XCTAssertEqual(s.ymd, "2026-07-20") // still snaps back to this week's Monday
    }

    func testWeekRangeCrossYear() {
        // Cross-year first week: 2026-01-01 is a Thursday → Monday start should be 2025-12-29, end 2026-01-04
        let r = DateUtil.weekRange(date("2026-01-01"))
        let s = parts(r.start), e = parts(r.end)
        XCTAssertEqual(s.ymd, "2025-12-29")
        XCTAssertTrue((s.h, s.m, s.s) == (0, 0, 0))
        XCTAssertEqual(e.ymd, "2026-01-04")
        XCTAssertTrue((e.h, e.m, e.s) == (23, 59, 59))
    }

    // MARK: - monthRange

    func testMonthRangeJuly() {
        let r = DateUtil.monthRange(date("2026-07-15"))
        let s = parts(r.start), e = parts(r.end)
        XCTAssertEqual(s.ymd, "2026-07-01")
        XCTAssertTrue((s.h, s.m, s.s) == (0, 0, 0))
        XCTAssertEqual(e.ymd, "2026-07-31")
        XCTAssertTrue((e.h, e.m, e.s) == (23, 59, 59))
    }

    func testMonthRangeJanuaryEnd() {
        let r = DateUtil.monthRange(date("2026-01-31"))
        let s = parts(r.start), e = parts(r.end)
        XCTAssertEqual(s.ymd, "2026-01-01")
        XCTAssertTrue((s.h, s.m, s.s) == (0, 0, 0))
        XCTAssertEqual(e.ymd, "2026-01-31")
        XCTAssertTrue((e.h, e.m, e.s) == (23, 59, 59))
    }

    func testMonthRangeLeapFebruary() {
        let r = DateUtil.monthRange(date("2024-02-10")) // leap-year February
        let e = parts(r.end)
        XCTAssertEqual(e.ymd, "2024-02-29")
        XCTAssertTrue((e.h, e.m, e.s) == (23, 59, 59))
    }

    // MARK: - periodKey

    func testPeriodKeyWeeklyNewYear() {
        XCTAssertEqual(DateUtil.periodKey(type: .weekly, date("2026-01-01")), "2026-W01")
    }

    func testPeriodKeyWeeklyMidYear() {
        XCTAssertEqual(DateUtil.periodKey(type: .weekly, date("2026-07-20")), "2026-W30")
    }

    func testPeriodKeyMonthly() {
        XCTAssertEqual(DateUtil.periodKey(type: .monthly, date("2026-07-20")), "2026-07")
    }

    func testPeriodKeyDailyNil() {
        XCTAssertNil(DateUtil.periodKey(type: .daily, date("2026-07-20")))
    }

    func testPeriodKeySpecificDateNil() {
        XCTAssertNil(DateUtil.periodKey(type: .specificDate, date("2026-07-20")))
    }

    // MARK: - isPeriodEnded

    func testIsPeriodEndedWithinWeek() {
        // 2026-W01 ends 2026-01-04 23:59:59; now=2026-01-03 is still inside the window
        XCTAssertFalse(DateUtil.isPeriodEnded(type: .weekly, key: "2026-W01", now: date("2026-01-03")))
    }

    func testIsPeriodEndedAfterWeek() {
        // now=2026-01-05 is past the 2026-W01 window
        XCTAssertTrue(DateUtil.isPeriodEnded(type: .weekly, key: "2026-W01", now: date("2026-01-05")))
    }

    func testIsPeriodEndedWithinMonth() {
        XCTAssertFalse(DateUtil.isPeriodEnded(type: .monthly, key: "2026-07", now: date("2026-07-15")))
    }

    func testIsPeriodEndedAfterMonth() {
        XCTAssertTrue(DateUtil.isPeriodEnded(type: .monthly, key: "2026-07", now: date("2026-08-01")))
    }

    func testIsPeriodEndedDailyAlwaysFalse() {
        // daily / specificDate have no period window; always returns false
        XCTAssertFalse(DateUtil.isPeriodEnded(type: .daily, key: "2026-07-20", now: date("2099-01-01")))
        XCTAssertFalse(DateUtil.isPeriodEnded(type: .specificDate, key: "x", now: date("2099-01-01")))
    }

    // MARK: - formatCNDate weekday

    func testFormatCNDateSunday() {
        XCTAssertEqual(DateUtil.formatCNDate(date("2026-01-04")), "2026-01-04 周日")
    }

    func testFormatCNDateSaturday() {
        XCTAssertEqual(DateUtil.formatCNDate(date("2026-01-03")), "2026-01-03 周六")
    }

    func testFormatCNDateMonday() {
        XCTAssertEqual(DateUtil.formatCNDate(date("2026-01-05")), "2026-01-05 周一")
    }

    // MARK: - components

    func testComponents() {
        let c = DateUtil.components(date("2026-03-17"))
        XCTAssertEqual(c.year, 2026)
        XCTAssertEqual(c.month, 3)
        XCTAssertEqual(c.day, 17)
    }

    func testComponentsIgnoresTime() {
        // Year/month/day extracted at any time of day must be identical
        let base = date("2026-03-17")
        let c = DateUtil.components(base.addingTimeInterval(86399))
        XCTAssertTrue((c.year, c.month, c.day) == (2026, 3, 17))
    }

    // MARK: - daysInMonth

    func testDaysInMonthCommonYear() {
        XCTAssertEqual(DateUtil.daysInMonth(year: 2026, month: 1), 31)
        XCTAssertEqual(DateUtil.daysInMonth(year: 2026, month: 2), 28)
        XCTAssertEqual(DateUtil.daysInMonth(year: 2026, month: 3), 31)
        XCTAssertEqual(DateUtil.daysInMonth(year: 2026, month: 4), 30)
        XCTAssertEqual(DateUtil.daysInMonth(year: 2026, month: 6), 30)
        XCTAssertEqual(DateUtil.daysInMonth(year: 2026, month: 9), 30)
        XCTAssertEqual(DateUtil.daysInMonth(year: 2026, month: 11), 30)
        XCTAssertEqual(DateUtil.daysInMonth(year: 2026, month: 12), 31)
    }

    func testDaysInMonthLeapFebruary() {
        XCTAssertEqual(DateUtil.daysInMonth(year: 2024, month: 2), 29)
        XCTAssertEqual(DateUtil.daysInMonth(year: 2028, month: 2), 29)
        XCTAssertEqual(DateUtil.daysInMonth(year: 2026, month: 2), 28)
    }

    func testDaysInMonthCenturyRule() {
        // Century years: leap only when divisible by 400
        XCTAssertEqual(DateUtil.daysInMonth(year: 1900, month: 2), 28)
        XCTAssertEqual(DateUtil.daysInMonth(year: 2000, month: 2), 29)
        XCTAssertEqual(DateUtil.daysInMonth(year: 2100, month: 2), 28)
    }

    // MARK: - date(year:month:day:)

    func testDateFromComponentsRoundTrip() {
        let d = DateUtil.date(year: 2026, month: 3, day: 17)
        XCTAssertEqual(DateUtil.localDate(d), "2026-03-17")
        let p = parts(d)
        XCTAssertTrue((p.h, p.m, p.s) == (0, 0, 0)) // 00:00:00 same day
    }

    func testDateFromComponentsLastDayEveryMonth() {
        // The last day of every month round-trips unchanged (leap and non-leap February included)
        for m in 1...12 {
            let n = DateUtil.daysInMonth(year: 2024, month: m)
            let c = DateUtil.components(DateUtil.date(year: 2024, month: m, day: n))
            XCTAssertEqual(c.year, 2024)
            XCTAssertEqual(c.month, m)
            XCTAssertEqual(c.day, n)
        }
    }

    func testDateFromComponentsLeapLastDay() {
        let c = DateUtil.components(DateUtil.date(year: 2024, month: 2, day: 29))
        XCTAssertTrue((c.year, c.month, c.day) == (2024, 2, 29))
    }

    // MARK: - weekdayISO / weekdayLabel

    func testWeekdayISOAllDays() {
        // 2026-07-20 Monday ... 2026-07-26 Sunday
        XCTAssertEqual(DateUtil.weekdayISO(date("2026-07-20")), 1)
        XCTAssertEqual(DateUtil.weekdayISO(date("2026-07-21")), 2)
        XCTAssertEqual(DateUtil.weekdayISO(date("2026-07-22")), 3)
        XCTAssertEqual(DateUtil.weekdayISO(date("2026-07-23")), 4)
        XCTAssertEqual(DateUtil.weekdayISO(date("2026-07-24")), 5)
        XCTAssertEqual(DateUtil.weekdayISO(date("2026-07-25")), 6)
        XCTAssertEqual(DateUtil.weekdayISO(date("2026-07-26")), 7)
    }

    func testWeekdayISOCrossYear() {
        // 2026-01-04 Sunday (same weekday baseline verified via formatCNDate)
        XCTAssertEqual(DateUtil.weekdayISO(date("2026-01-04")), 7)
        XCTAssertEqual(DateUtil.weekdayISO(date("2026-01-05")), 1) // Monday
    }

    func testWeekdayLabel() {
        XCTAssertEqual(DateUtil.weekdayLabel(1), "周一")
        XCTAssertEqual(DateUtil.weekdayLabel(4), "周四")
        XCTAssertEqual(DateUtil.weekdayLabel(7), "周日")
        XCTAssertEqual(DateUtil.weekdayLabel(0), "")
        XCTAssertEqual(DateUtil.weekdayLabel(-1), "")
        XCTAssertEqual(DateUtil.weekdayLabel(8), "")
    }

    // MARK: - isDue

    private func makeTask(_ type: TaskType, targetDate: String? = nil,
                          targetWeekday: Int? = nil) -> Task {
        Task(id: IdUtil.genId(), name: "t", type: type, acceptanceRequired: false,
             targetDate: targetDate, targetWeekday: targetWeekday,
             createdAt: DateUtil.isoDateTime(DateUtil.now()))
    }

    func testIsDueDailyAlways() {
        let t = makeTask(.daily)
        XCTAssertTrue(DateUtil.isDue(t, refDate: date("2026-07-20")))
        XCTAssertTrue(DateUtil.isDue(t, refDate: date("2026-01-01")))
    }

    func testIsDueWeeklyDayMatchesEveryWeek() {
        let t = makeTask(.weeklyDay, targetWeekday: 1) // every Monday
        XCTAssertTrue(DateUtil.isDue(t, refDate: date("2026-07-20")))   // Monday
        XCTAssertTrue(DateUtil.isDue(t, refDate: date("2026-07-27")))   // next Monday
        XCTAssertFalse(DateUtil.isDue(t, refDate: date("2026-07-21")))  // Tuesday
        XCTAssertFalse(DateUtil.isDue(t, refDate: date("2026-07-26")))  // Sunday
    }

    func testIsDueWeeklyDaySunday() {
        let t = makeTask(.weeklyDay, targetWeekday: 7) // every Sunday
        XCTAssertTrue(DateUtil.isDue(t, refDate: date("2026-07-26")))
        XCTAssertFalse(DateUtil.isDue(t, refDate: date("2026-07-20")))
    }

    func testIsDueWeeklyDayMissingConfigNeverDue() {
        // Weekday not configured → never due (defensive: never silently passes)
        let t = makeTask(.weeklyDay)
        XCTAssertFalse(DateUtil.isDue(t, refDate: date("2026-07-20")))
    }

    func testIsDueSpecificDate() {
        let t = makeTask(.specificDate, targetDate: "2026-07-20")
        XCTAssertTrue(DateUtil.isDue(t, refDate: date("2026-07-20")))
        XCTAssertFalse(DateUtil.isDue(t, refDate: date("2026-07-19")))
        XCTAssertFalse(DateUtil.isDue(t, refDate: date("2026-07-21")))
    }

    func testIsDuePeriodTypesAlways() {
        XCTAssertTrue(DateUtil.isDue(makeTask(.weekly), refDate: date("2026-07-20")))
        XCTAssertTrue(DateUtil.isDue(makeTask(.monthly), refDate: date("2026-01-31")))
    }

    // MARK: - periodKey weeklyDay

    func testPeriodKeyWeeklyDayNil() {
        // weeklyDay is day-level; produces no period key
        XCTAssertNil(DateUtil.periodKey(type: .weeklyDay, date("2026-07-20")))
    }

    // MARK: - nextDue

    /// Fixed baseline: 2026-09-07 is a **Monday** and 2026-09-13 a **Sunday**,
    /// consistent with the weekday alignment verified in testWeekdayISOAllDays.
    private static let baseMon = "2026-09-07"

    func testNextDueDailyAlwaysToday() {
        let t = makeTask(.daily)
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date("2026-09-07"))), "2026-09-07")
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date("2026-01-01"))), "2026-01-01")
    }

    func testNextDueWeeklyDayMatchesToday() {
        let t = makeTask(.weeklyDay, targetWeekday: 1) // every Monday
        // 2026-09-07 Monday → due today
        let d = DateUtil.nextDue(t, refDate: date(DateUtilTests.baseMon))
        XCTAssertEqual(DateUtil.localDate(d), DateUtilTests.baseMon)
        let p = parts(d)
        XCTAssertTrue((p.h, p.m, p.s) == (0, 0, 0))
    }

    func testNextDueWeeklyDayTomorrow() {
        let t = makeTask(.weeklyDay, targetWeekday: 2) // every Tuesday
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date(DateUtilTests.baseMon))),
                       "2026-09-08")
    }

    func testNextDueWeeklyDayLaterThisWeek() {
        let t = makeTask(.weeklyDay, targetWeekday: 4) // every Thursday
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date(DateUtilTests.baseMon))),
                       "2026-09-10")
    }

    func testNextDueWeeklyDaySundayEndOfWeek() {
        let t = makeTask(.weeklyDay, targetWeekday: 7) // every Sunday
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date(DateUtilTests.baseMon))),
                       "2026-09-13")
    }

    func testNextDueWeeklyDayCrossWeekendWrap() {
        // 2026-09-12 Saturday → target Wednesday 2026-09-16
        let t = makeTask(.weeklyDay, targetWeekday: 3)
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date("2026-09-12"))),
                       "2026-09-16")
    }

    func testNextDueWeeklyDayCrossYear() {
        // 2026-01-01 is a Thursday; target Monday → 2026-01-05
        let t = makeTask(.weeklyDay, targetWeekday: 1)
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date("2026-01-01"))),
                       "2026-01-05")
    }

    func testNextDueWeeklyDayMissingConfigFallsBackToToday() {
        // Weekday not configured → falls back to today (defensive: never returns an arbitrary date)
        let t = makeTask(.weeklyDay)
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date(DateUtilTests.baseMon))),
                       DateUtilTests.baseMon)
    }

    func testNextDueSpecificDateReturnsTargetAsIs() {
        // future → returned as-is
        let t = makeTask(.specificDate, targetDate: "2026-09-15")
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date(DateUtilTests.baseMon))),
                       "2026-09-15")
        // expired → also returned as-is (the caller decides expiry)
        let past = makeTask(.specificDate, targetDate: "2026-01-01")
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(past, refDate: date(DateUtilTests.baseMon))),
                       "2026-01-01")
    }

    func testNextDueWeeklyWeekEndSunday() {
        let t = makeTask(.weekly)
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date(DateUtilTests.baseMon))),
                       "2026-09-13")
        // On the period's end day → still this week's Sunday
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date("2026-09-13"))),
                       "2026-09-13")
    }

    func testNextDueWeeklyCrossYearWeek() {
        // 2026-01-01 Thursday → this week's Sunday 2026-01-04 (cross-year first week)
        let t = makeTask(.weekly)
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date("2026-01-01"))),
                       "2026-01-04")
    }

    func testNextDueMonthlyMonthEnd() {
        let t = makeTask(.monthly)
        // September has 30 days
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date("2026-09-15"))),
                       "2026-09-30")
        // On the month's last day → still month end
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date("2026-09-30"))),
                       "2026-09-30")
    }

    func testNextDueMonthlyFebruaryLeap() {
        let t = makeTask(.monthly)
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date("2024-02-10"))),
                       "2024-02-29") // leap year
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date("2026-02-10"))),
                       "2026-02-28") // non-leap year
    }

    // MARK: - dueLabel

    func testDueLabelDaily() {
        let t = makeTask(.daily)
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date(DateUtilTests.baseMon)), "今天到期")
    }

    func testDueLabelWeeklyDayToday() {
        let t = makeTask(.weeklyDay, targetWeekday: 1)
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date(DateUtilTests.baseMon)), "今天到期")
    }

    func testDueLabelWeeklyDayTomorrow() {
        let t = makeTask(.weeklyDay, targetWeekday: 2)
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date(DateUtilTests.baseMon)), "明天")
    }

    func testDueLabelWeeklyDayNDaysAhead() {
        // Monday → Thursday = 3 days
        let t = makeTask(.weeklyDay, targetWeekday: 4)
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date(DateUtilTests.baseMon)), "3 天后")
        // Monday → Sunday = 6 days
        let sunday = makeTask(.weeklyDay, targetWeekday: 7)
        XCTAssertEqual(DateUtil.dueLabel(sunday, refDate: date(DateUtilTests.baseMon)), "6 天后")
    }

    func testDueLabelSpecificDateToday() {
        let t = makeTask(.specificDate, targetDate: DateUtilTests.baseMon)
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date(DateUtilTests.baseMon)), "今天到期")
    }

    func testDueLabelSpecificDateOverdue() {
        let t = makeTask(.specificDate, targetDate: "2026-09-06")
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date(DateUtilTests.baseMon)), "已过期")
        // Earlier historical dates are likewise treated as expired
        let farPast = makeTask(.specificDate, targetDate: "2020-01-01")
        XCTAssertEqual(DateUtil.dueLabel(farPast, refDate: date(DateUtilTests.baseMon)), "已过期")
    }

    func testDueLabelSpecificDateTomorrow() {
        let t = makeTask(.specificDate, targetDate: "2026-09-08")
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date(DateUtilTests.baseMon)), "明天")
    }

    func testDueLabelSpecificDateNDaysAhead() {
        // 3 days from today
        let t = makeTask(.specificDate, targetDate: "2026-09-10")
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date(DateUtilTests.baseMon)), "3 天后")
    }

    func testDueLabelWeeklyRemainingDays() {
        let t = makeTask(.weekly)
        // Monday: 7 days left this week (today included)
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date(DateUtilTests.baseMon)), "本周剩 7 天")
        // Wednesday: 5 days left this week
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date("2026-09-09")), "本周剩 5 天")
        // Sunday: 1 day left this week
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date("2026-09-13")), "本周剩 1 天")
    }

    func testDueLabelWeeklyCrossYearWeek() {
        // Cross-year first week: 2026-01-01 Thursday → 4 days left this week (Thu/Fri/Sat/Sun)
        let t = makeTask(.weekly)
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date("2026-01-01")), "本周剩 4 天")
    }

    func testDueLabelMonthlyRemainingDays() {
        let t = makeTask(.monthly)
        // 2026-09-15: 16 days left this month (today included)
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date("2026-09-15")), "本月剩 16 天")
        // 2026-09-30: 1 day left this month
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date("2026-09-30")), "本月剩 1 天")
        // 2026-09-01: 30 days left this month
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date("2026-09-01")), "本月剩 30 天")
    }

    func testDueLabelMonthlyFebruaryLeap() {
        let t = makeTask(.monthly)
        // Leap-year February: 15 days left (2/15 included)
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date("2024-02-15")), "本月剩 15 天")
        // Non-leap February 28: 1 day left
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date("2026-02-28")), "本月剩 1 天")
    }

    func testDueLabelMonthlyCrossYearBoundary() {
        // December's last day → 1 day left this month
        let t = makeTask(.monthly)
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date("2026-12-31")), "本月剩 1 天")
    }

    // MARK: - QA additions: nextDue / dueLabel real-world boundaries

    /// A Sunday refDate scans to **next Monday**: offset=1 hits, crossing the ISO week boundary.
    /// 2026-09-13 Sunday → 2026-09-14 Monday
    func testNextDueWeeklyDaySundayToNextMonday() {
        let t = makeTask(.weeklyDay, targetWeekday: 1) // every Monday
        let sunday = date("2026-09-13")
        let d = DateUtil.nextDue(t, refDate: sunday)
        XCTAssertEqual(DateUtil.localDate(d), "2026-09-14")
        XCTAssertEqual(DateUtil.weekdayISO(d), 1)
    }

    /// Sunday refDate with a Sunday target → due today (does not scan next week)
    func testNextDueWeeklyDaySundayTargetSundayReturnsToday() {
        let t = makeTask(.weeklyDay, targetWeekday: 7) // every Sunday
        let sunday = date("2026-09-13")
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: sunday)),
                       "2026-09-13")
    }

    /// dueLabel for Sunday → next Monday should be "明天" (tomorrow; crosses weeks but only 1 day apart)
    func testDueLabelWeeklyDaySundayToNextMonday() {
        let t = makeTask(.weeklyDay, targetWeekday: 1)
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date("2026-09-13")), "明天")
    }

    /// dueLabel for Sunday → next Wednesday should be "3 天后" (3 days ahead)
    func testDueLabelWeeklyDaySundayToNextWednesday() {
        let t = makeTask(.weeklyDay, targetWeekday: 3)
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date("2026-09-13")), "3 天后")
    }

    /// Out-of-range targetWeekday (0 / 8 / -1) falls back to today (defensive path; never returns an arbitrary date)
    func testNextDueWeeklyDayInvalidTargetFallsBackToToday() {
        for invalid in [0, 8, -1, 100] {
            let t = makeTask(.weeklyDay, targetWeekday: invalid)
            XCTAssertEqual(
                DateUtil.localDate(DateUtil.nextDue(t, refDate: date(DateUtilTests.baseMon))),
                DateUtilTests.baseMon,
                "targetWeekday=\(invalid) 应回退到今天"
            )
        }
    }

    /// With no valid weeklyDay config, dueLabel shows "今天到期" (a side effect of nextDue falling back to today).
    /// Records current behavior; if it later hides this or shows "未配置", update this test accordingly.
    func testDueLabelWeeklyDayMissingConfigShowsToday() {
        let t = makeTask(.weeklyDay) // targetWeekday = nil
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date(DateUtilTests.baseMon)), "今天到期")
    }

    /// specificDate target exactly at month end: returned as-is, no offset across the month boundary
    func testNextDueSpecificDateAtMonthEnd() {
        let t = makeTask(.specificDate, targetDate: "2026-09-30")
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date("2026-09-15"))),
                       "2026-09-30")
    }

    /// specificDate target exactly at year end: returned as-is
    func testNextDueSpecificDateAtYearEnd() {
        let t = makeTask(.specificDate, targetDate: "2026-12-31")
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date("2026-12-01"))),
                       "2026-12-31")
    }

    /// specificDate target exactly on leap day 2/29: returned as-is
    func testNextDueSpecificDateAtLeapDay() {
        let t = makeTask(.specificDate, targetDate: "2024-02-29")
        XCTAssertEqual(DateUtil.localDate(DateUtil.nextDue(t, refDate: date("2024-02-01"))),
                       "2024-02-29")
    }

    /// dueLabel boundary for a specificDate target exactly tomorrow (daysDiff == 1)
    func testDueLabelSpecificDateTomorrowFromMonthStart() {
        // 2026-09-01 → 2026-09-02 = 1 day
        let t = makeTask(.specificDate, targetDate: "2026-09-02")
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date("2026-09-01")), "明天")
    }

    /// dueLabel boundary for a specificDate target exactly two days ahead (daysDiff == 2)
    func testDueLabelSpecificDateTwoDaysAhead() {
        let t = makeTask(.specificDate, targetDate: "2026-09-09")
        XCTAssertEqual(DateUtil.dueLabel(t, refDate: date("2026-09-07")), "2 天后")
    }

    // MARK: - Calendar grid / paging (used by the calendar view)

    func testWeekDaysSpansMondayToSunday() {
        let days = DateUtil.weekDays(date("2026-09-07")) // Monday
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(DateUtil.localDate(days[0]), "2026-09-07")
        XCTAssertEqual(DateUtil.localDate(days[6]), "2026-09-13")
    }

    func testWeekDaysAnchorsToWeekStartFromMidWeek() {
        // A Thursday anchor must still return the 7 days starting this week's Monday
        let days = DateUtil.weekDays(date("2026-09-10"))
        XCTAssertEqual(DateUtil.localDate(days[0]), "2026-09-07")
        XCTAssertEqual(DateUtil.localDate(days[6]), "2026-09-13")
    }

    func testMonthGridPadsToFullWeeks() {
        let grid = DateUtil.monthGrid(year: 2026, month: 9)
        XCTAssertEqual(grid.count % 7, 0, "网格必须是整周")
        XCTAssertEqual(DateUtil.localDate(grid[0]), "2026-08-31", "9/1 是周二，网格应从上个月周一开始")
        XCTAssertEqual(DateUtil.localDate(grid[grid.count - 1]), "2026-10-04")
        for d in 1...30 {
            let s = String(format: "2026-09-%02d", d)
            XCTAssertTrue(grid.contains { DateUtil.localDate($0) == s }, "\(s) 应在网格内")
        }
    }

    func testMonthGridLeapFebruary() {
        let grid = DateUtil.monthGrid(year: 2024, month: 2)
        XCTAssertEqual(grid.count % 7, 0)
        XCTAssertEqual(DateUtil.localDate(grid[0]), "2024-01-29", "2024/2/1 是周四，网格从上个月周一开始")
        XCTAssertTrue(grid.contains { DateUtil.localDate($0) == "2024-02-29" }, "闰日必须在网格内")
    }

    func testIsInMonth() {
        XCTAssertTrue(DateUtil.isInMonth(date("2026-09-15"), year: 2026, month: 9))
        XCTAssertFalse(DateUtil.isInMonth(date("2026-08-31"), year: 2026, month: 9), "上个月的填充日应判否")
        XCTAssertFalse(DateUtil.isInMonth(date("2026-09-01"), year: 2025, month: 9), "同月不同年应判否")
    }

    func testAddingMonthsClampsToMonthEnd() {
        XCTAssertEqual(DateUtil.localDate(DateUtil.addingMonths(1, to: date("2026-01-31"))), "2026-02-28")
        XCTAssertEqual(DateUtil.localDate(DateUtil.addingMonths(1, to: date("2024-01-31"))), "2024-02-29")
        XCTAssertEqual(DateUtil.localDate(DateUtil.addingMonths(-1, to: date("2026-03-31"))), "2026-02-28")
    }

    func testAddingDays() {
        XCTAssertEqual(DateUtil.localDate(DateUtil.addingDays(7, to: date("2026-09-07"))), "2026-09-14")
        XCTAssertEqual(DateUtil.localDate(DateUtil.addingDays(-7, to: date("2026-09-07"))), "2026-08-31")
    }

    // MARK: - occurrenceInWeek

    func testOccurrenceInWeek() {
        // 2026-09-07 is a Monday (aligned with testWeekdayISOAllDays / baseMon)
        let now = date("2026-09-07")
        XCTAssertEqual(DateUtil.localDate(DateUtil.occurrenceInWeek(weekday: 1, now: now)), "2026-09-07")
        XCTAssertEqual(DateUtil.localDate(DateUtil.occurrenceInWeek(weekday: 3, now: now)), "2026-09-09")
        XCTAssertEqual(DateUtil.localDate(DateUtil.occurrenceInWeek(weekday: 7, now: now)), "2026-09-13")
    }

    // MARK: - isEnded

    func testIsEndedWithEndDate() {
        let ended = Task(id: "t", name: "t", type: .weekly, acceptanceRequired: false,
                         targetCount: 1, endDate: "2026-09-10", createdAt: "2026-09-01 00:00:00")
        XCTAssertFalse(DateUtil.isEnded(ended, on: date("2026-09-09")))
        XCTAssertFalse(DateUtil.isEnded(ended, on: date("2026-09-10")), "结束日当天仍活跃")
        XCTAssertTrue(DateUtil.isEnded(ended, on: date("2026-09-11")))
    }

    func testIsEndedWithoutEndDateNeverEnds() {
        let forever = Task(id: "t", name: "t", type: .weekly, acceptanceRequired: false,
                          targetCount: 1, createdAt: "2026-09-01 00:00:00")
        XCTAssertFalse(DateUtil.isEnded(forever, on: date("2099-12-31")))
        XCTAssertFalse(DateUtil.isEnded(forever, on: date("2026-09-10")))
    }
}
