import Foundation

/// Status of daily / specific-date tasks.
///
/// Three tiers: not done, done, and skipped; done is further qualified by review outcome.
/// - Not done: `pending` (no check-in, counts toward no statistics)
/// - Done: `awaiting` (checked in, review pending, `counted=true`), `passed` (pass), `failed` (fail)
/// - Skipped: `skipped` (single-day exemption — the day is removed from expected slots; `counted=false`,
///   neither done nor streak-breaking)
///
/// ⚠️ Checking in counts as done: regardless of `acceptanceRequired`, a check-in sets `counted=true`,
///    immediately feeding streak, period progress, and completion rate; `awaiting` / `passed` / `failed`
///    all have `isDone == true`. Pass / fail is only a quality label (blue / green / yellow) and does not
///    affect whether the task is done.
///
/// ⚠️ Skip is not done: `skipped` has `isDone == false` and `counted == false`.
@frozen public enum TaskStatus: String, Codable, CaseIterable {
    case pending    // not done
    case awaiting   // awaiting review (already done at check-in; only the pass / fail quality review is pending)
    case passed     // pass (done and target met)
    case failed     // fail (done but target not met)
    case skipped    // skipped (single-day exemption; counted=false, neither done nor streak-breaking)
}

extension TaskStatus {
    /// Whether the day counts as done — true from the moment of check-in (including .awaiting);
    /// only pending (no check-in) is false. Pass / fail is only a quality label and does not change
    /// done (drives streak / completion rate / period counts).
    ///
    /// ⚠️ `skipped` (single-day exemption) is not done: it only means "no need to do it this day" and
    ///    must be excluded, otherwise it pollutes completion rate and streak as if it were done.
    public var isDone: Bool { self != .pending && self != .skipped }

    /// Restores from the persisted raw value.
    ///
    /// Old versions stored `"completed"` (the done case before it was renamed `passed`);
    /// migrate it to `.passed` so legacy data does not degrade to `.pending`.
    ///
    /// `"skipped"` needs no special case: `TaskStatus(rawValue:)` matches `.skipped` directly
    /// (its raw value is the case name) in the first `if`.
    public static func decode(raw: String) -> TaskStatus {
        if let s = TaskStatus(rawValue: raw) { return s }
        return raw == "completed" ? .passed : .pending
    }

    /// The JSON (Codable) path shares the same source as `decode(raw:)`. The synthesized implementation
    /// throws DecodingError on legacy `"completed"` in backups, failing the whole JSON import; decoding
    /// here migrates it the same way as the SwiftData read path (`PersistedCheckinRecord.toValue`).
    /// `encode(to:)` stays compiler-synthesized (raw value stored as-is); export is unaffected.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TaskStatus.decode(raw: raw)
    }
}

/// Check-in record (one per completed action; single source of truth — state machine and progress are derived from these)
public struct CheckinRecord: Identifiable, Codable, Equatable {
    public var id: String
    public var taskId: String
    public var date: String                   // local date the action happened, 'YYYY-MM-DD'
    public var status: TaskStatus             // status of this action (awaiting / passed / failed; pending is transient only)
    public var periodKey: String?             // period a period task belongs to: week='YYYY-Www' (ISO), month='YYYY-MM'
    public var counted: Bool                  // counts toward the count target (no review: true at check-in; with review: true after pass or fail)
    public var createdAt: String              // ISO datetime

    public init(id: String,
                taskId: String,
                date: String,
                status: TaskStatus,
                periodKey: String? = nil,
                counted: Bool,
                createdAt: String) {
        self.id = id
        self.taskId = taskId
        self.date = date
        self.status = status
        self.periodKey = periodKey
        self.counted = counted
        self.createdAt = createdAt
    }
}
