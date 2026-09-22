import XCTest
import CheckinCore

/// StatsUtil boundary tests: this week's expected count (all types / future days excluded / created
/// day / end day), completion and pass rates (including nil branches), per-task weakest-first
/// sorting, fixed 7 weekday items, last-4-week trend ordering, achieved-week streak start rules,
/// insufficient-sample threshold.
///
/// Baseline: 2026-09-07 is a Monday, this week = 2026-09-07 ~ 2026-09-13;
/// ref = 2026-09-09 (Wednesday) to verify "future days are not counted as expected".
final class StatsUtilTests: XCTestCase {

    // MARK: - Helpers

    private func date(_ ymd: String) -> Date { DateUtil.parseLocalDate(ymd)! }

    /// ref = 2026-09-09 (Wednesday); this week = 09-07 (Mon) ~ 09-13 (Sun)
    private let ref = DateUtil.parseLocalDate("2026-09-09")!

    private func makeTask(id: String = "t1",
                          name: String = "x",
                          type: TaskType,
                          targetDate: String? = nil,
                          targetWeekday: Int? = nil,
                          targetCount: Int? = nil,
                          endDate: String? = nil,
                          createdAt: String = "2026-09-01 00:00:00") -> Task {
        Task(id: id, name: name, type: type, acceptanceRequired: false,
             targetDate: targetDate, targetWeekday: targetWeekday,
             targetCount: targetCount, endDate: endDate, createdAt: createdAt)
    }

    private func record(taskId: String,
                        _ dayKey: String,
                        _ status: TaskStatus,
                        counted: Bool = true) -> CheckinRecord {
        CheckinRecord(id: "rec-\(taskId)-\(dayKey)-\(status.rawValue)",
                      taskId: taskId, date: dayKey, status: status,
                      periodKey: nil, counted: counted,
                      createdAt: dayKey + " 10:00:00")
    }

    private func ratio(_ s: WeeklyStats) -> Double {
        XCTAssertNotNil(s.rate, "expected>0 时完成率不应为 nil")
        return s.rate ?? -1
    }

    // MARK: - expectedCount

    func testExpectedDailyCapsFutureDaysOut() {
        // Viewing stats on Wednesday: only Mon–Wed are expected (3 days), not diluted by Thu–Sun
        let t = makeTask(type: .daily, createdAt: "2026-08-01 00:00:00")
        XCTAssertEqual(StatsUtil.expectedCount(task: t, records: [], inWeekOf: date("2026-09-09")), 3)
        // Looking back on Sunday: the full week → 7 days
        XCTAssertEqual(StatsUtil.expectedCount(task: t, records: [], inWeekOf: date("2026-09-13")), 7)
    }

    func testExpectedDailyRespectsCreatedDay() {
        // Created this Wednesday → only Wednesday itself is expected
        XCTAssertEqual(StatsUtil.expectedCount(task: makeTask(type: .daily, createdAt: "2026-09-09 08:00:00"),
                                               records: [], inWeekOf: date("2026-09-09")), 1)
        // Created after this week → 0 expected this week
        XCTAssertEqual(StatsUtil.expectedCount(task: makeTask(type: .daily, createdAt: "2026-09-11 08:00:00"),
                                               records: [], inWeekOf: date("2026-09-09")), 0)
    }

    func testExpectedDailyRespectsEndDay() {
        // Ended Wednesday → Monday and Tuesday, 2 days
        let t = makeTask(type: .daily, endDate: "2026-09-08", createdAt: "2026-08-01 00:00:00")
        XCTAssertEqual(StatsUtil.expectedCount(task: t, records: [], inWeekOf: date("2026-09-09")), 2)
    }

    func testExpectedWeeklyDayCountsSameWeekOccurrence() {
        // Every Tuesday: this Tuesday 09-08 has passed → 1
        let t = makeTask(type: .weeklyDay, targetWeekday: 2, createdAt: "2026-08-01 00:00:00")
        XCTAssertEqual(StatsUtil.expectedCount(task: t, records: [], inWeekOf: date("2026-09-09")), 1)
        // Every Thursday: not yet reached (today is Wednesday) → 0
        let thu = makeTask(type: .weeklyDay, targetWeekday: 4, createdAt: "2026-08-01 00:00:00")
        XCTAssertEqual(StatsUtil.expectedCount(task: thu, records: [], inWeekOf: date("2026-09-09")), 0)
        // Looking back on Sunday → Thursday has passed → 1
        XCTAssertEqual(StatsUtil.expectedCount(task: thu, records: [], inWeekOf: date("2026-09-13")), 1)
    }

    func testExpectedWeeklyDayBeforeCreationIsZero() {
        // Every Monday, but created this Tuesday → this Monday's occurrence is not retroactive
        let t = makeTask(type: .weeklyDay, targetWeekday: 1, createdAt: "2026-09-08 08:00:00")
        XCTAssertEqual(StatsUtil.expectedCount(task: t, records: [], inWeekOf: date("2026-09-09")), 0)
    }

    func testExpectedWeeklyDayMissingConfigIsZero() {
        XCTAssertEqual(StatsUtil.expectedCount(task: makeTask(type: .weeklyDay),
                                               records: [], inWeekOf: date("2026-09-09")), 0)
    }

    func testExpectedWeeklyUsesTargetCount() {
        XCTAssertEqual(StatsUtil.expectedCount(task: makeTask(type: .weekly, targetCount: 3,
                                                              createdAt: "2026-08-01 00:00:00"),
                                               records: [], inWeekOf: date("2026-09-09")), 3)
        // No target configured → defaults to 1
        XCTAssertEqual(StatsUtil.expectedCount(task: makeTask(type: .weekly,
                                                              createdAt: "2026-08-01 00:00:00"),
                                               records: [], inWeekOf: date("2026-09-09")), 1)
    }

