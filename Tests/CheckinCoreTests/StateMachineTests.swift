import XCTest
import CheckinCore

/// StateMachine boundary tests: judging (pass / fail) before-and-after counting / same-day override /
/// pass / fail / revoke / immutability (returns a new array) / periodKey passthrough for period tasks.
/// The original 4 minimal tests are kept; the rest are QA additions.
final class StateMachineTests: XCTestCase {

    private func makeTask(acceptance: Bool, type: TaskType = .daily, targetCount: Int? = nil) -> CheckinCore.Task {
        CheckinCore.Task(id: "t1", name: "x", type: type, acceptanceRequired: acceptance,
             targetCount: targetCount, createdAt: "2026-03-17 00:00:00")
    }

    private func ref(_ ymd: String) -> Date {
        DateUtil.parseLocalDate(ymd)!
    }

    // MARK: - Original tests (kept)

    func testCompleteNoAcceptance() {
        let task = makeTask(acceptance: false)
        let recs = StateMachine.applyAction(task: task, records: [], action: .complete, refDate: ref("2026-03-17"))
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].status, .passed)
        XCTAssertTrue(recs[0].counted)
        XCTAssertEqual(recs[0].date, "2026-03-17")
    }

    func testCompleteWithAcceptance() {
        let task = makeTask(acceptance: true)
        let recs = StateMachine.applyAction(task: task, records: [], action: .complete, refDate: ref("2026-03-17"))
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].status, .awaiting)
        XCTAssertTrue(recs[0].counted, "需过关任务点击完成即计入完成")
        XCTAssertTrue(recs[0].status.isDone, "点击完成即算完成")
    }

    func testSameDayOverride() {
        let task = makeTask(acceptance: false)
        var recs = StateMachine.applyAction(task: task, records: [], action: .complete, refDate: ref("2026-03-17"))
        recs = StateMachine.applyAction(task: task, records: recs, action: .complete, refDate: ref("2026-03-17"))
        XCTAssertEqual(recs.count, 1, "同日重复 complete 应覆盖而非新增")
    }

    func testPassAndRevoke() {
        let task = makeTask(acceptance: true)
        var recs = StateMachine.applyAction(task: task, records: [], action: .complete, refDate: ref("2026-03-17"))
        recs = StateMachine.applyAction(task: task, records: recs, action: .pass, refDate: ref("2026-03-17"))
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].status, .passed)
        XCTAssertTrue(recs[0].counted)

        recs = StateMachine.applyAction(task: task, records: recs, action: .revoke, refDate: ref("2026-03-17"))
        XCTAssertEqual(recs.count, 0, "revoke 应删除当天记录")
    }

    func testFailCountsAsDone() {
        // Completion counts immediately (counted=true); "fail" is still done: status=.failed with counted=true
        let task = makeTask(acceptance: true)
        var recs = StateMachine.applyAction(task: task, records: [], action: .complete, refDate: ref("2026-03-17"))
        XCTAssertTrue(recs[0].counted, "点击完成即计入完成")
        recs = StateMachine.applyAction(task: task, records: recs, action: .fail, refDate: ref("2026-03-17"))
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].status, .failed)
        XCTAssertTrue(recs[0].counted, "没过关也要计入完成")
        XCTAssertTrue(recs[0].status.isDone)
    }

    func testPassAndFailOnlyFlipAwaiting() {
        // pass / fail only flip that day's .awaiting record; other statuses are kept as-is
        let task = makeTask(acceptance: true)
        let already = CheckinRecord(id: "c1", taskId: "t1", date: "2026-03-17", status: .passed, counted: true, createdAt: "2026-03-17 08:00:00")
        let awaiting = CheckinRecord(id: "a1", taskId: "t1", date: "2026-03-17", status: .awaiting, counted: false, createdAt: "2026-03-17 09:00:00")
        let judged = StateMachine.applyAction(task: task, records: [already, awaiting], action: .fail, refDate: ref("2026-03-17"))
        XCTAssertEqual(judged.first { $0.id == "a1" }?.status, .failed)
        XCTAssertEqual(judged.first { $0.id == "c1" }?.status, .passed, "已判定的记录不应被再次改写")
    }

    // MARK: - Immutability

    func testInputNotMutated() {
        // The input records must not be modified; applyAction must return a new array
        let task = makeTask(acceptance: false)
        let original: [CheckinRecord] = [
            CheckinRecord(id: "r0", taskId: "t1", date: "2026-03-16", status: .passed, counted: true, createdAt: "2026-03-16 00:00:00")
        ]
        let before = original
        _ = StateMachine.applyAction(task: task, records: before, action: .complete, refDate: ref("2026-03-17"))
        XCTAssertEqual(original.count, 1, "入参 records 不应被原地修改")
        XCTAssertEqual(original[0].id, "r0")
    }

    func testPassReturnsNewInstance() {
        let task = makeTask(acceptance: true)
        let recs = StateMachine.applyAction(task: task, records: [], action: .complete, refDate: ref("2026-03-17"))
        let judged = StateMachine.applyAction(task: task, records: recs, action: .pass, refDate: ref("2026-03-17"))
        XCTAssertEqual(recs[0].status, .awaiting, "原数组不应被改变（pass 返回新数组）")
        XCTAssertEqual(judged[0].status, .passed)
        XCTAssertNotEqual(judged, recs, "pass 应返回内容不同的新数组")
    }

    // MARK: - Period task periodKey passthrough

    func testWeeklyCompleteCarriesPeriodKey() {
        let task = makeTask(acceptance: false, type: .weekly, targetCount: 3)
        let recs = StateMachine.applyAction(task: task, records: [], action: .complete, refDate: ref("2026-07-20"))
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].periodKey, "2026-W30")
        XCTAssertTrue(recs[0].counted)
    }

    func testWeeklyWithAcceptancePeriodKeyPreservedThroughPass() {
        let task = makeTask(acceptance: true, type: .weekly, targetCount: 3)
        var recs = StateMachine.applyAction(task: task, records: [], action: .complete, refDate: ref("2026-07-20"))
        XCTAssertEqual(recs[0].periodKey, "2026-W30")
        XCTAssertTrue(recs[0].counted, "需过关周期任务点击完成即计入完成")
        recs = StateMachine.applyAction(task: task, records: recs, action: .pass, refDate: ref("2026-07-20"))
        XCTAssertEqual(recs[0].periodKey, "2026-W30", "判定后应保留 periodKey")
        XCTAssertTrue(recs[0].counted)
    }

    func testSpecificDateNoPeriodKey() {
        let task = makeTask(acceptance: false, type: .specificDate)
        let recs = StateMachine.applyAction(task: task, records: [], action: .complete, refDate: ref("2026-07-20"))
        XCTAssertNil(recs[0].periodKey)
    }

    // MARK: - Same-day override + period

    func testSameDayOverrideWeeklyKeepsPeriodKey() {
        let task = makeTask(acceptance: false, type: .weekly, targetCount: 3)
        var recs = StateMachine.applyAction(task: task, records: [], action: .complete, refDate: ref("2026-07-20"))
        recs = StateMachine.applyAction(task: task, records: recs, action: .complete, refDate: ref("2026-07-20"))
        XCTAssertEqual(recs.count, 1, "同日重复 complete 应覆盖")
        XCTAssertEqual(recs[0].periodKey, "2026-W30")
    }

    // MARK: - pass / fail only affect awaiting

    func testPassOnlyFlipsAwaiting() {
        let task = makeTask(acceptance: true)
        // One already-judged passed and one awaiting on the same day; verifies pass flips only the awaiting
        let already = CheckinRecord(id: "c1", taskId: "t1", date: "2026-03-17", status: .passed, counted: true, createdAt: "2026-03-17 08:00:00")
        let awaiting = CheckinRecord(id: "a1", taskId: "t1", date: "2026-03-17", status: .awaiting, counted: false, createdAt: "2026-03-17 09:00:00")
        let judged = StateMachine.applyAction(task: task, records: [already, awaiting], action: .pass, refDate: ref("2026-03-17"))
        let doneOnes = judged.filter { $0.status.isDone && $0.counted }
        XCTAssertEqual(doneOnes.count, 2, "pass 应把 awaiting 翻为 passed，已判定的记录保持不变")
    }

    // MARK: - revoke removes only that task's record for the day

    func testRevokeOnlySameDayTask() {
        let task = makeTask(acceptance: false)
        let other = CheckinRecord(id: "o1", taskId: "other", date: "2026-03-17", status: .passed, counted: true, createdAt: "2026-03-17 00:00:00")
        var recs: [CheckinRecord] = [other]
        recs = StateMachine.applyAction(task: task, records: recs, action: .complete, refDate: ref("2026-03-17"))
        recs = StateMachine.applyAction(task: task, records: recs, action: .revoke, refDate: ref("2026-03-17"))
        XCTAssertEqual(recs.count, 1, "revoke 只删除本任务当天记录，另一任务记录应保留")
        XCTAssertEqual(recs[0].taskId, "other")
    }

    func testRevokeDifferentDayKept() {
        let task = makeTask(acceptance: false)
        var recs = StateMachine.applyAction(task: task, records: [], action: .complete, refDate: ref("2026-03-16"))
        recs = StateMachine.applyAction(task: task, records: recs, action: .complete, refDate: ref("2026-03-17"))
        XCTAssertEqual(recs.count, 2)
        recs = StateMachine.applyAction(task: task, records: recs, action: .revoke, refDate: ref("2026-03-17"))
        XCTAssertEqual(recs.count, 1, "revoke 只删 refDate 当天，前一天保留")
        XCTAssertEqual(recs[0].date, "2026-03-16")
    }

    // MARK: - Historical-day judging (fixes "a prior day's check-in had nowhere to be judged")

    /// Calling pass with a historical-day refDate must flip only that day's awaiting; today's record is untouched.
    func testJudgePastDayAwaitingKeepsTodayUntouched() {
        let task = makeTask(acceptance: true)
        let yesterday = CheckinRecord(id: "y1", taskId: "t1", date: "2026-03-16",
                                      status: .awaiting, counted: false, createdAt: "2026-03-16 20:00:00")
        let today = CheckinRecord(id: "t1", taskId: "t1", date: "2026-03-17",
                                  status: .passed, counted: true, createdAt: "2026-03-17 08:00:00")
        let judged = StateMachine.applyAction(task: task, records: [yesterday, today],
                                              action: .pass, refDate: ref("2026-03-16"))
        XCTAssertEqual(judged.first { $0.id == "y1" }?.status, .passed, "历史日 awaiting 应被判定为 passed")
        XCTAssertTrue(judged.first { $0.id == "y1" }?.counted ?? false, "过关要计入完成")
        XCTAssertEqual(judged.first { $0.id == "t1" }?.status, .passed, "今天的记录不应被动")
    }

    /// Failing a historical day's awaiting likewise flips only that day, with counted=true.
    func testJudgePastDayAwaitingFailCounts() {
        let task = makeTask(acceptance: true)
        let yesterday = CheckinRecord(id: "y1", taskId: "t1", date: "2026-03-16",
                                      status: .awaiting, counted: false, createdAt: "2026-03-16 20:00:00")
        let judged = StateMachine.applyAction(task: task, records: [yesterday],
                                              action: .fail, refDate: ref("2026-03-16"))
        XCTAssertEqual(judged.first { $0.id == "y1" }?.status, .failed)
        XCTAssertTrue(judged.first { $0.id == "y1" }?.counted ?? false, "没过关也算完成")
        XCTAssertEqual(judged.first { $0.id == "y1" }?.date, "2026-03-16", "记录应留在原日期而非今天")
    }

    /// Reproduces the detail page's full "open a historical day in the calendar → tap fail" flow (core layer):
    /// a historical day's complete (→ awaiting); the detail page derives awaiting for that day;
    /// calling fail with that day's refDate must flip it to failed with the record on the **original
    /// day**, not today. TaskDetailView now passes workingDate as that refDate, relying on exactly
    /// this invariant.
    func testDetailHistoricalDayFailFlow() {
        let task = makeTask(acceptance: true)
        let hist = "2026-03-16"
        var recs = StateMachine.applyAction(task: task, records: [], action: .complete, refDate: ref(hist))
        // Equivalent of the detail page's statusOf(date: hist)
        let derived = recs.filter { $0.taskId == task.id && $0.date == hist }.last?.status ?? .pending
        XCTAssertEqual(derived, .awaiting, "历史日详情应显示待判定")
        recs = StateMachine.applyAction(task: task, records: recs, action: .fail, refDate: ref(hist))
        let after = recs.filter { $0.taskId == task.id && $0.date == hist }.last?.status ?? .pending
        XCTAssertEqual(after, .failed, "点没过关应翻为 failed 且落在原日")
        XCTAssertEqual(recs.first { $0.date == hist }?.date, hist, "记录不应误记到今天")
    }

    // MARK: - skip (single-day exemption)

    /// Tapping skip writes a .skipped, counted=false record (skip is not a completion).
    func testSkipCreatesSkippedNotCounted() {
        let task = makeTask(acceptance: false)
        let recs = StateMachine.applyAction(task: task, records: [], action: .skip, refDate: ref("2026-03-17"))
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].status, .skipped)
        XCTAssertFalse(recs[0].counted, "跳过不计入完成")
        XCTAssertEqual(recs[0].date, "2026-03-17")
        XCTAssertFalse(recs[0].status.isDone, "跳过不是完成（isDone 必须为 false）")
    }

    /// Same day: complete then skip → only the skip remains (they override each other).
    func testSkipOverridesComplete() {
        let task = makeTask(acceptance: false)
        var recs = StateMachine.applyAction(task: task, records: [], action: .complete, refDate: ref("2026-03-17"))
        recs = StateMachine.applyAction(task: task, records: recs, action: .skip, refDate: ref("2026-03-17"))
        XCTAssertEqual(recs.count, 1, "同日 skip 覆盖 complete，只应留 1 条")
        XCTAssertEqual(recs[0].status, .skipped)
        XCTAssertFalse(recs[0].counted)
    }

    /// Same day: skip then complete → only the complete remains.
    func testCompleteOverridesSkip() {
        let task = makeTask(acceptance: false)
        var recs = StateMachine.applyAction(task: task, records: [], action: .skip, refDate: ref("2026-03-17"))
        recs = StateMachine.applyAction(task: task, records: recs, action: .complete, refDate: ref("2026-03-17"))
        XCTAssertEqual(recs.count, 1, "同日 complete 覆盖 skip，只应留 1 条")
        XCTAssertEqual(recs[0].status, .passed)
        XCTAssertTrue(recs[0].counted)
    }

    /// revoke acts as "restore": removes the day's skip record, leaving 0 records.
    func testRevokeRemovesSkip() {
        let task = makeTask(acceptance: false)
        var recs = StateMachine.applyAction(task: task, records: [], action: .skip, refDate: ref("2026-03-17"))
        XCTAssertEqual(recs.count, 1)
        recs = StateMachine.applyAction(task: task, records: recs, action: .revoke, refDate: ref("2026-03-17"))
        XCTAssertEqual(recs.count, 0, "revoke 即恢复：删除当天 skip 记录")
    }

    /// A skipped day has no awaiting record → pass / fail are no-ops (the record stays .skipped).
    func testPassFailNoopOnSkippedDay() {
        let task = makeTask(acceptance: true)
        let skipped = CheckinRecord(id: "s1", taskId: "t1", date: "2026-03-17",
                                    status: .skipped, counted: false, createdAt: "2026-03-17 08:00:00")
        let afterPass = StateMachine.applyAction(task: task, records: [skipped], action: .pass, refDate: ref("2026-03-17"))
        XCTAssertEqual(afterPass.count, 1)
        XCTAssertEqual(afterPass.first?.status, .skipped, "跳过日无 awaiting 记录，pass 无副作用")
        let afterFail = StateMachine.applyAction(task: task, records: [skipped], action: .fail, refDate: ref("2026-03-17"))
        XCTAssertEqual(afterFail.first?.status, .skipped, "跳过日无 awaiting 记录，fail 无副作用")
    }

    /// A count-based task's (weekly) skip record carries a periodKey.
    func testSkipWeeklyCarriesPeriodKey() {
        let task = makeTask(acceptance: false, type: .weekly, targetCount: 3)
        let recs = StateMachine.applyAction(task: task, records: [], action: .skip, refDate: ref("2026-07-20"))
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].periodKey, "2026-W30", "次数任务的跳过记录应带 periodKey")
        XCTAssertFalse(recs[0].counted)
    }

    /// A day-level task's (daily) skip record has a nil periodKey.
    func testSkipDailyHasNilPeriodKey() {
        let task = makeTask(acceptance: false, type: .daily)
        let recs = StateMachine.applyAction(task: task, records: [], action: .skip, refDate: ref("2026-07-20"))
        XCTAssertNil(recs[0].periodKey, "单日级跳过 periodKey 为 nil")
    }
}
