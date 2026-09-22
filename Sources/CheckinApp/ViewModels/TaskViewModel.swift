import Foundation
import SwiftData
import CheckinCore

/// Today view model (@Observable).
///
/// Orchestrates `CheckinRepository` (SwiftData writes) + the pure function layer (state machine /
/// period progress / dates). Holds only action methods and derivations driven by @Query data;
/// caches no mutable state itself (all state is derived).
@Observable
final class TaskViewModel {

    // MARK: - State machine actions (write back to SwiftData)

    /// `refDate` decides **which day the record lands on**, so it **deliberately has no default value**.
    ///
    /// This used to default to `= DateUtil.now()`: a caller omitting it would not error, it would
    /// just silently record the entry to today — historical-day backfills, calendar look-backs and
    /// similar all quietly wrote the wrong date with nothing visible in the UI (buttons worked,
    /// records appeared). Removing the default turns the omission into a **compile error**,
    /// caught by the compiler.
    ///
    /// Callers pass explicitly by semantics: today view passes "today", calendar passes the selected
    /// day, detail page passes the day being viewed.
    func complete(_ task: Task, refDate: Date, context: ModelContext) {
        CheckinRepository(modelContext: context)
            .applyAction(taskId: task.id, action: .complete, refDate: refDate)
    }

    func pass(_ task: Task, refDate: Date, context: ModelContext) {
        CheckinRepository(modelContext: context)
            .applyAction(taskId: task.id, action: .pass, refDate: refDate)
    }

    func fail(_ task: Task, refDate: Date, context: ModelContext) {
        CheckinRepository(modelContext: context)
            .applyAction(taskId: task.id, action: .fail, refDate: refDate)
    }

    func revoke(_ task: Task, refDate: Date, context: ModelContext) {
        CheckinRepository(modelContext: context)
            .applyAction(taskId: task.id, action: .revoke, refDate: refDate)
    }

    /// Single-day exemption: skip `refDate` (writes a .skipped record).
    ///
    /// `refDate` likewise **deliberately has no default** (same as complete/pass/fail/revoke) —
    /// omission must fail compilation, otherwise "skip a day" would silently record to today.
    func skip(_ task: Task, refDate: Date, context: ModelContext) {
        CheckinRepository(modelContext: context)
            .applyAction(taskId: task.id, action: .skip, refDate: refDate)
    }

    // MARK: - Today aggregations

    /// Check-in-able today: daily tasks + weekly-day tasks due today
    func dailyTasks(_ tasks: [Task], refDate: Date) -> [Task] {
        tasks.filter {
            $0.type == .daily
            || ($0.type == .weeklyDay && DateUtil.isDue($0, refDate: refDate))
        }
    }

    func specificTasksForToday(_ tasks: [Task], refDate: Date) -> [Task] {
        tasks.filter { $0.type == .specificDate && DateUtil.isDue($0, refDate: refDate) }
    }

    /// Period tasks (weekly/monthly count targets); weekly-day is day-level and not included
    func periodTasks(_ tasks: [Task]) -> [Task] {
        tasks.filter { $0.type == .weekly || $0.type == .monthly }
    }

    // MARK: - Daily / specific-date current status

    /// The day's latest record determines its status (no record → pending, naturally resetting the next day)
    func statusOf(_ task: Task, records: [CheckinRecord], date: String) -> TaskStatus {
        records.filter { $0.taskId == task.id && $0.date == date }
            .last?.status ?? .pending
    }

    // MARK: - Period progress derivation

    func progressFor(_ task: Task, records: [CheckinRecord], now: Date) -> PeriodProgress {
        guard let key = DateUtil.periodKey(type: task.type, now) else {
            return PeriodProgress(done: 0, target: task.targetCount ?? 0,
                                  percent: 0, achieved: false, status: .inProgress)
        }
        return PeriodUtil.computePeriodProgress(task: task, records: records, periodKey: key, now: now)
    }

    /// Whether an awaiting-review record exists (drives the pass/fail/revoke buttons on the period card)
    func hasAwaiting(_ task: Task, records: [CheckinRecord], now: Date) -> Bool {
        if let key = DateUtil.periodKey(type: task.type, now) {
            return records.contains {
                $0.taskId == task.id && $0.periodKey == key && $0.status == .awaiting
            }
        }
        let today = DateUtil.localDate(now)
        return records.contains {
            $0.taskId == task.id && $0.date == today && $0.status == .awaiting
        }
    }
}