    func testExpectedWeeklyEndedIsZero() {
        let t = makeTask(type: .weekly, targetCount: 3, endDate: "2026-09-01",
                         createdAt: "2026-08-01 00:00:00")
        XCTAssertEqual(StatsUtil.expectedCount(task: t, records: [], inWeekOf: date("2026-09-09")), 0)
    }

    func testExpectedSpecificDateWithinWeek() {
        // Future (this Thursday) → 0; viewed on Sunday → 1; outside this week → 0
        let t = makeTask(type: .specificDate, targetDate: "2026-09-10",
                         createdAt: "2026-08-01 00:00:00")
        XCTAssertEqual(StatsUtil.expectedCount(task: t, records: [], inWeekOf: date("2026-09-09")), 0)
        XCTAssertEqual(StatsUtil.expectedCount(task: t, records: [], inWeekOf: date("2026-09-13")), 1)
        let outside = makeTask(type: .specificDate, targetDate: "2026-09-20",
                               createdAt: "2026-08-01 00:00:00")
        XCTAssertEqual(StatsUtil.expectedCount(task: outside, records: [], inWeekOf: date("2026-09-13")), 0)
    }

    func testExpectedWeeklyRespectsCreatedDay() {
        // Same rule as .daily: the task did not exist that week → 0 expected
        // (rather than polluting the historical week with 0%)
        let future = makeTask(type: .weekly, targetCount: 3, createdAt: "2026-09-16 08:00:00")
        XCTAssertEqual(StatsUtil.expectedCount(task: future, records: [], inWeekOf: date("2026-09-09")), 0,
                       "创建日晚于该周 → 该周不应计入次数目标")
        // Weeks it existed → target count as usual
        let thisWeek = makeTask(type: .weekly, targetCount: 3, createdAt: "2026-09-09 08:00:00")
        XCTAssertEqual(StatsUtil.expectedCount(task: thisWeek, records: [], inWeekOf: date("2026-09-10")), 3)
    }

    func testExpectedMonthlyIsZeroInWeekScope() {
        XCTAssertEqual(StatsUtil.expectedCount(task: makeTask(type: .monthly, targetCount: 10,
                                                              createdAt: "2026-08-01 00:00:00"),
                                               records: [], inWeekOf: date("2026-09-09")), 0)
    }

    // MARK: - weeklyStats / rate / passRate

    func testWeeklyStatsRateNilWhenNothingExpected() {
        let stats = StatsUtil.weeklyStats(tasks: [], records: [], ref: date("2026-09-09"))
        XCTAssertEqual(stats.expected, 0)
        XCTAssertNil(stats.rate, "应做为 0 时完成率应为 nil，而不是 0%")
        XCTAssertNil(stats.passRate)
    }

    func testWeeklyStatsCountsOncePerDay() {
        let t = makeTask(type: .daily, createdAt: "2026-08-01 00:00:00")
        let recs = [
            record(taskId: "t1", "2026-09-07", .passed),
            record(taskId: "t1", "2026-09-07", .failed), // same-day duplicate → counted once
        ]
        let stats = StatsUtil.weeklyStats(tasks: [t], records: recs, ref: date("2026-09-09"))
        XCTAssertEqual(stats.done, 1)
        XCTAssertEqual(stats.expected, 3)
        XCTAssertEqual(ratio(stats), 1.0 / 3.0, accuracy: 0.001)
    }

    func testWeeklyStatsIgnoresUncountedAndOutOfWeek() {
        let t = makeTask(type: .daily, createdAt: "2026-08-01 00:00:00")
        let recs = [
            record(taskId: "t1", "2026-09-08", .passed, counted: false), // uncounted → not done
            record(taskId: "t1", "2026-09-06", .passed),                 // last Sunday → outside this week
            record(taskId: "other", "2026-09-07", .passed),              // another task → not counted for this one
        ]
        let stats = StatsUtil.weeklyStats(tasks: [t], records: recs, ref: date("2026-09-09"))
        XCTAssertEqual(stats.done, 0)
        XCTAssertEqual(stats.expected, 3)
    }

    func testWeeklyStatsExcludesEndedTaskRecords() {
        // Task ended this Tuesday → only Mon/Tue are expected this week; records of an ended task don't count
        let t = makeTask(type: .daily, endDate: "2026-09-08", createdAt: "2026-08-01 00:00:00")
        XCTAssertEqual(StatsUtil.expectedCount(task: t, records: [], inWeekOf: date("2026-09-09")), 2)
    }

    func testPassRateNilWhenNoJudgement() {
        // Only awaiting records → judged = 0 → pass rate nil (UI shows "no judgements yet")
        let t = makeTask(type: .daily, createdAt: "2026-08-01 00:00:00")
        let recs = [record(taskId: "t1", "2026-09-07", .awaiting)]
        let stats = StatsUtil.weeklyStats(tasks: [t], records: recs, ref: date("2026-09-09"))
        XCTAssertEqual(stats.done, 1, "打卡即算完成")
        XCTAssertEqual(stats.judged, 0)
        XCTAssertNil(stats.passRate)
    }

    func testPassRateCountsPassedOverJudged() {
        let t = makeTask(type: .daily, createdAt: "2026-08-01 00:00:00")
        let recs = [
            record(taskId: "t1", "2026-09-07", .passed),
            record(taskId: "t1", "2026-09-08", .failed),
            record(taskId: "t1", "2026-09-09", .awaiting), // awaiting does not count in the denominator
        ]
        let stats = StatsUtil.weeklyStats(tasks: [t], records: recs, ref: date("2026-09-09"))
        XCTAssertEqual(stats.done, 3)
        XCTAssertEqual(stats.passed, 1)
        XCTAssertEqual(stats.judged, 2)
        XCTAssertEqual(stats.passRate ?? -1, 0.5, accuracy: 0.001)
    }

    // MARK: - completionByTask

