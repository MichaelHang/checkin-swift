import Foundation
import SwiftData
import CheckinCore

/// SwiftData persisted task entity (persistence only; no mutable state).
///
/// `typeRaw` stores the enum raw value; `toValue` maps back to the value type `Task`
/// for the pure-function layer.
@Model
final class PersistedTask {
    @Attribute(.unique) var id: String
    var name: String
    var typeRaw: String               // enum rawValue
    var acceptanceRequired: Bool
    var note: String?
    var targetDate: String?
    var targetWeekday: Int?          // weeklyDay only: 1=Monday ... 7=Sunday
    var targetCount: Int?
    var endDate: String?             // period task optional end date 'YYYY-MM-DD'
    var createdAt: String

    init(from t: Task) {
        self.id = t.id
        self.name = t.name
        self.typeRaw = t.type.rawValue
        self.acceptanceRequired = t.acceptanceRequired
        self.note = t.note
        self.targetDate = t.targetDate
        self.targetWeekday = t.targetWeekday
        self.targetCount = t.targetCount
        self.endDate = t.endDate
        self.createdAt = t.createdAt
    }

    /// Maps back to the value type (for the pure-function layer)
    var toValue: Task {
        Task(id: id,
             name: name,
             type: TaskType(rawValue: typeRaw) ?? .daily,
             acceptanceRequired: acceptanceRequired,
             note: note,
             targetDate: targetDate,
             targetWeekday: targetWeekday,
             targetCount: targetCount,
             endDate: endDate,
             createdAt: createdAt)
    }
}
