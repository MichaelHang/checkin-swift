import XCTest
import CheckinCore

/// PeriodUtil.computePeriodProgress boundary tests:
/// done counting rules (counted only + periodKey match + taskId match) / achieved / percent (33·67·100 capped)
/// / status (inProgress / completed / failed) / target=0 does not crash.
final class PeriodUtilTests: XCTestCase {

    private func task(target: Int) -> CheckinCore.Task {
        CheckinCore.Task(id: "t1", name: "周任务", type: .weekly, acceptanceRequired: false,
             targetCount: target, createdAt: "2026-07-20 00:00:00")
    }

    private func taskWithEndDate(target: Int, endDate: String) -> CheckinCore.Task {
        CheckinCore.Task(id: "t1", name: "周任务", type: .weekly, acceptanceRequired: false,
             targetCount: target, endDate: endDate, createdAt: "2026-07-20 00:00:00")
    }

    private func rec(_ taskId: String, _ periodKey: String, counted: Bool, id: String = UUID().uuidString) -> CheckinRecord {
        CheckinRecord(id: id, taskId: taskId, date: "2026-07-20", status: counted ? .passed : .awaiting,
                      periodKey: periodKey, counted: counted, createdAt: "2026-07-20 00:00:00")
    }

    private func now(_ ymd: String) -> Date { DateUtil.parseLocalDate(ymd)! }

    // MARK: - done counting rules

    func testDoneCountsOnlyCounted() {
        // Two counted + one uncounted (awaiting)
        let records = [
            rec("t1", "2026-W30", counted: true),
            rec("t1", "2026-W30", counted: true),
            rec("t1", "2026-W30", counted: false)
        ]
        let p = PeriodUtil.computePeriodProgress(task: task(target: 3), records: records, periodKey: "2026-W30", now: now("2026-07-20"))
        XCTAssertEqual(p.done, 2)
    }

    func testDoneIgnoresOtherPeriodKey() {
        let records = [
            rec("t1", "2026-W30", counted: true),
            rec("t1", "2026-W29", counted: true), // different period: not counted
            rec("t2", "2026-W30", counted: true)  // different task: not counted
        ]
        let p = PeriodUtil.computePeriodProgress(task: task(target: 3), records: records, periodKey: "2026-W30", now: now("2026-07-20"))
        XCTAssertEqual(p.done, 1)
    }

    func testDoneSameTaskDifferentPeriodNotMixed() {
        let records = [
            rec("t1", "2026-W30", counted: true),
            rec("t1", "2026-W29", counted: true),
            rec("t1", "2026-W28", counted: true)
        ]
        let p = PeriodUtil.computePeriodProgress(task: task(target: 3), records: records, periodKey: "2026-W30", now: now("2026-07-20"))
        XCTAssertEqual(p.done, 1, "同任务不同 periodKey 不应串")
    }

    // MARK: - achieved / status

    func testAchievedWhenDoneEqualsTarget() {
        let records = [rec("t1", "2026-W30", counted: true), rec("t1", "2026-W30", counted: true), rec("t1", "2026-W30", counted: true)]
        let p = PeriodUtil.computePeriodProgress(task: task(target: 3), records: records, periodKey: "2026-W30", now: now("2026-07-20"))
        XCTAssertTrue(p.achieved)
        XCTAssertEqual(p.status, .completed)
        XCTAssertEqual(p.done, 3)
        XCTAssertEqual(p.target, 3)
    }

    func testStatusInProgressWhenWithinAndNotAchieved() {
        let records = [rec("t1", "2026-W30", counted: true)]
        let p = PeriodUtil.computePeriodProgress(task: task(target: 3), records: records, periodKey: "2026-W30", now: now("2026-07-20"))
        XCTAssertFalse(p.achieved)
        XCTAssertEqual(p.status, .inProgress)
    }

    func testStatusFailedWhenEndedAndNotAchieved() {
        // 2026-W30 ends 2026-08-02 23:59:59; now=2026-08-10 is past it
        let records = [rec("t1", "2026-W30", counted: true)]
        let p = PeriodUtil.computePeriodProgress(task: task(target: 3), records: records, periodKey: "2026-W30", now: now("2026-08-10"))
        XCTAssertEqual(p.status, .failed, "窗口结束且未达标应判 failed")
    }

