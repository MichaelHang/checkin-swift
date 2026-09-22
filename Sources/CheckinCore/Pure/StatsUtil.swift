import Foundation

// MARK: - Behavior stats result types

/// Weekly overview: expected / done / completion rate + pass / judged / pass rate
public struct WeeklyStats: Equatable {
    public var expected: Int      // expected count this week
    public var done: Int          // done count this week (counted == true)
    public var rate: Double?      // done / expected; expected == 0 → nil
    public var passed: Int        // passes this week
    public var judged: Int        // judged count this week (passed + failed)
    public var passRate: Double?  // passed / judged; judged == 0 → nil

    public init(expected: Int,
                done: Int,
                rate: Double?,
                passed: Int,
                judged: Int,
                passRate: Double?) {
        self.expected = expected
        self.done = done
        self.rate = rate
        self.passed = passed
        self.judged = judged
        self.passRate = passRate
    }
}

/// This week's completion for a single task (for "which tasks keep slipping")
public struct TaskCompletion: Identifiable, Equatable {
    public var id: String
    public var name: String
    public var expected: Int
    public var done: Int
    public var rate: Double?

    public init(id: String, name: String, expected: Int, done: Int, rate: Double?) {
        self.id = id
        self.name = name
        self.expected = expected
        self.done = done
        self.rate = rate
    }
}

/// This week's completion for one weekday (fixed Mon..Sun, 7 entries)
public struct WeekdayCompletion: Identifiable, Equatable {
    public var weekday: Int      // DateUtil.weekdayISO: 1=Mon ... 7=Sun
    public var label: String
    public var expected: Int
    public var done: Int
    public var rate: Double?

    public var id: Int { weekday }

    public init(weekday: Int, label: String, expected: Int, done: Int, rate: Double?) {
        self.weekday = weekday
        self.label = label
        self.expected = expected
        self.done = done
        self.rate = rate
    }
}

/// Completion rate for one week (for the recent-weeks trend)
public struct WeekTrend: Identifiable, Equatable {
    public var label: String     // this week / last week / 3 weeks ago / 4 weeks ago
    public var rate: Double?     // nil when that week's expected is 0

    public var id: String { label }

    public init(label: String, rate: Double?) {
        self.label = label
        self.rate = rate
    }
}

/// Behavior statistics pure functions (CheckinCore, Foundation only; unit-testable, no SwiftData dependency)
///
/// Criteria (fixed; do not change on your own):
/// - **Done = any check-in counts**: `CheckinRecord.counted == true` (including passed / failed / awaiting),
///   consistent with `StateMachine.applyAction`; quality is tracked separately as the pass rate.
/// - **Window = the current calendar week** (Mon..Sun, reusing `DateUtil.weekRange`), aligned with period tasks' periodKey.
/// - **Future days don't count toward expected**: stats viewed on Wednesday must not be diluted by Thu..Sun.
///
/// ## "Expected slot" model (core invariant: done ≤ expected → completion rate never exceeds 100%)
///
/// One "expected" = one `(taskId, dateKey)` slot; `expected` is the total slot count and `done` is the
/// number of slots **with a counted record** — same source, so done can never exceed expected.
///
/// Slot conditions (see `expectedSlots`): task not ended that day + day ≤ cap + [day ≥ creation date
/// **or** a counted record exists for the task that day]. The **backfill branch** means a backdated
/// check-in counts as that day's expected; historical days before creation with no check-in at all
/// still aren't expected, so weeks before a task existed aren't retroactively 0% (the trend stays true).
///
/// ## "Single-day exemption (skip)" criteria
///
/// - **Day-level tasks** (daily / weeklyDay / specificDate): skipped dates are **removed from expected slots**
///   (see the `skippedKeys` guard in `expectedSlots`) — not in the denominator, not a miss, no drag on the rate.
/// - **Count tasks** (weekly / monthly): available days = period total days − skipped days in the period;
///   target capped at `effectiveTarget = min(targetCount, available days)`
///   (see `weekStats` / `completionByTask` / `expectedCount`).
/// - **Available days span the whole period, not truncated at cap (today)** — future days remain
///   available; only explicitly skipped days subtract. That is distinct from "done truncated at cap" — don't mix them up.
/// - **With no skips, results must match exactly**: no skips in a week = 7 → `min(target, 7) = target`.
public struct StatsUtil {

