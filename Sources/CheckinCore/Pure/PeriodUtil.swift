import Foundation

/// Period task (weekly/monthly) progress and status derivation (pure functions)
public struct PeriodUtil {

    /// done = count of counted==true records for this task + periodKey
    /// target = min(targetCount, available days); available days = period total days − skipped days in the period (whole period, not truncated at now)
    /// target == 0 (whole period skipped) → achieved=false, percent=0, status = .noExpectation
    /// The early return precedes the isPeriodEnded check; its real job is avoiding a 0/0 division and returning .noExpectation.
    /// (With target==0, achieved = (done >= 0) would always be true, so the isPeriodEnded/.failed branch is
    ///  structurally unreachable anyway; the early return's position guards no ordering dependency.)
    /// Otherwise: achieved → .completed; isPeriodEnded → .failed; else .inProgress
    /// percent = min(100, Int((Double(done)/Double(target)*100).rounded())) unless .noExpectation, else 0
    ///
    /// ⚠️ Invariant (caller must guarantee): `periodKey` and `now` must belong to the **same period**.
    /// `done` and `isPeriodEnded` are both judged by `periodKey`, while the available-days window derives
    /// from `now` (weekRange/monthRange(now)). If the two are not the same period (e.g. a historical
    /// period key paired with the current now), "done/ended" and "available days" follow conflicting
    /// criteria and yield contradictory results. No `assert`/`precondition` guard exists — an **unguarded** calling contract.
    ///
    /// To support browsing historical periods later, do **not** mix a historical key with `now`; derive the
    /// window from `periodKey`'s own range instead (consider promoting DateUtil's private `periodKey → range` helper to internal).
    public static func computePeriodProgress(task: Task,
                                             records: [CheckinRecord],
                                             periodKey: String,
                                             now: Date) -> PeriodProgress {
        let done = records.filter {
            $0.taskId == task.id && $0.periodKey == periodKey && $0.counted
                && (task.endDate == nil || $0.date <= task.endDate!)
        }.count

        // Derive the period range from now (whole period: weekly = one week / monthly = full month), for the available-days criteria.
        let periodStart: Date
        let periodEnd: Date
        let totalDays: Int
        switch task.type {
        case .weekly:
            let range = DateUtil.weekRange(now)
            periodStart = range.start
            periodEnd = range.end
            totalDays = 7
        case .monthly:
            let range = DateUtil.monthRange(now)
            periodStart = range.start
            periodEnd = range.end
            let c = DateUtil.components(now)
            totalDays = DateUtil.daysInMonth(year: c.year, month: c.month)
        default:
            periodStart = now
            periodEnd = now
            totalDays = 0
        }
        let startKey = DateUtil.localDate(periodStart)
        let endKey = DateUtil.localDate(periodEnd)
        let skipped = StatsUtil.skippedDayCount(taskId: task.id, records: records,
                                                fromKey: startKey, toKey: endKey)
        let availableDays = max(0, totalDays - skipped)
        let target = min(task.targetCount ?? 0, availableDays)

        // No available days: express "nothing expected this week/month" as a distinct status instead of falling through to .failed.
        if target == 0 {
            return PeriodProgress(done: done, target: 0, percent: 0,
                                  achieved: false, status: .noExpectation)
        }

        let achieved = done >= target
        let percent = min(100, Int((Double(done) / Double(target) * 100).rounded()))

        let status: PeriodStatus
        if achieved {
            status = .completed
        } else if DateUtil.isPeriodEnded(type: task.type, key: periodKey, now: now) {
            status = .failed
        } else {
            status = .inProgress
        }

        return PeriodProgress(done: done, target: target, percent: percent,
                              achieved: achieved, status: status)
    }
}