    // MARK: - percent

    func testPercentOneThird() {
        let records = [rec("t1", "2026-W30", counted: true)]
        let p = PeriodUtil.computePeriodProgress(task: task(target: 3), records: records, periodKey: "2026-W30", now: now("2026-07-20"))
        XCTAssertEqual(p.percent, 33)
    }

    func testPercentTwoThird() {
        let records = [rec("t1", "2026-W30", counted: true), rec("t1", "2026-W30", counted: true)]
        let p = PeriodUtil.computePeriodProgress(task: task(target: 3), records: records, periodKey: "2026-W30", now: now("2026-07-20"))
        XCTAssertEqual(p.percent, 67)
    }

    func testPercentFull() {
        let records = [rec("t1", "2026-W30", counted: true), rec("t1", "2026-W30", counted: true), rec("t1", "2026-W30", counted: true)]
        let p = PeriodUtil.computePeriodProgress(task: task(target: 3), records: records, periodKey: "2026-W30", now: now("2026-07-20"))
        XCTAssertEqual(p.percent, 100)
    }

    func testPercentCappedAt100WhenOverTarget() {
        let records = (0..<5).map { _ in rec("t1", "2026-W30", counted: true) }
        let p = PeriodUtil.computePeriodProgress(task: task(target: 3), records: records, periodKey: "2026-W30", now: now("2026-07-20"))
        XCTAssertEqual(p.percent, 100, "超过目标应封顶 100")
        XCTAssertTrue(p.achieved)
    }

    func testPercentZeroWhenTargetZero() {
        // target=0 must not crash; percent=0, achieved=false
        let records = [rec("t1", "2026-W30", counted: true)]
        let p = PeriodUtil.computePeriodProgress(task: task(target: 0), records: records, periodKey: "2026-W30", now: now("2026-07-20"))
        XCTAssertEqual(p.percent, 0)
        XCTAssertFalse(p.achieved)
        XCTAssertEqual(p.target, 0)
    }

    func testPercentZeroWhenNoRecords() {
        let p = PeriodUtil.computePeriodProgress(task: task(target: 3), records: [], periodKey: "2026-W30", now: now("2026-07-20"))
        XCTAssertEqual(p.done, 0)
        XCTAssertEqual(p.percent, 0)
        XCTAssertEqual(p.status, .inProgress)
    }

    // MARK: - endDate filtering

    func testProgressExcludesRecordsAfterEndDate() {
        // Weekly task ending 2026-07-22; two counted records in the same period,
        // one inside the window, one after it ends
        let task = taskWithEndDate(target: 3, endDate: "2026-07-22")
        let recInWindow = CheckinRecord(id: "r1", taskId: "t1", date: "2026-07-20",
                                        status: .passed, periodKey: "2026-W30",
                                        counted: true, createdAt: "2026-07-20 00:00:00")
        let recAfterEnd = CheckinRecord(id: "r2", taskId: "t1", date: "2026-07-25",
                                        status: .passed, periodKey: "2026-W30",
                                        counted: true, createdAt: "2026-07-25 00:00:00")
        let p = PeriodUtil.computePeriodProgress(task: task, records: [recInWindow, recAfterEnd],
                                                 periodKey: "2026-W30", now: now("2026-07-25"))
        XCTAssertEqual(p.done, 1, "结束日之后的记录不应计入")
    }

    // MARK: - Single-day exemption (skip): available-days cap / no expected days

    /// Skip record (counted=false, excluded from done; skipped days are tallied by StatsUtil.skippedDayCount)
    private func skip(_ taskId: String, _ ymd: String) -> CheckinRecord {
        CheckinRecord(id: "skip-\(taskId)-\(ymd)", taskId: taskId, date: ymd,
                      status: .skipped, periodKey: nil, counted: false,
                      createdAt: ymd + " 00:00:00")
    }

    /// Target 5, 3 days skipped this week (W30 = 07-20 ~ 07-26) → target = min(5, 7-3) = 4.
    func testEffectiveTargetCappedBySkippedDays() {
        let records = [skip("t1", "2026-07-20"), skip("t1", "2026-07-21"), skip("t1", "2026-07-22"),
                       rec("t1", "2026-W30", counted: true)]
        let p = PeriodUtil.computePeriodProgress(task: task(target: 5), records: records,
                                                 periodKey: "2026-W30", now: now("2026-07-20"))
        XCTAssertEqual(p.target, 4, "min(5, 7-3) = 4")
        XCTAssertEqual(p.done, 1)
    }

