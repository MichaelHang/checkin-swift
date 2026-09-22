import Foundation
import CheckinCore

/// Unified rules for "can this day be acted on (check-in / review / revoke)" + badge text.
///
/// ## Why it lives in its own file
///
/// The rule is shared by **two** call sites and must be exactly identical — otherwise the calendar
/// could say a day is not tappable while the detail page still is:
/// - `CalendarView`: whether the selected day's task rows render action buttons;
/// - `TaskDetailView`: whether an opened day's details render action buttons (this view previously
///   missed the gate, allowing "open a future day → tap done → write a future-dated record").
///
/// ## Why pure functions
///
/// It used to be a `private` computed property inside a View, **invisible to tests**, so the rule
/// could not be locked. Extracting pure functions and injecting `now` explicitly (no internal
/// `DateUtil.now()`) lets tests inject fixed dates and assert.
enum CalendarDayPolicy {

    /// Whether the date is today (local-date comparison, time of day ignored)
    static func isToday(_ date: Date, now: Date) -> Bool {
        DateUtil.localDate(date) == DateUtil.localDate(now)
    }

    /// Whether the date is after today (local-date comparison, time of day ignored)
    static func isFuture(_ date: Date, now: Date) -> Bool {
        DateUtil.localDate(date) > DateUtil.localDate(now)
    }

    /// Whether the day allows check-in / review / revoke: **today and past days yes, future days read-only**.
    ///
    /// Past days are open by explicit user request (backfilling on historical dates). Future days must
    /// be blocked — otherwise a "completed in the future" record gets written, polluting streak and
    /// completion-rate stats.
    ///
    /// - Parameter selected: **the day the record will land on** (the value actually passed as `refDate`),
    ///   not "which day the user is looking at" — the two differ for period tasks (period tasks
    ///   always use `now`).
    static func canAct(selected: Date, now: Date) -> Bool {
        !isFuture(selected, now: now)
    }

    /// Skip / restore is **not** subject to the "future days read-only" rule; always allowed.
    ///
    /// Three reasons:
    /// 1. Skip cancels the day's obligation instead of writing a completion — marking next Monday off
    ///    (a future day) is a legitimate request;
    /// 2. A future day can only hold skip records (check-ins are blocked by `canAct`), never real ones;
    /// 3. So "restore" (= revoke) on that day only removes the skip, never a real check-in.
    ///
    /// `canAct` stays as is — future-day check-ins remain read-only.
    static func canSkip(selected: Date, now: Date) -> Bool { true }

    /// Badge text: future day → "未到" / today → `nil` (no badge) / past day → "补记".
    ///
    /// It expresses **which day the record lands on**, not "whether buttons exist" — the old
    /// implementation keyed off "actionable / read-only", which no longer holds now that past-day
    /// actions are allowed.
    static func badge(selected: Date, now: Date) -> String? {
        if isFuture(selected, now: now) { return "未到" }
        if isToday(selected, now: now) { return nil }
        return "补记"
    }
}
