import XCTest
import CheckinCore

/// StreakUtil.computeStreak boundary tests (daily tasks only; anchored to the current date):
/// streak includes today / break resets to the recent segment / today missing → starts from
/// yesterday / counted records only / other tasks isolated / non-daily returns 0.
/// computeStreak anchors to the current system date, so all dates are constructed relative to now
/// for reproducibility.
final class StreakUtilTests: XCTestCase {

    /// offset: day offset relative to today (0=today, -1=yesterday, ...)
    private func day(_ offset: Int) -> String {
        let cal = Calendar(identifier: .gregorian)
        let d = cal.date(byAdding: .day, value: offset, to: Date())!
        return DateUtil.localDate(d)
    }

    private func dailyTask(_ id: String = "t1") -> CheckinCore.Task {
        CheckinCore.Task(id: id, name: "每日", type: .daily, acceptanceRequired: false,
             createdAt: "2026-01-01 00:00:00")
    }

    private func rec(_ taskId: String, _ date: String, counted: Bool) -> CheckinRecord {
        CheckinRecord(id: UUID().uuidString, taskId: taskId, date: date,
                      status: counted ? .passed : .awaiting, counted: counted,
                      createdAt: date + " 00:00:00")
    }

    /// Single-day exemption record (status=.skipped, counted=false)
    private func skipRec(_ taskId: String, _ date: String) -> CheckinRecord {
        CheckinRecord(id: UUID().uuidString, taskId: taskId, date: date,
                      status: .skipped, counted: false,
                      createdAt: date + " 00:00:00")
    }

    /// "Fail" still counts as done → the streak is unbroken
    func testFailedStillCountsTowardStreak() {
        let task = dailyTask()
        let records = [
            rec("t1", day(0), counted: false),   // status manually changed to failed after construction
            rec("t1", day(-1), counted: true),
            rec("t1", day(-2), counted: true)
        ]
        let withFailed = records.map { r -> CheckinRecord in
            var c = r
            if r.date == day(0) { c.status = .failed; c.counted = true }
            return c
        }
        XCTAssertEqual(StreakUtil.computeStreak(task: task, records: withFailed), 3,
                       "没过关但 counted=true，应照样计入连续天数")
    }

    // MARK: - Non-daily tasks

    func testNonDailyReturnsZero() {
        let weekly = CheckinCore.Task(id: "t1", name: "周", type: .weekly, acceptanceRequired: false,
                              targetCount: 3, createdAt: "2026-01-01 00:00:00")
        let records = [rec("t1", day(0), counted: true), rec("t1", day(-1), counted: true)]
        XCTAssertEqual(StreakUtil.computeStreak(task: weekly, records: records), 0)
    }

    func testSpecificDateReturnsZero() {
        let sd = CheckinCore.Task(id: "t1", name: "指定", type: .specificDate, acceptanceRequired: false,
                          createdAt: "2026-01-01 00:00:00")
        let records = [rec("t1", day(0), counted: true)]
        XCTAssertEqual(StreakUtil.computeStreak(task: sd, records: records), 0)
    }

    // MARK: - Empty records

    func testEmptyRecords() {
        XCTAssertEqual(StreakUtil.computeStreak(task: dailyTask(), records: []), 0)
    }

    // MARK: - Streak including today

    func testConsecutiveIncludingToday() {
        let records = [rec("t1", day(0), counted: true),
                       rec("t1", day(-1), counted: true),
                       rec("t1", day(-2), counted: true)]
        XCTAssertEqual(StreakUtil.computeStreak(task: dailyTask(), records: records), 3)
    }

    func testConsecutiveFive() {
        let records = (0...4).map { rec("t1", day(-$0), counted: true) }
        XCTAssertEqual(StreakUtil.computeStreak(task: dailyTask(), records: records), 5)
    }

    // MARK: - Breaks reset to the recent segment

    func testBreakResetsToRecentSegment() {
        // Today and yesterday consecutive, the day before missing, an earlier record (4 days ago)
        // → only the most recent segment counts
        let records = [rec("t1", day(0), counted: true),
                       rec("t1", day(-1), counted: true),
                       rec("t1", day(-4), counted: true)]
        XCTAssertEqual(StreakUtil.computeStreak(task: dailyTask(), records: records), 2)
    }

    func testBreakAtToday() {
        // Record today, missing yesterday, exists the day before → streak of only 1
        let records = [rec("t1", day(0), counted: true),
                       rec("t1", day(-2), counted: true)]
        XCTAssertEqual(StreakUtil.computeStreak(task: dailyTask(), records: records), 1)
    }

    // MARK: - Today missing → starts from yesterday

    func testStartFromYesterdayWhenTodayMissing() {
        let records = [rec("t1", day(-1), counted: true),
                       rec("t1", day(-2), counted: true),
                       rec("t1", day(-3), counted: true)]
        XCTAssertEqual(StreakUtil.computeStreak(task: dailyTask(), records: records), 3,
                       "今日无 counted 记录应从昨天起算连续")
    }

    // MARK: - Only counted records

    func testAwaitingNotCounted() {
        // Today has a single awaiting (counted=false) record
        let records = [rec("t1", day(0), counted: false)]
        XCTAssertEqual(StreakUtil.computeStreak(task: dailyTask(), records: records), 0,
                       "awaiting 不计连续")
    }

    func testMixedCountedAndAwaiting() {
        // Today completed, yesterday awaiting (not counted), the day before completed
        let records = [rec("t1", day(0), counted: true),
                       rec("t1", day(-1), counted: false),
                       rec("t1", day(-2), counted: true)]
        XCTAssertEqual(StreakUtil.computeStreak(task: dailyTask(), records: records), 1,
                       "昨天 awaiting 中断，今天仅 1")
    }

    // MARK: - Other-task isolation

    func testOtherTaskIsolated() {
        let records = [rec("other", day(0), counted: true),
                       rec("other", day(-1), counted: true),
                       rec("other", day(-2), counted: true)]
        XCTAssertEqual(StreakUtil.computeStreak(task: dailyTask("t1"), records: records), 0,
                       "其他任务的记录不应计入本任务连续天数")
    }

    func testMultipleTasksIndependent() {
        let records = [rec("t1", day(0), counted: true),
                       rec("t1", day(-1), counted: true),
                       rec("t2", day(0), counted: true),
                       rec("t2", day(-1), counted: true),
                       rec("t2", day(-2), counted: true)]
        XCTAssertEqual(StreakUtil.computeStreak(task: dailyTask("t1"), records: records), 2)
        XCTAssertEqual(StreakUtil.computeStreak(task: dailyTask("t2"), records: records), 3)
    }

    // MARK: - Single-day exemption (skipped days crossed)

    /// Skipped days are crossed directly: the streak is neither reduced nor broken.
    func testStreakSkipsOverSkippedDay() {
        // d-3 done, d-2 skipped, d-1 done, today done → streak 3
        // (a skipped day neither occupies a slot nor breaks the chain)
        let records = [rec("t1", day(0), counted: true),
                       rec("t1", day(-1), counted: true),
                       rec("t1", day(-3), counted: true),
                       skipRec("t1", day(-2))]
        XCTAssertEqual(StreakUtil.computeStreak(task: dailyTask(), records: records), 3)
    }

    /// All skipped days, no completions → streak 0 (skip ≠ done).
    func testOnlySkippedDaysGivesZeroStreak() {
        let records = [skipRec("t1", day(0)), skipRec("t1", day(-1))]
        XCTAssertEqual(StreakUtil.computeStreak(task: dailyTask(), records: records), 0)
    }
}
