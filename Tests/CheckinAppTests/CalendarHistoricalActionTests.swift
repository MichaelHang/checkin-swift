import XCTest
import SwiftData
import CheckinCore
@testable import CheckinApp

/// Regression lock for "historical days are actionable" on the calendar.
///
/// The one serious correctness risk after opening historical days (user-requested backfill):
/// the view model actions' `refDate` could silently default to today. If the calendar omitted
/// `refDate: selected`, tapping a button on a historical day would record the entry **to today**.
/// The error is invisible in the UI (buttons work, records appear) and only quietly skews stats,
/// so tests must lock "the record lands on the selected day".
///
/// Also locks `CalendarDayPolicy` (future days read-only) and badge semantics — these were
/// `private` computed properties inside Views and unassertable directly, hence pure functions
/// verified here.
@MainActor
final class CalendarHistoricalActionTests: XCTestCase {

    // MARK: - Fixtures

    /// Same as BackupTests: temporary on-disk store + migration plan (exercises the real schema path)
    private func makeContainer() throws -> ModelContainer {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkin-refdate-\(UUID().uuidString).store")
        let schema = Schema([PersistedTask.self, PersistedCheckinRecord.self])
        let config = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(
            for: schema,
            migrationPlan: CheckinMigrationPlan.self,
            configurations: [config]
        )
    }

    private func date(_ ymd: String) -> Date { DateUtil.parseLocalDate(ymd)! }

    private var todayKey: String { DateUtil.localDate(DateUtil.now()) }

    /// Persists a task and returns its value-type copy
    private func seed(_ container: ModelContainer,
                      id: String,
                      acceptanceRequired: Bool = false) -> Task {
        let task = Task(id: id, name: "补记用例",
                        type: .daily,
                        acceptanceRequired: acceptanceRequired,
                        createdAt: "2026-09-01 09:00:00")
        CheckinRepository(modelContext: container.mainContext).addTask(task)
        return task
    }

    private func records(_ container: ModelContainer, taskId: String) -> [CheckinRecord] {
        CheckinRepository(modelContext: container.mainContext)
            .fetchRecords(taskId: taskId)
            .map { $0.toValue }
    }

    // MARK: - complete: on a historical day → the record must land on that day

    func testCompleteOnHistoricalDayWritesRecordToThatDay() throws {
        let container = try makeContainer()
        let task = seed(container, id: "hist-complete")
        let vm = TaskViewModel()
        let historical = "2026-09-03"                              // historical backfill day

        vm.complete(task, refDate: date(historical), context: container.mainContext)

        let recs = records(container, taskId: "hist-complete")
        XCTAssertEqual(recs.count, 1, "应只产生 1 条记录")
        XCTAssertEqual(recs.first?.date, historical, "历史日打卡必须落在历史日，而不是今天")
        XCTAssertNotEqual(recs.first?.date, todayKey, "绝不能误记到今天（漏传 refDate 的典型症状）")
        XCTAssertEqual(recs.first?.status, .passed, "acceptanceRequired=false → 打卡即过关")
        XCTAssertTrue(recs.first?.counted ?? false, "打卡即计入完成")
    }

    /// Key invariant: acting on a historical day must leave **no trace on today**
    /// (asserts via the View-equivalent `statusOf`, i.e. re-checks from the UI's perspective)
    func testCompleteOnHistoricalDayLeavesTodayUntouched() throws {
        let container = try makeContainer()
        let task = seed(container, id: "hist-untouched")
        let vm = TaskViewModel()
        let historical = "2026-09-03"

        vm.complete(task, refDate: date(historical), context: container.mainContext)

        let recs = records(container, taskId: "hist-untouched")
        XCTAssertEqual(vm.statusOf(task, records: recs, date: historical), .passed,
                       "历史日应显示为已完成")
        XCTAssertEqual(vm.statusOf(task, records: recs, date: todayKey), .pending,
                       "今天应仍是未完成 —— 记录没有被串到今天")
    }

    /// User-requested scenario: "backfilling Monday's done from Thursday must count as Monday's" —
    /// a backfill day may precede the task's creation day. The state machine does not validate
    /// createdAt (that is the expected-slot metric's concern); this locks that the App layer
    /// will not rewrite the date.
    func testCompleteOnDayBeforeTaskCreationWritesToThatBackdatedDay() throws {
        let container = try makeContainer()
        let task = Task(id: "hist-backdated", name: "补记用例", type: .daily,
                        acceptanceRequired: false, createdAt: "2026-09-08 09:00:00")
        CheckinRepository(modelContext: container.mainContext).addTask(task)
        let vm = TaskViewModel()

        vm.complete(task, refDate: date("2026-09-03"), context: container.mainContext)

        let recs = records(container, taskId: "hist-backdated")
        XCTAssertEqual(recs.first?.date, "2026-09-03", "早于创建日的补记也必须落在补记日")
        XCTAssertNotEqual(recs.first?.date, todayKey)
    }