    /// The real contract when `target == 0` (available days fully consumed by skips):
    /// **(a) no 0/0 divide-by-zero crash** — without the early return, `Int(Double(done)/Double(0)*100)`
    /// = `Int(NaN)` would fatalError;
    /// **(b) the result must be `.noExpectation`**.
    ///
    /// ⚠️ Signpost for maintainers: this test does **not** (and cannot) lock "the `target == 0` early
    /// return happens before `isPeriodEnded`". When `target == 0`, `achieved = (done >= 0)` is always
    /// true → `status` goes to `.completed` first and **structurally never reaches the
    /// `isPeriodEnded` branch**, so "must not become `.failed`" is trivially true regardless of
    /// ordering. The early return's real load-bearing guarantees are (a) and (b): removing it crashes
    /// on 0/0 and never yields `.noExpectation`. Do **not** "protect" a sequencing dependency that
    /// does not exist.
    ///
    /// Note: the available-days window is by design taken from `now` (see PeriodUtil), so part (2)
    /// uses an already-ended past `periodKey` to build the "period ended + no available days"
    /// combination and asserts it is still `.noExpectation` (also not an ordering lock).
    func testZeroAvailableDaysReturnsNoExpectationWithoutDivideByZero() {
        let nowDate = now("2026-08-10")                        // Monday; this week = 08-10 ~ 08-16
        let days = ["2026-08-10", "2026-08-11", "2026-08-12", "2026-08-13",
                    "2026-08-14", "2026-08-15", "2026-08-16"]
        let records = days.map { skip("t1", $0) }              // all 7 days of the week skipped → 0 available days
        let thisWeekKey = DateUtil.periodKey(type: .weekly, nowDate)! // "2026-W33"

        // (1) Period in progress: target 0 → no available days
        let inProgress = PeriodUtil.computePeriodProgress(task: task(target: 5), records: records,
                                                          periodKey: thisWeekKey, now: nowDate)
        XCTAssertEqual(inProgress.target, 0)
        XCTAssertEqual(inProgress.status, .noExpectation, "整周被跳过 → 无可做天数")
        XCTAssertFalse(inProgress.achieved)
        XCTAssertEqual(inProgress.percent, 0)

        // (2) Pass an already-ended past periodKey: period ended + no available days,
        // result must still be .noExpectation (not an ordering lock)
        let endedKey = "2026-W30"                              // 2026-07-20 ~ 07-26, ended relative to 2026-08-10
        XCTAssertTrue(DateUtil.isPeriodEnded(type: .weekly, key: endedKey, now: nowDate),
                      "前置：该 periodKey 确已结束")
        let ended = PeriodUtil.computePeriodProgress(task: task(target: 5), records: records,
                                                     periodKey: endedKey, now: nowDate)
        XCTAssertEqual(ended.target, 0)
        XCTAssertEqual(ended.status, .noExpectation, "周期已结束但无可做天数 → 仍为 .noExpectation")
    }

    /// PeriodUtil and StatsUtil must agree on the effective target (capped by available days) for
    /// the same scenario (guards against metric drift).
    func testPeriodUtilAndStatsUtilAgreeOnEffectiveTarget() {
        let t = CheckinCore.Task(id: "t1", name: "周任务", type: .weekly, acceptanceRequired: false,
                                 targetCount: 5, createdAt: "2026-07-20 00:00:00")
        let records = [skip("t1", "2026-07-20"), skip("t1", "2026-07-21"), skip("t1", "2026-07-22")]
        let ref = now("2026-07-21")
        let statsTarget = StatsUtil.expectedCount(task: t, records: records, inWeekOf: ref)
        let p = PeriodUtil.computePeriodProgress(task: t, records: records, periodKey: "2026-W30", now: ref)
        XCTAssertEqual(statsTarget, p.target, "两个入口的可做天数口径必须一致（防漂移）")
        XCTAssertEqual(statsTarget, 4, "min(5, 7-3) = 4")
    }
}
