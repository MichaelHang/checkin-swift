import Foundation

/// State machine for daily / specific-date / period tasks (immutable, returns a new array)
///
/// Rules (contract matches the Web version):
/// - complete: any check-in counts as done (counted=true).
///             Review required → insert status=.awaiting (quality pending review, still counts toward streak/period progress);
///             no review required → insert status=.passed;
///             **a repeated complete on the same day overwrites (updates) instead of adding a record**
/// - pass / fail: the task's status=.awaiting record on refDate → .passed / .failed,
///             both with counted=true — **fail still counts as done**, toward streak and period progress
/// - revoke: deletes the task's record on refDate (back to pending) — **also the inverse of restore (un-skip)**
/// - skip: single-day exemption — deletes the task's record on refDate, then writes a status=.skipped, counted=false record
///         (symmetric with complete; count tasks carry `periodKey`, day-level `periodKey=nil`).
///         Same-day skip and complete overwrite each other; pass / fail have no effect on skipped days (no awaiting record that day).
///
/// complete records for period tasks (weekly/monthly) carry `periodKey` (the current period) so
/// PeriodUtil can count per period; pass / fail preserve the periodKey.
public struct StateMachine {

    public static func applyAction(task: Task,
                                   records: [CheckinRecord],
                                   action: TaskAction,
                                   refDate: Date) -> [CheckinRecord] {
        let dateStr = DateUtil.localDate(refDate)
        var result = records

        switch action {
        case .complete:
            // Remove the task's existing record for the day (same-day repeat → overwrite)
            result.removeAll { $0.taskId == task.id && $0.date == dateStr }

            // Any check-in counts as done: review required → awaiting(.awaiting) still counted=true (counts immediately);
            // no review required → directly passed(.passed). pass/fail is only a quality mark, not whether it's done.
            let status: TaskStatus = task.acceptanceRequired ? .awaiting : .passed
            let counted = true
            // Period task records belong to the current period
            let periodKey: String? = (task.type == .weekly || task.type == .monthly)
                ? DateUtil.periodKey(type: task.type, refDate)
                : nil

            let rec = CheckinRecord(
                id: IdUtil.genId(),
                taskId: task.id,
                date: dateStr,
                status: status,
                periodKey: periodKey,
                counted: counted,
                createdAt: DateUtil.isoDateTime(refDate)
            )
            result.append(rec)

        case .pass, .fail:
            // The awaiting record on refDate → passed / failed (periodKey preserved)
            // Both set counted=true: a fail still means "was done", counting toward streak and period progress
            let target: TaskStatus = (action == .pass) ? .passed : .failed
            result = result.map { r in
                guard r.taskId == task.id, r.date == dateStr, r.status == .awaiting else { return r }
                return CheckinRecord(
                    id: r.id,
                    taskId: r.taskId,
                    date: r.date,
                    status: target,
                    periodKey: r.periodKey,
                    counted: true,
                    createdAt: r.createdAt
                )
            }

        case .revoke:
            // Delete the task's record on refDate
            result.removeAll { $0.taskId == task.id && $0.date == dateStr }

        case .skip:
            // Single-day exemption: symmetric with complete — first remove the existing record for the day
            // (same-day skip/complete overwrite each other), then write a .skipped, counted=false record (a skip is not a completion and counts toward no stats).
            result.removeAll { $0.taskId == task.id && $0.date == dateStr }
            let skipPeriodKey: String? = (task.type == .weekly || task.type == .monthly)
                ? DateUtil.periodKey(type: task.type, refDate)
                : nil
            let skipRec = CheckinRecord(
                id: IdUtil.genId(),
                taskId: task.id,
                date: dateStr,
                status: .skipped,
                periodKey: skipPeriodKey,
                counted: false,
                createdAt: DateUtil.isoDateTime(refDate)
            )
            result.append(skipRec)
        }

        return result
    }
}