    // MARK: - Internal: expected slots

    /// One expected opportunity: a task on a day
    private struct Slot: Hashable {
        let taskId: String
        let dateKey: String
    }

    private static func slotKey(taskId: String, dateKey: String) -> String {
        taskId + "|" + dateKey
    }

    /// Days a task was skipped in [fromKey, toKey] (single entry point for skip counting)
    ///
    /// `internal` (not private): `PeriodUtil` uses it for the same available-days criteria, avoiding drift.
    static func skippedDayCount(taskId: String, records: [CheckinRecord],
                                fromKey: String, toKey: String) -> Int {
        records.filter {
            $0.taskId == taskId && $0.status == .skipped
                && $0.date >= fromKey && $0.date <= toKey
        }.count
    }

    /// All expected slots in the week (Mon..Sun, capped at cap)
    private static func expectedSlots(tasks: [Task],
                                      records: [CheckinRecord],
                                      weekStart: Date,
                                      cap: Date) -> Set<Slot> {
        var slots: Set<Slot> = []
        for task in tasks {
            let created = createdDay(of: task)
            // Dates this task was explicitly skipped on: the single place enforcing skip → remove expected slot.
            let skippedKeys: Set<String> = Set(
                records.filter { $0.taskId == task.id && $0.status == .skipped }.map { $0.date }
            )
            for offset in 0..<7 {
                let day = DateUtil.addingDays(offset, to: weekStart)
                guard day <= cap else { continue }                        // future days don't count
                guard matchesDay(task: task, day: day) else { continue }  // type / config match
                guard !DateUtil.isEnded(task, on: day) else { continue }  // ended tasks are no longer expected

                let key = DateUtil.localDate(day)
                guard !skippedKeys.contains(key) else { continue }        // skipped days removed from expected slots
                let afterCreated: Bool = {
                    guard let created else { return true }
                    return key >= DateUtil.localDate(created)
                }()
                // Backfill: a day before creation with a counted record that day still counts as that day's expected
                let backdated = records.contains { $0.taskId == task.id && $0.date == key && $0.counted }
                guard afterCreated || backdated else { continue }

                slots.insert(Slot(taskId: task.id, dateKey: key))
            }
        }
        return slots
    }

    /// Whether the task could produce a slot on this day (type and config only)
    private static func matchesDay(task: Task, day: Date) -> Bool {
        switch task.type {
        case .daily:
            return true
        case .weeklyDay:
            return task.targetWeekday == DateUtil.weekdayISO(day)
        case .specificDate:
            return task.targetDate == DateUtil.localDate(day)
        case .weekly, .monthly:
            return false // period-level tasks count by count target, no per-day slots
        }
    }

    // MARK: - This week's expected count

    /// The task's expected count this week (= its expected slots; count target for period tasks)
    ///
    /// **Needs `records`**: a backfilled day counts as expected even before the task's creation
    /// date, and only records can prove it.
    public static func expectedCount(task: Task, records: [CheckinRecord], inWeekOf ref: Date) -> Int {
        let week = DateUtil.weekRange(ref)
        let cap = min(dayStart(ref), dayStart(week.end))
        var total = expectedSlots(tasks: [task], records: records,
                                  weekStart: week.start, cap: cap).count
        if task.type == .weekly, exists(task, on: cap), !DateUtil.isEnded(task, on: cap) {
            // Available days span the whole week (not truncated at cap): future days remain available; only explicitly skipped days subtract.
            let weekStartKey = DateUtil.localDate(week.start)
            let weekEndKey = DateUtil.localDate(DateUtil.addingDays(6, to: week.start))
            let skipped = skippedDayCount(taskId: task.id, records: records,
                                          fromKey: weekStartKey, toKey: weekEndKey)
            total += min(max(0, task.targetCount ?? 1), max(0, 7 - skipped))
        }
        return total
    }

    // MARK: - Weekly overview

    /// This week's completion / pass overview
    ///
    /// - expected: total expected slots (+ count target for period tasks)
    /// - done: slots with a counted record (period tasks truncated to the count target)
    /// - rate: done / expected; expected == 0 → nil
    /// - passRate: .passed / (.passed + .failed) within slots; 0 denominator → nil
    public static func weeklyStats(tasks: [Task], records: [CheckinRecord], ref: Date) -> WeeklyStats {
        let week = DateUtil.weekRange(ref)
        return weekStats(tasks: tasks, records: records,
                         weekStart: week.start, cap: min(dayStart(ref), dayStart(week.end)))
    }

