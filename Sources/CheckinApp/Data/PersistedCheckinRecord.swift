import Foundation
import SwiftData
import CheckinCore

/// SwiftData persisted check-in record entity (persistence only).
///
/// `statusRaw` stores the enum raw value; `toValue` maps back to the value type
/// `CheckinRecord` for the pure-function layer.
@Model
final class PersistedCheckinRecord {
    @Attribute(.unique) var id: String
    var taskId: String
    var date: String
    var statusRaw: String
    var periodKey: String?
    var counted: Bool
    var createdAt: String

    init(from r: CheckinRecord) {
        self.id = r.id
        self.taskId = r.taskId
        self.date = r.date
        self.statusRaw = r.status.rawValue
        self.periodKey = r.periodKey
        self.counted = r.counted
        self.createdAt = r.createdAt
    }

    var toValue: CheckinRecord {
        CheckinRecord(id: id,
                      taskId: taskId,
                      date: date,
                      // decode instead of a direct rawValue init: legacy "completed" migrates to .passed
                      status: TaskStatus.decode(raw: statusRaw),
                      periodKey: periodKey,
                      counted: counted,
                      createdAt: createdAt)
    }
}