    func testCompletionByTaskSortedByRateAscending() {
        let good = makeTask(id: "good", name: "每日全做", type: .daily, createdAt: "2026-08-01 00:00:00")
        let mid = makeTask(id: "mid", name: "每日做一次", type: .daily, createdAt: "2026-08-01 00:00:00")
        let poor = makeTask(id: "poor", name: "每周某天没做", type: .weeklyDay, targetWeekday: 1,
                            createdAt: "2026-08-01 00:00:00")
        let excluded = makeTask(id: "exc", name: "月任务", type: .monthly, targetCount: 10,
                                createdAt: "2026-08-01 00:00:00")
        let recs = [
            record(taskId: "good", "2026-09-07", .passed),
            record(taskId: "good", "2026-09-08", .passed),
            record(taskId: "good", "2026-09-09", .passed),
            record(taskId: "mid", "2026-09-07", .passed),
        ]
        let list = StatsUtil.completionByTask(tasks: [good, mid, poor, excluded],
                                              records: recs, ref: date("2026-09-09"))
        XCTAssertEqual(list.map { $0.id }, ["poor", "mid", "good"], "完成率升序 → 短板排前")
        XCTAssertFalse(list.contains { $0.id == "exc" }, "应做为 0 的任务不进榜")
        XCTAssertEqual(list[0].done, 0)
        XCTAssertEqual(list[0].expected, 1)
        XCTAssertEqual(list[0].rate ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(list[2].rate ?? -1, 1.0, accuracy: 0.001)
    }

    func testCompletionByTaskEmptyWhenNothingExpected() {
        let list = StatsUtil.completionByTask(tasks: [], records: [], ref: date("2026-09-09"))
        XCTAssertTrue(list.isEmpty)
    }

    // MARK: - completionByWeekday

    func testCompletionByWeekdayAlwaysSevenItems() {
        let t = makeTask(type: .daily, createdAt: "2026-08-01 00:00:00")
        let list = StatsUtil.completionByWeekday(tasks: [t], records: [], ref: date("2026-09-09"))
        XCTAssertEqual(list.count, 7)
        XCTAssertEqual(list.map { $0.label }, ["周一", "周二", "周三", "周四", "周五", "周六", "周日"])
        XCTAssertEqual(list.map { $0.weekday }, [1, 2, 3, 4, 5, 6, 7])
    }

    func testCompletionByWeekdayFutureDaysZeroExpected() {
        // Today is Wednesday → Mon/Tue/Wed have 1 expected each; Thu–Sun are future → 0
        let t = makeTask(type: .daily, createdAt: "2026-08-01 00:00:00")
        let list = StatsUtil.completionByWeekday(tasks: [t], records: [], ref: date("2026-09-09"))
        XCTAssertEqual(list.map { $0.expected }, [1, 1, 1, 0, 0, 0, 0])
        XCTAssertNil(list[3].rate, "未来日不应产生完成率")
    }

    func testCompletionByWeekdayMatchesRecords() {
        let midweek = makeTask(id: "w", type: .weeklyDay, targetWeekday: 2,
                               createdAt: "2026-08-01 00:00:00")
        let daily = makeTask(id: "d", type: .daily, createdAt: "2026-08-01 00:00:00")
        let recs = [record(taskId: "d", "2026-09-08", .passed)]
        let list = StatsUtil.completionByWeekday(tasks: [daily, midweek], records: recs,
                                                 ref: date("2026-09-09"))
        // Tuesday: daily + weeklyDay = 2 expected, only daily done → 1/2
        XCTAssertEqual(list[1].expected, 2)
        XCTAssertEqual(list[1].done, 1)
        XCTAssertEqual(list[1].rate ?? -1, 0.5, accuracy: 0.001)
        // Monday: only daily expected (weeklyDay targets Tuesday) → 1 expected, 0 done
        XCTAssertEqual(list[0].expected, 1)
        XCTAssertEqual(list[0].done, 0)
        XCTAssertEqual(list[0].rate ?? -1, 0, accuracy: 0.001)
    }

    // MARK: - weeklyTrend

    func testWeeklyTrendLengthAndOrder() {
        let t = makeTask(type: .daily, createdAt: "2026-08-01 00:00:00")
        let trend = StatsUtil.weeklyTrend(tasks: [t], records: [], ref: date("2026-09-09"))
        XCTAssertEqual(trend.count, 4)
        XCTAssertEqual(trend.map { $0.label }, ["4 周前", "3 周前", "上周", "本周"],
                       "按时间升序排列 → 本周在最右")
    }

    func testWeeklyTrendCustomWeeks() {
        let t = makeTask(type: .daily, createdAt: "2026-08-01 00:00:00")
        XCTAssertEqual(StatsUtil.weeklyTrend(tasks: [t], records: [], ref: date("2026-09-09"), weeks: 2).count, 2)
        XCTAssertEqual(StatsUtil.weeklyTrend(tasks: [t], records: [], ref: date("2026-09-09"), weeks: 0).count, 1,
                       "非法入参兜底为 1 周")
    }

    func testWeeklyTrendRatesReflectHistory() {
        let t = makeTask(type: .daily, createdAt: "2026-08-01 00:00:00")
        let recs = [
            record(taskId: "t1", "2026-09-07", .passed),
            record(taskId: "t1", "2026-09-08", .passed),
            record(taskId: "t1", "2026-09-09", .passed),
        ]
        let trend = StatsUtil.weeklyTrend(tasks: [t], records: recs, ref: date("2026-09-09"))
        // This week: 3 expected (Mon–Wed), 3 done → 100%
        XCTAssertEqual(trend.last?.label, "本周")
        XCTAssertEqual(trend.last?.rate ?? -1, 1.0, accuracy: 0.001)
        // Other weeks have no records → rate 0 (expected non-zero), not nil
        XCTAssertEqual(trend[0].rate ?? -1, 0, accuracy: 0.001)
    }

    // MARK: - achievedWeekStreak

    func testAchievedStreakZeroWhenNeverAchieved() {
        let t = makeTask(type: .daily, createdAt: "2026-08-01 00:00:00")
        XCTAssertEqual(StatsUtil.achievedWeekStreak(tasks: [t], records: [], ref: date("2026-09-09")), 0)
    }

    func testAchievedStreakCountsCurrentWeekWhenAchieved() {
        // This week 3/3 achieved + last week 7/7 achieved, two weeks ago only 3/7 → streak of 2
        let t = makeTask(type: .daily, createdAt: "2026-08-01 00:00:00")
        var recs: [CheckinRecord] = []
        for day in ["2026-09-07", "2026-09-08", "2026-09-09"] {
            recs.append(record(taskId: "t1", day, .passed))           // this week 3/3
        }
        for day in ["2026-08-31", "2026-09-01", "2026-09-02", "2026-09-03",
                    "2026-09-04", "2026-09-05", "2026-09-06"] {
            recs.append(record(taskId: "t1", day, .passed))           // last week 7/7
        }
        for day in ["2026-08-24", "2026-08-25", "2026-08-26"] {
            recs.append(record(taskId: "t1", day, .passed))           // two weeks ago 3/7 → not achieved, streak breaks here
        }
        XCTAssertEqual(StatsUtil.achievedWeekStreak(tasks: [t], records: recs, ref: date("2026-09-09")), 2)
    }

    func testAchievedStreakStartsFromLastWeekWhenCurrentNotAchieved() {
        // This week only 2/3 done (< 80%) → must not break; counting starts from last week; last week 7/7 → streak of 1
        let t = makeTask(type: .daily, createdAt: "2026-08-01 00:00:00")
        var recs: [CheckinRecord] = []
        for day in ["2026-09-07", "2026-09-08"] {
            recs.append(record(taskId: "t1", day, .passed))
        }
        for day in ["2026-08-31", "2026-09-01", "2026-09-02", "2026-09-03",
                    "2026-09-04", "2026-09-05", "2026-09-06"] {
            recs.append(record(taskId: "t1", day, .passed))
        }
        XCTAssertEqual(StatsUtil.achievedWeekStreak(tasks: [t], records: recs, ref: date("2026-09-09")), 1)
    }

    func testAchieveRatioConstant() {
        XCTAssertEqual(Constants.achieveRatio, 0.8, accuracy: 0.0001)
    }

    /// Historical weeks of a period task: the task did not exist yet → nothing expected that week →
    /// rate nil, not 0% (regression: .weekly previously only checked isEnded, not the created day,
    /// so the trend sprouted phantom 0% bars)
    func testWeeklyTrendNilForWeeksBeforeCreation() {
        let t = makeTask(type: .weekly, targetCount: 3, createdAt: "2026-09-09 08:00:00")
        let trend = StatsUtil.weeklyTrend(tasks: [t], records: [], ref: date("2026-09-10"))
        XCTAssertEqual(trend.count, 4)
        for idx in 0..<3 {
            XCTAssertNil(trend[idx].rate, "第 \(idx) 项属于任务创建前的历史周 → 应显示「—」")
        }
        XCTAssertEqual(trend[3].rate ?? -1, 0, accuracy: 0.001) // this week: 3 expected / 0 done
    }

    /// Achieved-week streak: only "this week" gets the not-yet-achieved exemption; a historical miss
    /// breaks the streak — it cannot skip endlessly backwards.
    /// (Regression: the old implementation continued on every step while streak==0, so
    /// "this week 0% + last week 0% + two weeks ago 100%" misreported 1)
    func testAchievedStreakDoesNotSkipHistoricalMisses() {
        let t = makeTask(type: .daily, createdAt: "2026-08-01 00:00:00")
        var recs: [CheckinRecord] = []
        // Two weeks ago (08-24 ~ 08-30) full attendance, 100%
        for day in ["2026-08-24", "2026-08-25", "2026-08-26", "2026-08-27",
                    "2026-08-28", "2026-08-29", "2026-08-30"] {
            recs.append(record(taskId: "t1", day, .passed))
        }
        // Last week (08-31 ~ 09-06) 0 check-ins, this week 0 → streak should be 0
        XCTAssertEqual(StatsUtil.achievedWeekStreak(tasks: [t], records: recs, ref: date("2026-09-09")), 0)
    }

    /// Achieved-week streak: an intervening "empty week" (0 expected that week) does **not** break
    /// the streak.
    ///
    /// Regression lock: the old semantics also treated "no expected data" as a break →
    /// "this week 100% + empty last week + two weeks ago 100%" misreported 1.
    /// Under the new semantics the empty week is skipped and counting continues backwards: 2.
    func testAchievedStreakSkipsEmptyWeek() {
        // ref = 2026-09-10 (Thursday) → this week = 09-07 ~ 09-13; last week = 08-31 ~ 09-06; two weeks ago = 08-24 ~ 08-30
        // t1: one-off task on Thursday 08-27 (two weeks ago), completed → that week 1/1 = 100%
        let t1 = makeTask(id: "t1", type: .specificDate, targetDate: "2026-08-27",
                          createdAt: "2026-08-01 00:00:00")
        // t2: created and completed today (09-10) → this week 1/1 = 100%
        let t2 = makeTask(id: "t2", type: .daily, createdAt: "2026-09-10 00:00:00")
        let recs = [record(taskId: "t1", "2026-08-27", .passed),
                    record(taskId: "t2", "2026-09-10", .passed)]

        // Precondition: last week is genuinely "empty" — neither task exists yet or applies → expected == 0, rate nil
        let lastWeek = StatsUtil.weeklyStats(tasks: [t1, t2], records: recs, ref: date("2026-09-06"))
        XCTAssertEqual(lastWeek.expected, 0, "上周应为空周（无应做）")
        XCTAssertNil(lastWeek.rate, "空周 → 完成率 nil，不是 0%")

        // This week +1, empty last week skipped, two weeks ago +1 → 2
        XCTAssertEqual(StatsUtil.achievedWeekStreak(tasks: [t1, t2], records: recs, ref: date("2026-09-10")), 2)
    }

    /// Achieved-week streak: the boundary opposite of the "empty week" — a historical week **with
    /// expected but zero check-ins** is a real failure and must break the streak.
    ///
    /// The only difference from `testAchievedStreakSkipsEmptyWeek`: last week switches from "empty"
    /// to "has an unmet task", so the streak drops from 2 to 1. The two tests are a pair pinning the
    /// "empty week ≠ failed week" gate.
    func testAchievedStreakStopsAtFailedWeekWithData() {
        let t1 = makeTask(id: "t1", type: .specificDate, targetDate: "2026-08-27",
                          createdAt: "2026-08-01 00:00:00")     // two weeks ago 100%
        let t2 = makeTask(id: "t2", type: .daily, createdAt: "2026-09-10 00:00:00") // this week 100%
        // t3: last week (08-31 ~ 09-06) has expected (09-03) but zero check-ins → a real failed week
        let t3 = makeTask(id: "t3", type: .specificDate, targetDate: "2026-09-03",
                          createdAt: "2026-08-01 00:00:00")
        let tasks = [t1, t2, t3]
        let recs = [record(taskId: "t1", "2026-08-27", .passed),
                    record(taskId: "t2", "2026-09-10", .passed)]

        // Precondition: last week is non-empty — expected 1 / done 0 → rate 0
        let lastWeek = StatsUtil.weeklyStats(tasks: tasks, records: recs, ref: date("2026-09-06"))
        XCTAssertEqual(lastWeek.expected, 1, "上周 t3 应做 1 次（非空周）")
        XCTAssertEqual(lastWeek.done, 0)
        XCTAssertEqual(ratio(lastWeek), 0.0, accuracy: 0.001)

        // This week +1 → last week (has data, not achieved) breaks it → 1
        XCTAssertEqual(StatsUtil.achievedWeekStreak(tasks: tasks, records: recs, ref: date("2026-09-10")), 1)
    }

    // MARK: - Insufficient sample

    func testMinSampleForRateThreshold() {
        XCTAssertEqual(Constants.minSampleForRate, 3)
        // Typical new user: a single weekly-day task has only 1 expected this week → below the
        // threshold, the UI takes the insufficient-sample branch
        let t = makeTask(type: .weeklyDay, targetWeekday: 1, createdAt: "2026-09-01 00:00:00")
        let expected = StatsUtil.expectedCount(task: t, records: [], inWeekOf: date("2026-09-09"))
        XCTAssertEqual(expected, 1)
        XCTAssertLessThan(expected, Constants.minSampleForRate)
    }

    func testSampleInsufficientForThreeWeeklyDayTasks() {
        // Three weekly-day tasks and it is only Tuesday → expected 2 < 3 → still insufficient sample
        let tasks = [
            makeTask(id: "a", type: .weeklyDay, targetWeekday: 1, createdAt: "2026-08-01 00:00:00"),
            makeTask(id: "b", type: .weeklyDay, targetWeekday: 2, createdAt: "2026-08-01 00:00:00"),
            makeTask(id: "c", type: .weeklyDay, targetWeekday: 5, createdAt: "2026-08-01 00:00:00"),
        ]
        let stats = StatsUtil.weeklyStats(tasks: tasks, records: [], ref: date("2026-09-09"))
        XCTAssertEqual(stats.expected, 2, "周五还没到 → 只统计周一、周二")
        XCTAssertLessThan(stats.expected, Constants.minSampleForRate)
    }

    // MARK: - Backfill (date earlier than the creation day)

    func testBackdatedCheckinBeforeCreationCountsAsSlot() {
        // User-requested: backfilling Monday's done from Thursday must count as Monday's
        // The task is only created 09-10, but a counted record exists on 09-07 (Monday)
        // → Monday counts as one of its expected slots
        let t = makeTask(type: .weeklyDay, targetWeekday: 1, createdAt: "2026-09-10 08:00:00")
        let recs = [record(taskId: "t1", "2026-09-07", .passed)]
        XCTAssertEqual(StatsUtil.expectedCount(task: t, records: recs, inWeekOf: date("2026-09-10")), 1,
                       "补打卡日应成为应做槽位")
        let stats = StatsUtil.weeklyStats(tasks: [t], records: recs, ref: date("2026-09-10"))
        XCTAssertEqual(stats.expected, 1)
        XCTAssertEqual(stats.done, 1)
        XCTAssertEqual(ratio(stats), 1.0, accuracy: 0.001)
    }

    func testPastDayBeforeCreationWithoutRecordIsNotSlot() {
        // Inverse lock: a historical date before creation with no check-in still does not count as
        // expected (otherwise historical weeks get retroactively turned into 0%)
        let t = makeTask(type: .weeklyDay, targetWeekday: 1, createdAt: "2026-09-10 08:00:00")
        XCTAssertEqual(StatsUtil.expectedCount(task: t, records: [], inWeekOf: date("2026-09-10")), 0)
    }

    func testBackdatedRecordDoesNotLeakIntoOtherDays() {
        // Backfill only recognizes the day with a record; it never spreads the task to other dates
        let t = makeTask(type: .weeklyDay, targetWeekday: 1, createdAt: "2026-09-10 08:00:00")
        let recs = [record(taskId: "t1", "2026-09-07", .passed)]
        let byWeekday = StatsUtil.completionByWeekday(tasks: [t], records: recs, ref: date("2026-09-10"))
        XCTAssertEqual(byWeekday[0].expected, 1, "周一：补打卡 → 1 个槽位")
        XCTAssertEqual(byWeekday[0].done, 1)
        XCTAssertEqual(byWeekday[1].expected, 0, "周二：该任务是每周一 → 无槽位")
        XCTAssertNil(byWeekday[1].rate)
    }

    // MARK: - Completion rate cap (done ≤ expected)

    func testCompletionRateNeverExceedsHundredPercent() {
        // Mixed data: backfills + same-day duplicates + a period task over-checking; done must not exceed expected
        let tasks = [
            makeTask(id: "d1", type: .daily, createdAt: "2026-09-09 08:00:00"),
            makeTask(id: "w1", type: .weeklyDay, targetWeekday: 1, createdAt: "2026-09-10 08:00:00"),
            makeTask(id: "k1", type: .weekly, targetCount: 2, createdAt: "2026-08-01 00:00:00"),
        ]
        var recs: [CheckinRecord] = []
        for day in ["2026-09-07", "2026-09-08", "2026-09-09", "2026-09-10"] {
            recs.append(record(taskId: "d1", day, .passed))  // daily task: 4 consecutive days (2 backfilled before creation)
            recs.append(record(taskId: "d1", day, .failed))  // same-day duplicate → counted once
        }
        recs.append(record(taskId: "w1", "2026-09-07", .passed))       // Monday backfill
        for day in ["2026-09-07", "2026-09-08", "2026-09-09"] {
            recs.append(record(taskId: "k1", day, .passed))            // period task: target 2 but checked in 3 times
        }

        let stats = StatsUtil.weeklyStats(tasks: tasks, records: recs, ref: date("2026-09-10"))
        // Exact values (the old metric gave 200% on this data; pinning absolutes guards against
        // drift better than inequalities alone)
        XCTAssertEqual(stats.expected, 7, "d1 补打卡 4 天 + w1 周一 1 + k1 目标 2")
        XCTAssertEqual(stats.done, 7)
        XCTAssertEqual(stats.passed, 3)
        XCTAssertEqual(stats.judged, 7)
        XCTAssertLessThanOrEqual(stats.done, stats.expected, "done 不得大于 expected")
        XCTAssertLessThanOrEqual(ratio(stats), 1.0, "完成率不得超过 100%")

        for item in StatsUtil.completionByTask(tasks: tasks, records: recs, ref: date("2026-09-10")) {
            XCTAssertLessThanOrEqual(item.done, item.expected)
            XCTAssertLessThanOrEqual(item.rate ?? 0, 1.0)
        }
        for item in StatsUtil.completionByWeekday(tasks: tasks, records: recs, ref: date("2026-09-10")) {
            XCTAssertLessThanOrEqual(item.done, item.expected)
            if let r = item.rate { XCTAssertLessThanOrEqual(r, 1.0) }
        }
    }

    // MARK: - Real production data reproduction (previously showed 113%)

    /// 2026-09-10 (Thursday) real data: 16 weeklyDay tasks + 9 counted records,
    /// where Monday's 3 records belong to tasks created 09-09 (after Monday)
    /// → pre-fix expected=8/done=9 → 113%.
    func testRealDataBackdatedCheckinsNoLongerExceedHundredPercent() {
        let ref = date("2026-09-10") // Thursday; this week 09-07 ~ 09-13, cap = 09-10
        var tasks: [Task] = []
        // Monday ×3 (created after Monday → slots come from records)
        tasks += (1...3).map { makeTask(id: "m\($0)", type: .weeklyDay, targetWeekday: 1,
                                        createdAt: "2026-09-09 08:00:00") }
        // Tuesday ×3
        tasks += (1...3).map { makeTask(id: "t\($0)", type: .weeklyDay, targetWeekday: 2,
                                        createdAt: "2026-09-08 08:00:00") }
        // Wednesday ×2
        tasks += (1...2).map { makeTask(id: "w\($0)", type: .weeklyDay, targetWeekday: 3,
                                        createdAt: "2026-09-08 08:00:00") }
        // Thursday ×3
        tasks += (1...3).map { makeTask(id: "th\($0)", type: .weeklyDay, targetWeekday: 4,
                                        createdAt: "2026-09-09 08:00:00") }
        // The other 5 tasks fall on Saturday (1) / Sunday (4) (future days) → no slots; created 09-09 matching production
        tasks += [makeTask(id: "f1", type: .weeklyDay, targetWeekday: 6, createdAt: "2026-09-09 08:00:00"),
                  makeTask(id: "f2", type: .weeklyDay, targetWeekday: 7, createdAt: "2026-09-09 08:00:00"),
                  makeTask(id: "f3", type: .weeklyDay, targetWeekday: 7, createdAt: "2026-09-09 08:00:00"),
                  makeTask(id: "f4", type: .weeklyDay, targetWeekday: 7, createdAt: "2026-09-09 08:00:00"),
                  makeTask(id: "f5", type: .weeklyDay, targetWeekday: 7, createdAt: "2026-09-09 08:00:00")]
        XCTAssertEqual(tasks.count, 16)

        var recs: [CheckinRecord] = []
        recs.append(record(taskId: "m1", "2026-09-07", .passed))
        recs.append(record(taskId: "m2", "2026-09-07", .failed))
        recs.append(record(taskId: "m3", "2026-09-07", .failed))
        recs.append(record(taskId: "t1", "2026-09-08", .passed))
        recs.append(record(taskId: "t2", "2026-09-08", .failed))
        recs.append(record(taskId: "t3", "2026-09-08", .failed))
        recs.append(record(taskId: "w1", "2026-09-09", .failed))
        recs.append(record(taskId: "th1", "2026-09-10", .failed))
        recs.append(record(taskId: "th2", "2026-09-10", .failed))

        let stats = StatsUtil.weeklyStats(tasks: tasks, records: recs, ref: ref)
        XCTAssertEqual(stats.expected, 11, "3(周一) + 3(周二) + 2(周三) + 3(周四)")
        XCTAssertEqual(stats.done, 9)
        XCTAssertEqual(ratio(stats), 9.0 / 11.0, accuracy: 0.001) // ≈ 82%, no longer 113%
        XCTAssertLessThanOrEqual(ratio(stats), 1.0)
        // Pass rate: passed 2 / judged 9 ≈ 22%
        XCTAssertEqual(stats.passed, 2)
        XCTAssertEqual(stats.judged, 9)
        XCTAssertEqual(stats.passRate ?? -1, 2.0 / 9.0, accuracy: 0.001)

        // Achieved-week streak: this week 9/11 ≈ 82% ≥ 80% → +1; the tasks were created 09-08 / 09-09,
        // so all earlier historical weeks are "empty weeks" (nothing expected) → skipped, not breaking → streak stays 1
        XCTAssertEqual(StatsUtil.achievedWeekStreak(tasks: tasks, records: recs, ref: ref), 1,
                       "线上真实数据：历史周全空 → 连续数应保持 1（空周豁免不改变既有结果）")

        // By weekday: Mon 100% / Tue 100% / Wed 50% / Thu 67% / Fri–Sun are future → "—"
        let byWeekday = StatsUtil.completionByWeekday(tasks: tasks, records: recs, ref: ref)
        XCTAssertEqual(byWeekday.map { $0.expected }, [3, 3, 2, 3, 0, 0, 0])
        XCTAssertEqual(byWeekday.map { $0.done }, [3, 3, 1, 2, 0, 0, 0])
        XCTAssertEqual(byWeekday[0].rate ?? -1, 1.0, accuracy: 0.001)          // Mon 100%
        XCTAssertEqual(byWeekday[1].rate ?? -1, 1.0, accuracy: 0.001)          // Tue 100%
        XCTAssertEqual(byWeekday[2].rate ?? -1, 0.5, accuracy: 0.001)          // Wed 50%
        XCTAssertEqual(byWeekday[3].rate ?? -1, 2.0 / 3.0, accuracy: 0.001)    // Thu 67%
        for idx in 4...6 {
            XCTAssertNil(byWeekday[idx].rate, "周五~周日是未来日 → 显示「—」")
        }
    }

    // MARK: - Period tasks: future-day records must not count in done (Bug A — READ side)

    /// ref=2026-09-09 (Wednesday): Thu–Sun remain this week, but the cap is 09-09.
    /// The period task's counted records falling on 09-10/11/12 are future days → must not count as done.
    func testWeeklyStatsFutureDayRecordDoesNotCount() {
        let t = makeTask(type: .weekly, targetCount: 3, createdAt: "2026-08-01 00:00:00")
        let recs = [record(taskId: "t1", "2026-09-12", .passed)] // Saturday: future
        let stats = StatsUtil.weeklyStats(tasks: [t], records: recs, ref: ref)
        XCTAssertEqual(stats.expected, 3, "周期目标 3 次计入应做")
        XCTAssertEqual(stats.done, 0, "未来日记录必须被截断在 cap 之外")
        XCTAssertEqual(ratio(stats), 0.0, accuracy: 0.0001,
                       "修复前 done=1 → rate=0.333；修复后 → 0.0")
    }

    /// Cap boundary: today's record must count; tomorrow's must not; with both present, done=1
    func testWeeklyStatsTodayIsLastCountableDay() {
        let t = makeTask(type: .weekly, targetCount: 3, createdAt: "2026-08-01 00:00:00")
        let recs = [
            record(taskId: "t1", "2026-09-09", .passed), // today: counted
            record(taskId: "t1", "2026-09-10", .passed), // tomorrow: future, not counted
        ]
        let stats = StatsUtil.weeklyStats(tasks: [t], records: recs, ref: ref)
        XCTAssertEqual(stats.expected, 3)
        XCTAssertEqual(stats.done, 1, "只有今天的记录算完成")
    }

    /// The same case in the per-task weakest-first list: future-day records do not affect done / rate
    func testCompletionByTaskWeeklyRespectsCap() {
        let t = makeTask(type: .weekly, targetCount: 3, createdAt: "2026-08-01 00:00:00")
        let recs = [record(taskId: "t1", "2026-09-12", .passed)] // weekend: future
        let list = StatsUtil.completionByTask(tasks: [t], records: recs, ref: ref)
        XCTAssertEqual(list.count, 1, "应有 1 行（expected > 0）")
        XCTAssertEqual(list[0].expected, 3)
        XCTAssertEqual(list[0].done, 0, "未来日记录不得计入 done")
        XCTAssertEqual(list[0].rate ?? -1, 0.0, accuracy: 0.0001)
    }

    /// Regression lock: when ref is this week's Sunday (whole week past), cap = week end and the
    /// Saturday record must count as usual (the fix must not break the normal "whole week already
    /// past" scenario).
    func testWeeklyStatsFullHistoricalWeekStillWorks() {
        let t = makeTask(type: .weekly, targetCount: 3, createdAt: "2026-08-01 00:00:00")
        let recs = [record(taskId: "t1", "2026-09-12", .passed)] // this Saturday: a future that has passed (cap = Sunday)
        let stats = StatsUtil.weeklyStats(tasks: [t], records: recs,
                                          ref: date("2026-09-13"))
        XCTAssertEqual(stats.expected, 3)
        XCTAssertEqual(stats.done, 1, "整周已过的历史周：周六的记录必须计入")
    }

    // MARK: - Single-day exemption (skip) metrics

    /// Day-level: skipping a day removes it from the expected slots (denominator -1) while keeping done ≤ expected.
    func testSkippedDayExcludedFromExpectedDaily() {
        let t = makeTask(type: .daily, createdAt: "2026-08-01 00:00:00")
        let recs = [record(taskId: "t1", "2026-09-07", .skipped, counted: false)] // skip Monday
        XCTAssertEqual(StatsUtil.expectedCount(task: t, records: recs, inWeekOf: date("2026-09-09")), 2,
                       "周三看：周一~周三 3 天，跳过周一 → 2")
        let stats = StatsUtil.weeklyStats(tasks: [t], records: recs, ref: date("2026-09-09"))
        XCTAssertEqual(stats.expected, 2)
        XCTAssertEqual(stats.done, 0, "跳过不算完成")
        XCTAssertLessThanOrEqual(stats.done, stats.expected)
    }

    /// Count-based task: target 5, 3 days skipped → effectiveTarget = min(5, 7-3) = 4.
    func testWeeklyEffectiveTargetCappedBySkippedDays() {
        let t = makeTask(type: .weekly, targetCount: 5, createdAt: "2026-08-01 00:00:00")
        let recs = ["2026-09-07", "2026-09-08", "2026-09-09"]
            .map { record(taskId: "t1", $0, .skipped, counted: false) }
        XCTAssertEqual(StatsUtil.expectedCount(task: t, records: recs, inWeekOf: date("2026-09-09")), 4,
                       "min(5, 7-3) = 4")
    }

    /// No-skip regression lock: target 5, no skips → expected stays 5 (identical to current behavior).
    func testWeeklyNoSkipKeepsTargetUnchanged() {
        let t = makeTask(type: .weekly, targetCount: 5, createdAt: "2026-08-01 00:00:00")
        XCTAssertEqual(StatsUtil.expectedCount(task: t, records: [], inWeekOf: date("2026-09-09")), 5,
                       "无跳过 = 7 可做日 → min(5,7)=5，行为不得漂移")
        let stats = StatsUtil.weeklyStats(tasks: [t], records: [], ref: date("2026-09-09"))
        XCTAssertEqual(stats.expected, 5)
    }

    /// Monthly tasks' available-days capping is PeriodUtil's job; StatsUtil's weekly metric excludes
    /// monthly (always 0).
    func testMonthlyEffectiveTargetCapped() {
        let t = makeTask(type: .monthly, targetCount: 10, createdAt: "2026-08-01 00:00:00")
        let recs = ["2026-09-07", "2026-09-08"]
            .map { record(taskId: "t1", $0, .skipped, counted: false) }
        XCTAssertEqual(StatsUtil.expectedCount(task: t, records: recs, inWeekOf: date("2026-09-09")), 0,
                       "monthly 不进周口径，跳过与否都不改变")
        XCTAssertEqual(StatsUtil.weeklyStats(tasks: [t], records: recs, ref: date("2026-09-09")).expected, 0)
    }

    /// 【Key】A skipped future day still deducts available days (full week, not cap); day-level
    /// future days are excluded from expected by the cap. The two metrics differ — do not mix them up.
    func testFutureSkippedDayStillDeductsAvailableDays() {
        // Count-based task: target 7, Thursday 09-11 skipped (future relative to ref=09-09)
        // → available 7-1=6 → min(7,6)=6. Capping by ref instead would wrongly give 7 (future days
        // don't count) → this pins "available days use the whole period".
        let weekly = makeTask(id: "w", type: .weekly, targetCount: 7, createdAt: "2026-08-01 00:00:00")
        let recs = [record(taskId: "w", "2026-09-11", .skipped, counted: false)] // Thursday: future
        XCTAssertEqual(StatsUtil.expectedCount(task: weekly, records: recs, inWeekOf: date("2026-09-09")), 6,
                       "未来日仍是可做日：跳过它 → 可做 7-1=6（不按 cap 截断）")
        XCTAssertEqual(StatsUtil.expectedCount(task: weekly, records: [], inWeekOf: date("2026-09-09")), 7,
                       "无跳过 → 7，作为对照")
        // Day-level: future days are outside this week's expected (cap-truncated); skipping them changes nothing
        let daily = makeTask(id: "d", type: .daily, createdAt: "2026-08-01 00:00:00")
        XCTAssertEqual(StatsUtil.expectedCount(task: daily,
                                              records: [record(taskId: "d", "2026-09-11", .skipped, counted: false)],
                                              inWeekOf: date("2026-09-09")), 3,
                       "周一~周三 3 天，未来日 09-11 不入单日 expected")
        XCTAssertEqual(StatsUtil.expectedCount(task: daily, records: [], inWeekOf: date("2026-09-09")), 3,
                       "无跳过时同为 3 → 跳过未来日不影响单日级")
    }

    /// Skipped days do not break the achieved-week streak: skips shrink this week's expected → still achieved.
    func testAchievedWeekStreakNotBrokenBySkip() {
        let t = makeTask(type: .daily, createdAt: "2026-08-31 00:00:00")
        var recs: [CheckinRecord] = []
        for day in ["2026-08-31", "2026-09-01", "2026-09-02", "2026-09-03",
                    "2026-09-04", "2026-09-05", "2026-09-06"] {
            recs.append(record(taskId: "t1", day, .passed))            // last week 7/7 achieved
        }
        recs.append(record(taskId: "t1", "2026-09-07", .skipped, counted: false))
        recs.append(record(taskId: "t1", "2026-09-08", .skipped, counted: false))
        recs.append(record(taskId: "t1", "2026-09-09", .passed))       // this week only Wednesday remains → 1/1 achieved
        let thisWeek = StatsUtil.weeklyStats(tasks: [t], records: recs, ref: date("2026-09-09"))
        XCTAssertEqual(thisWeek.expected, 1, "跳过周一/周二 → 本周应做 1")
        XCTAssertEqual(thisWeek.done, 1)
        // Old metric (skips not deducted) = 1/3 ≈ 33% → this week not achieved; new metric 1/1 = 100%
        // → achieved → streak 2
        XCTAssertEqual(StatsUtil.achievedWeekStreak(tasks: [t], records: recs, ref: date("2026-09-09")), 2,
                       "本周仍达标 → 连续 2 周（跳过日不打断）")
    }
}