    // MARK: - pass / fail: judging on a historical day still targets that day

    func testPassOnHistoricalDayJudgesThatDaysRecord() throws {
        let container = try makeContainer()
        // acceptance required → complete lands in .awaiting
        let task = seed(container, id: "hist-pass", acceptanceRequired: true)
        let vm = TaskViewModel()
        let historical = "2026-09-03"

        vm.complete(task, refDate: date(historical), context: container.mainContext)
        XCTAssertEqual(records(container, taskId: "hist-pass").first?.status, .awaiting)

        vm.pass(task, refDate: date(historical), context: container.mainContext)

        let recs = records(container, taskId: "hist-pass")
        XCTAssertEqual(recs.count, 1, "判定是就地翻转，不应新增记录")
        XCTAssertEqual(recs.first?.date, historical, "判定必须作用于历史日那条记录")
        XCTAssertEqual(recs.first?.status, .passed)
        XCTAssertTrue(recs.first?.counted ?? false, "过关要计入完成")
        XCTAssertEqual(vm.statusOf(task, records: recs, date: todayKey), .pending,
                       "今天不应被判定影响")
    }

    func testFailOnHistoricalDayJudgesThatDaysRecord() throws {
        let container = try makeContainer()
        let task = seed(container, id: "hist-fail", acceptanceRequired: true)
        let vm = TaskViewModel()
        let historical = "2026-09-03"

        vm.complete(task, refDate: date(historical), context: container.mainContext)
        vm.fail(task, refDate: date(historical), context: container.mainContext)

        let recs = records(container, taskId: "hist-fail")
        XCTAssertEqual(recs.first?.date, historical)
        XCTAssertEqual(recs.first?.status, .failed)
        XCTAssertTrue(recs.first?.counted ?? false, "没过关也算完成")
    }

    // MARK: - revoke: removes only that day, never today

    func testRevokeOnHistoricalDayRemovesOnlyThatDay() throws {
        let container = try makeContainer()
        let task = seed(container, id: "hist-revoke")
        let vm = TaskViewModel()

        vm.complete(task, refDate: date("2026-09-02"), context: container.mainContext)
        vm.complete(task, refDate: date("2026-09-03"), context: container.mainContext)
        XCTAssertEqual(records(container, taskId: "hist-revoke").count, 2)

        vm.revoke(task, refDate: date("2026-09-03"), context: container.mainContext)

        let recs = records(container, taskId: "hist-revoke")
        XCTAssertEqual(recs.count, 1, "撤销只应删掉 09-03 那条")
        XCTAssertEqual(recs.first?.date, "2026-09-02", "09-02 那条必须完好")
    }

    // MARK: - Today: the default path must not break

    func testCompleteOnTodayStillWritesTodayRecord() throws {
        let container = try makeContainer()
        let task = seed(container, id: "today-complete")
        let vm = TaskViewModel()

        vm.complete(task, refDate: DateUtil.now(), context: container.mainContext)

        let recs = records(container, taskId: "today-complete")
        XCTAssertEqual(recs.first?.date, todayKey, "今天打卡仍应记到今天")
    }

    // MARK: - CalendarDayPolicy: future days read-only + badge semantics

    func testCanActAllowsTodayAndPastButBlocksFuture() {
        let now = date("2026-09-09")
        XCTAssertTrue(CalendarDayPolicy.canAct(selected: date("2026-09-09"), now: now),
                      "今天可操作")
        XCTAssertTrue(CalendarDayPolicy.canAct(selected: date("2026-09-08"), now: now),
                      "历史日可操作（补记）")
        XCTAssertTrue(CalendarDayPolicy.canAct(selected: date("2026-08-01"), now: now),
                      "更早的历史日同样可操作")
        XCTAssertFalse(CalendarDayPolicy.canAct(selected: date("2026-09-10"), now: now),
                       "明天必须只读 —— 否则会写出「未来已完成」")
        XCTAssertFalse(CalendarDayPolicy.canAct(selected: date("2026-10-01"), now: now),
                       "更远的未来同样只读")
    }

    func testIsFutureAndIsTodayBoundaries() {
        let now = date("2026-09-09")
        XCTAssertFalse(CalendarDayPolicy.isFuture(date("2026-09-09"), now: now), "今天不算未来")
        XCTAssertFalse(CalendarDayPolicy.isFuture(date("2026-09-08"), now: now), "过去不算未来")
        XCTAssertTrue(CalendarDayPolicy.isFuture(date("2026-09-10"), now: now), "明天是未来")

        XCTAssertTrue(CalendarDayPolicy.isToday(date("2026-09-09"), now: now))
        XCTAssertFalse(CalendarDayPolicy.isToday(date("2026-09-08"), now: now))
        XCTAssertFalse(CalendarDayPolicy.isToday(date("2026-09-10"), now: now))
    }

