import Foundation

// MARK: - Enums

/// Task type.
///
/// - `daily` / `specificDate` / `weeklyDay` are single-day level: one record per day, no count target
/// - `weekly` / `monthly` are period level: count target over a natural weekly / monthly period
@frozen public enum TaskType: String, Codable, CaseIterable, Identifiable {
    case daily
    case specificDate   // specific date (single occurrence)
    case weeklyDay      // weekly on a given weekday (e.g. Mondays; single-day level, no count target)
    case weekly         // period task: weekly (count target)
    case monthly        // period task: monthly (count target)

    public var id: String { rawValue }
}

/// User actions (state machine input).
@frozen public enum TaskAction: String, Codable, CaseIterable {
    case complete   // check-in: always done at once (counted=true), review or not; with review required it enters .awaiting pending quality review
    case pass       // review: pass
    case fail       // review: fail (still counts as done, only the quality differs)
    case revoke     // revoke: delete the day's record, back to not done; also the inverse of restore (un-skip)
    case skip       // single-day exemption: skip a day (single-day tasks drop the expected day; period tasks lose one doable day)
}

// MARK: - Pure value types

/// Task (configuration + type + switches; no mutable state — all status is derived)
public struct Task: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var type: TaskType
    public var acceptanceRequired: Bool       // review-required switch: when on, check-in enters awaiting and needs a pass / fail review
    public var note: String?
    public var targetDate: String?            // specificDate only: 'YYYY-MM-DD'
    public var targetWeekday: Int?            // weeklyDay only: 1=Monday ... 7=Sunday
    public var targetCount: Int?              // weekly/monthly only: count target (>=1)
    public var endDate: String?               // period task optional end date 'YYYY-MM-DD' (nil = never expires)
    public var createdAt: String              // ISO datetime (local)

    public init(id: String,
                name: String,
                type: TaskType,
                acceptanceRequired: Bool,
                note: String? = nil,
                targetDate: String? = nil,
                targetWeekday: Int? = nil,
                targetCount: Int? = nil,
                endDate: String? = nil,
                createdAt: String) {
        self.id = id
        self.name = name
        self.type = type
        self.acceptanceRequired = acceptanceRequired
        self.note = note
        self.targetDate = targetDate
        self.targetWeekday = targetWeekday
        self.targetCount = targetCount
        self.endDate = endDate
        self.createdAt = createdAt
    }
}