    /// Stats for a specific week (`cap` = cutoff day)
    private static func weekStats(tasks: [Task],
                                  records: [CheckinRecord],
                                  weekStart: Date,
                                  cap: Date) -> WeeklyStats {
        let startKey = DateUtil.localDate(weekStart)
        let endKey = DateUtil.localDate(DateUtil.addingDays(6, to: weekStart))

        // Bucket this week's counted records by (taskId, date) (last record wins per day)
        var statusBySlot: [String: TaskStatus] = [:]
        for r in records where r.counted && r.date >= startKey && r.date <= endKey {
            statusBySlot[slotKey(taskId: r.taskId, dateKey: r.date)] = r.status
        }

        let slots = expectedSlots(tasks: tasks, records: records, weekStart: weekStart, cap: cap)
        var expected = slots.count
        var done = 0
        var passed = 0
        var judged = 0

        for slot in slots {
            let key = slotKey(taskId: slot.taskId, dateKey: slot.dateKey)
            guard let status = statusBySlot[key] else { continue }
            done += 1
            if status == .passed {
                passed += 1
                judged += 1
            } else if status == .failed {
                judged += 1
            }
        }

        // Period-level (weekly): counted by count target; target capped by available days (skips subtracted), done truncated to target so the rate never exceeds 100%
        for task in tasks where task.type == .weekly {
            // Weeks before the task existed don't count toward expected, otherwise rate would be 0% instead of nil (phantom 0% bars in the trend)
            guard exists(task, on: cap) else { continue }
            guard !DateUtil.isEnded(task, on: cap) else { continue }
            let target = max(0, task.targetCount ?? 1)
            guard target > 0 else { continue }
            // Available days span the whole week (endKey, not cap): future days remain available; only explicitly skipped days subtract.
            let skippedInWeek = skippedDayCount(taskId: task.id, records: records,
                                                fromKey: startKey, toKey: endKey)
            let effectiveTarget = min(target, max(0, 7 - skippedInWeek))
            expected += effectiveTarget

            let dayStatuses = countedDayStatuses(of: task.id, in: records,
                                                 from: startKey,
                                                 to: capEndKey(weekEndKey: endKey, cap: cap))
            let used = min(dayStatuses.count, effectiveTarget)
            done += used
            for (_, status) in dayStatuses.sorted(by: { $0.key < $1.key }).prefix(used) {
                if status == .passed {
                    passed += 1
                    judged += 1
                } else if status == .failed {
                    judged += 1
                }
            }
        }

        // Safety net: no criteria drift may allow done > expected (completion rate capped at 100%)
        done = min(done, expected)
        return WeeklyStats(
            expected: expected,
            done: done,
            rate: ratio(done, expected),
            passed: passed,
            judged: judged,
            passRate: ratio(passed, judged)
        )
    }

    // MARK: - By task, weakest first (ascending rate)