    func testBadgeSemanticsByDayKind() {
        let now = date("2026-09-09")
        XCTAssertNil(CalendarDayPolicy.badge(selected: date("2026-09-09"), now: now),
                     "今天不显示徽标")
        XCTAssertEqual(CalendarDayPolicy.badge(selected: date("2026-09-08"), now: now), "补记",
                       "历史日 → 补记")
        XCTAssertEqual(CalendarDayPolicy.badge(selected: date("2026-09-10"), now: now), "未到",
                       "未来日 → 未到")
    }

    /// Bug B lock: future days must be read-only, otherwise "completed in the future" pollution
    /// records get written. The rule is shared by CalendarView and TaskDetailView, so it must be
    /// locked on a pure function outside the Views.
    func testCalendarDayPolicyCanActBlocksFuture() {
        let now = date("2026-09-09")
        XCTAssertTrue(CalendarDayPolicy.canAct(selected: date("2026-09-09"), now: now), "今天可操作")
        XCTAssertTrue(CalendarDayPolicy.canAct(selected: date("2026-09-07"), now: now),
                      "历史日可操作（用户明确要求放开）")
        XCTAssertFalse(CalendarDayPolicy.canAct(selected: date("2026-09-10"), now: now),
                       "未来日不可操作")
    }

    // MARK: - Single-day exemption (skip): future days can be skipped / restored

    /// Local date string offset N days from today (negative = past).
    private func offsetDay(_ days: Int) -> String {
        let d = Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: Date())!
        return DateUtil.localDate(d)
    }

    /// Skip on a future day → the record lands on the future day with counted=false and status=.skipped.
    func testSkipOnFutureDayWritesFutureRecord() throws {
        let container = try makeContainer()
        let task = seed(container, id: "future-skip")
        let vm = TaskViewModel()
        let target = offsetDay(3)                      // future day

        vm.skip(task, refDate: date(target), context: container.mainContext)

        let recs = records(container, taskId: "future-skip")
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs.first?.date, target, "跳过记录必须落在未来日，而不是今天")
        XCTAssertEqual(recs.first?.status, .skipped)
        XCTAssertFalse(recs.first?.counted ?? true, "跳过不计入完成")
        XCTAssertEqual(vm.statusOf(task, records: recs, date: target), .skipped)
    }

    /// Locks "trap A": a future-day skip must be restorable — if restore also went through canAct
    /// it would be blocked, with no way to revoke.
    func testRevokeRemovesFutureSkip() throws {
        let container = try makeContainer()
        let task = seed(container, id: "future-revoke")
        let vm = TaskViewModel()
        let target = offsetDay(3)

        vm.skip(task, refDate: date(target), context: container.mainContext)
        XCTAssertEqual(records(container, taskId: "future-revoke").count, 1)

        vm.revoke(task, refDate: date(target), context: container.mainContext)
        XCTAssertEqual(records(container, taskId: "future-revoke").count, 0,
                       "陷阱 A：未来日跳过必须能恢复（revoke 不经 canAct）")
    }

    func testCanSkipAllowsPastTodayFuture() {
        let now = date("2026-09-09")
        XCTAssertTrue(CalendarDayPolicy.canSkip(selected: date("2026-09-08"), now: now), "历史日可跳过")
        XCTAssertTrue(CalendarDayPolicy.canSkip(selected: date("2026-09-09"), now: now), "今天可跳过")
        XCTAssertTrue(CalendarDayPolicy.canSkip(selected: date("2026-09-10"), now: now), "未来日也可跳过")
        XCTAssertTrue(CalendarDayPolicy.canSkip(selected: date("2026-10-01"), now: now))
    }

    /// Regression lock: canAct behavior must not change with the addition of canSkip — future-day check-ins stay read-only.
    func testCanActStillBlocksFuture() {
        let now = date("2026-09-09")
        XCTAssertTrue(CalendarDayPolicy.canAct(selected: date("2026-09-09"), now: now))
        XCTAssertTrue(CalendarDayPolicy.canAct(selected: date("2026-09-07"), now: now))
        XCTAssertFalse(CalendarDayPolicy.canAct(selected: date("2026-09-10"), now: now),
                       "canAct 行为不得改动：未来日打卡仍只读")
        XCTAssertTrue(CalendarDayPolicy.canSkip(selected: date("2026-09-10"), now: now),
                      "canSkip 恒 true 与 canAct 互不影响")
    }
}
