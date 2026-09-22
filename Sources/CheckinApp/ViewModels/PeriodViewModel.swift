import Foundation
import SwiftData
import CheckinCore

/// Period (weekly/monthly) view model (@Observable).
///
/// Orchestrates the Repository + pure functions `PeriodUtil` / `DateUtil`, providing weekly/monthly
/// filtering, progress derivation, period window text and check-in/review (pass·fail)/revoke actions.
@Observable
final class PeriodViewModel {

    // MARK: - Actions

    func checkin(_ task: Task, context: ModelContext) {
        CheckinRepository(modelContext: context)
            .applyAction(taskId: task.id, action: .complete, refDate: DateUtil.now())
    }

    func pass(_ task: Task, context: ModelContext) {
        CheckinRepository(modelContext: context)
            .applyAction(taskId: task.id, action: .pass, refDate: DateUtil.now())
    }

    func fail(_ task: Task, context: ModelContext) {
        CheckinRepository(modelContext: context)
            .applyAction(taskId: task.id, action: .fail, refDate: DateUtil.now())
    }

    func revoke(_ task: Task, context: ModelContext) {
        CheckinRepository(modelContext: context)
            .applyAction(taskId: task.id, action: .revoke, refDate: DateUtil.now())
    }

    // MARK: - Weekly / monthly filters

    func weeklyTasks(_ tasks: [Task]) -> [Task] {
        tasks.filter { $0.type == .weekly && !DateUtil.isEnded($0, on: DateUtil.now()) }
    }

    func monthlyTasks(_ tasks: [Task]) -> [Task] {
        tasks.filter { $0.type == .monthly && !DateUtil.isEnded($0, on: DateUtil.now()) }
    }

    func weeklyDayTasks(_ tasks: [Task]) -> [Task] {
        tasks.filter { $0.type == .weeklyDay && !DateUtil.isEnded($0, on: DateUtil.now()) }
    }

    func dailyTasks(_ tasks: [Task]) -> [Task] {
        tasks.filter { $0.type == .daily && !DateUtil.isEnded($0, on: DateUtil.now()) }
    }

    // MARK: - Progress / window derivation

    func progressFor(_ task: Task, records: [CheckinRecord], now: Date) -> PeriodProgress {
        guard let key = DateUtil.periodKey(type: task.type, now) else {
            return PeriodProgress(done: 0, target: task.targetCount ?? 0,
                                  percent: 0, achieved: false, status: .inProgress)
        }
        return PeriodUtil.computePeriodProgress(task: task, records: records, periodKey: key, now: now)
    }

    func hasAwaiting(_ task: Task, records: [CheckinRecord], now: Date) -> Bool {
        guard let key = DateUtil.periodKey(type: task.type, now) else { return false }
        return records.contains {
            $0.taskId == task.id && $0.periodKey == key && $0.status == .awaiting
        }
    }

    /// Period window text, e.g. '2026-03-16 ~ 2026-03-22'
    func periodWindowText(_ task: Task, now: Date) -> String {
        if task.type == .weekly {
            let r = DateUtil.weekRange(now)
            return "\(DateUtil.localDate(r.start)) ~ \(DateUtil.localDate(r.end))"
        } else if task.type == .monthly {
            let r = DateUtil.monthRange(now)
            return "\(DateUtil.localDate(r.start)) ~ \(DateUtil.localDate(r.end))"
        }
        return ""
    }
}