    /// Per-task weekly completion, **ascending by completion rate** (weakest first); tasks with 0 expected are excluded
    public static func completionByTask(tasks: [Task], records: [CheckinRecord], ref: Date) -> [TaskCompletion] {
        let week = DateUtil.weekRange(ref)
        let cap = min(dayStart(ref), dayStart(week.end))
        let startKey = DateUtil.localDate(week.start)
        let endKey = DateUtil.localDate(DateUtil.addingDays(6, to: week.start))
        let slots = expectedSlots(tasks: tasks, records: records, weekStart: week.start, cap: cap)

        var expectedByTask: [String: Int] = [:]
        var doneByTask: [String: Int] = [:]
        for slot in slots {
            expectedByTask[slot.taskId, default: 0] += 1
            if hasCounted(taskId: slot.taskId, dateKey: slot.dateKey, in: records) {
                doneByTask[slot.taskId, default: 0] += 1
            }
        }

        var result: [TaskCompletion] = []
        for task in tasks {
            var expected = expectedByTask[task.id] ?? 0
            var done = doneByTask[task.id] ?? 0
            if task.type == .weekly, exists(task, on: cap), !DateUtil.isEnded(task, on: cap) {
                let target = max(0, task.targetCount ?? 1)
                // Same criteria as weekStats / expectedCount: target capped by available days (whole week minus skipped days).
                let skippedInWeek = skippedDayCount(taskId: task.id, records: records,
                                                    fromKey: startKey, toKey: endKey)
                let effectiveTarget = min(target, max(0, 7 - skippedInWeek))
                expected += effectiveTarget
                done += min(countedDayStatuses(of: task.id, in: records,
                                               from: startKey,
                                               to: capEndKey(weekEndKey: endKey, cap: cap)).count, effectiveTarget)
            }
            guard expected > 0 else { continue }
            done = min(done, expected)
            result.append(TaskCompletion(id: task.id,
                                         name: task.name,
                                         expected: expected,
                                         done: done,
                                         rate: ratio(done, expected)))
        }
        // Ascending rate → weakest first; ties broken by expected descending (bigger tasks stand out)
        return result.sorted { lhs, rhs in
            if lhs.rate == rhs.rate { return lhs.expected > rhs.expected }
            return (lhs.rate ?? 1) < (rhs.rate ?? 1)
        }
    }

    // MARK: - By weekday (fixed Mon..Sun, 7 entries)

    /// Mon..Sun completion (always 7 entries, so the UI can lay out 7 bars directly)
    public static func completionByWeekday(tasks: [Task], records: [CheckinRecord], ref: Date) -> [WeekdayCompletion] {
        let week = DateUtil.weekRange(ref)
        let cap = min(dayStart(ref), dayStart(week.end))
        let slots = expectedSlots(tasks: tasks, records: records, weekStart: week.start, cap: cap)

        var result: [WeekdayCompletion] = []
        for iso in 1...7 {
            let day = DateUtil.addingDays(iso - 1, to: week.start)
            let key = DateUtil.localDate(day)
            guard day <= cap else {
                result.append(WeekdayCompletion(weekday: iso, label: DateUtil.weekdayLabel(iso),
                                                expected: 0, done: 0, rate: nil))
                continue
            }
            let daySlots = slots.filter { $0.dateKey == key }
            let expected = daySlots.count
            let done = min(daySlots.filter { hasCounted(taskId: $0.taskId, dateKey: key, in: records) }.count,
                           expected)
            result.append(WeekdayCompletion(weekday: iso,
                                            label: DateUtil.weekdayLabel(iso),
                                            expected: expected,
                                            done: done,
                                            rate: ratio(done, expected)))
        }
        return result
    }

    // MARK: - Recent-weeks trend (current week rightmost → chronological order)

    /// Completion rates for the last `weeks` weeks including the current one, in **chronological order**
    /// (the last item is the current week → rightmost in the UI)
    public static func weeklyTrend(tasks: [Task],
                                   records: [CheckinRecord],
                                   ref: Date,
                                   weeks: Int = 4) -> [WeekTrend] {
        let total = max(1, weeks)
        var result: [WeekTrend] = []
        // Walk from the oldest week toward the current week so it lands rightmost
        for step in stride(from: total - 1, through: 0, by: -1) {
            let anchor = DateUtil.addingDays(-7 * step, to: ref)
            let week = DateUtil.weekRange(anchor)
            // The current week counts only through today; past weeks count the whole week
            let cap = step == 0 ? min(dayStart(ref), dayStart(week.end)) : dayStart(week.end)
            let stats = weekStats(tasks: tasks, records: records, weekStart: week.start, cap: cap)
            result.append(WeekTrend(label: trendLabel(step), rate: stats.rate))
        }
        return result
    }

    /// Chinese trend labels: step=0 → this week; 1 → last week; ≥2 → (step+1) weeks ago
    private static func trendLabel(_ step: Int) -> String {
        switch step {
        case 0: return "本周"
        case 1: return "上周"
        default: return "\(step + 1) 周前"
        }
    }

    // MARK: - Consecutive achieved weeks

