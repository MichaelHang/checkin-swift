import Foundation
import SwiftData
import CheckinCore

/// Stats view model (@Observable).
///
/// **Thin wrapper**: only bridges `@Query` data to `StatsUtil` pure functions (the `StreakUtil`
/// streak and the delete action are kept here). All metrics (expected / done / pass rate / weak
/// spots / by weekday / trend / achieved-week streak) live in `StatsUtil` and are unit-testable.
@Observable
final class StatsViewModel {

    // MARK: - This week's stats (delegated to StatsUtil)

    func weeklyStats(_ tasks: [Task], records: [CheckinRecord], ref: Date) -> WeeklyStats {
        StatsUtil.weeklyStats(tasks: tasks, records: records, ref: ref)
    }

    func completionByTask(_ tasks: [Task], records: [CheckinRecord], ref: Date) -> [TaskCompletion] {
        StatsUtil.completionByTask(tasks: tasks, records: records, ref: ref)
    }

    func completionByWeekday(_ tasks: [Task], records: [CheckinRecord], ref: Date) -> [WeekdayCompletion] {
        StatsUtil.completionByWeekday(tasks: tasks, records: records, ref: ref)
    }

    func weeklyTrend(_ tasks: [Task], records: [CheckinRecord], ref: Date, weeks: Int = 4) -> [WeekTrend] {
        StatsUtil.weeklyTrend(tasks: tasks, records: records, ref: ref, weeks: weeks)
    }

    func achievedWeekStreak(_ tasks: [Task], records: [CheckinRecord], ref: Date) -> Int {
        StatsUtil.achievedWeekStreak(tasks: tasks, records: records, ref: ref)
    }

    // MARK: - Streak / delete (reused by the detail page)

    /// Consecutive completed days (daily tasks only, derived by StreakUtil)
    func streakFor(_ task: Task, records: [CheckinRecord]) -> Int {
        StreakUtil.computeStreak(task: task, records: records)
    }

    func deleteTask(id: String, context: ModelContext) {
        CheckinRepository(modelContext: context).deleteTask(id: id)
    }
}
