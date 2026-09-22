import Foundation

/// Streak-of-done-days statistics (daily tasks only)
public struct StreakUtil {

    /// Takes all counted==true dates for the task and counts back from the most recent day over
    /// consecutive calendar days. No record today → start from yesterday; a gap resets to zero.
    /// **Skipped dates (.skipped) are crossed over during the walk**: they neither reduce the streak
    /// nor break the chain (single-day exemption). Daily tasks (type == .daily) only; other types return 0.
    public static func computeStreak(task: Task, records: [CheckinRecord]) -> Int {
        guard task.type == .daily else { return 0 }

        let relevant = records.filter {
            $0.taskId == task.id && (task.endDate == nil || $0.date <= task.endDate!)
        }
        let dateStrings = relevant.filter { $0.counted }.map { $0.date }
        // Skipped-day set (filtered from the same source as done, keeping criteria consistent)
        let skipped = Set(relevant.filter { $0.status == .skipped }.map { $0.date })

        return computeStreakFromDates(dateStrings, skipped: skipped)
    }

    // MARK: - Internal

    private static func computeStreakFromDates(_ dateStrings: [String], skipped: Set<String>) -> Int {
        let set = Set(dateStrings)
        guard !set.isEmpty || !skipped.isEmpty else { return 0 }

        let todayStr = DateUtil.localDate(DateUtil.now())
        let anchorStr: String
        if set.contains(todayStr) {
            anchorStr = todayStr
        } else if let todayDate = DateUtil.parseLocalDate(todayStr) {
            let cal = Calendar(identifier: .gregorian)
            let yesterday = cal.date(byAdding: .day, value: -1, to: todayDate)!
            anchorStr = DateUtil.localDate(yesterday)
        } else {
            return 0
        }

        var streak = 0
        var cursor = anchorStr
        let cal = Calendar(identifier: .gregorian)
        while true {
            if skipped.contains(cursor) {
                // Skipped day: step back one day and continue — streak not reduced, chain not broken.
                guard let d = DateUtil.parseLocalDate(cursor) else { break }
                cursor = DateUtil.localDate(cal.date(byAdding: .day, value: -1, to: d)!)
                continue
            }
            guard set.contains(cursor) else { break }
            streak += 1
            guard let d = DateUtil.parseLocalDate(cursor) else { break }
            cursor = DateUtil.localDate(cal.date(byAdding: .day, value: -1, to: d)!)
        }
        return streak
    }
}