    /// Number of consecutive weeks with completion rate ≥ `Constants.achieveRatio`
    ///
    /// Two situations do **not** break the streak (any other miss does):
    /// - **Current week not yet achieved** → start counting from last week, so a week that just
    ///   began (nothing checked in yet) doesn't zero the streak;
    /// - **Historical empty weeks** (expected == 0, e.g. task not yet created / config mismatch) →
    ///   no data ≠ failure; skipped so an empty week in between doesn't falsely break the streak.
    ///
    /// **A historical week with expected > 0 that missed the threshold** is the only real break
    /// (`expected > 0 && rate < threshold`). Looks back at most 52 weeks.
    ///
    /// ## Empty-week exemption semantics
    ///
    /// Empty weeks are exempt, so the streak can span far-apart achieved weeks: current week achieved
    /// + N empty weeks + an earlier achieved week → streak of 2. Daily / weekly-day users never hit
    /// this (every week has expected slots); only many one-off specific-date tasks produce it.
    public static func achievedWeekStreak(tasks: [Task], records: [CheckinRecord], ref: Date) -> Int {
        var streak = 0
        for step in 0..<52 {
            let anchor = DateUtil.addingDays(-7 * step, to: ref)
            let week = DateUtil.weekRange(anchor)
            let cap = step == 0 ? min(dayStart(ref), dayStart(week.end)) : dayStart(week.end)
            let stats = weekStats(tasks: tasks, records: records, weekStart: week.start, cap: cap)
            guard let rate = stats.rate, rate >= Constants.achieveRatio else {
                // Three branches when the threshold isn't met:
                // 1) Current week (step == 0): just began, not yet filled → skip, count from last week;
                // 2) Historical empty week (expected == 0, nothing expected): no data ≠ failure → skip, no break;
                // 3) Historical week with expected > 0 below the threshold → real failure → break.
                // Branch 3 gates against skipping failed weeks forever; branch 2 guards empty weeks in between.
                // Branches 1 and 2 are both continue; their order doesn't affect semantics.
                // The load-bearing part: branch 3 must be break, not continue — continue would skip past failed weeks.
                if step == 0 { continue }
                guard stats.expected > 0 else { continue }
                break
            }
            streak += 1
        }
        return streak
    }

    // MARK: - Helpers

    /// (a / b); b == 0 → nil (means "not computable", not 0, so the UI doesn't show 0%)
    private static func ratio(_ a: Int, _ b: Int) -> Double? {
        guard b > 0 else { return nil }
        return Double(a) / Double(b)
    }

    /// Day start 00:00:00 (local)
    private static func dayStart(_ d: Date) -> Date {
        DateUtil.parseLocalDate(DateUtil.localDate(d)) ?? d
    }

    /// The week window's actual right end: `min(weekEnd, cap)`, so future days aren't swallowed by the window
    ///
    /// When bucketing period-level (.weekly) check-ins by day, the window end must be ≤ cap,
    /// otherwise Sat/Sun future-day records would be miscounted as done.
    private static func capEndKey(weekEndKey: String, cap: Date) -> String {
        let capKey = DateUtil.localDate(cap)
        return min(weekEndKey, capKey)
    }

    /// Task creation day (00:00:00); createdAt is 'YYYY-MM-DD HH:mm:ss'
    private static func createdDay(of task: Task) -> Date? {
        DateUtil.parseLocalDate(String(task.createdAt.prefix(10)))
    }

    /// Whether the task already existed on `day` (treated as always existing if createdAt fails to parse)
    ///
    /// Period-level (weekly) tasks have no per-day slot to infer creation from; this keeps weeks
    /// before the task existed from counting as 0%.
    private static func exists(_ task: Task, on day: Date) -> Bool {
        guard let created = createdDay(of: task) else { return true }
        return DateUtil.localDate(day) >= DateUtil.localDate(created)
    }

    /// Whether the task has a counted record on that day
    private static func hasCounted(taskId: String, dateKey: String, in records: [CheckinRecord]) -> Bool {
        records.contains { $0.taskId == taskId && $0.date == dateKey && $0.counted }
    }

    /// A task's counted statuses bucketed by day in [fromKey, toKey] (last record wins per day)
    private static func countedDayStatuses(of taskId: String,
                                           in records: [CheckinRecord],
                                           from fromKey: String,
                                           to toKey: String) -> [String: TaskStatus] {
        var map: [String: TaskStatus] = [:]
        for r in records where r.taskId == taskId && r.counted && r.date >= fromKey && r.date <= toKey {
            map[r.date] = r.status
        }
        return map
    }
}
