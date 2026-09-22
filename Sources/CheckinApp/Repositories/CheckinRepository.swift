import Foundation
import SwiftData
import CheckinCore

/// Backup file structure: `{ "tasks": [Task], "records": [CheckinRecord] }`, matching the value types (all Codable).
struct CheckinBackup: Codable {
    var tasks: [Task]
    var records: [CheckinRecord]
}

/// Persistence orchestration: SwiftData CRUD + the pure-function layer + entity <-> value type mapping.
///
/// Writes go through `StateMachine.applyAction` (`toValue` -> pure function -> write back
/// `PersistedCheckinRecord`); deleting a task cascade-deletes its records.
struct CheckinRepository {

    let modelContext: ModelContext

    // MARK: - Queries

    func fetchTasks() -> [PersistedTask] {
        (try? modelContext.fetch(FetchDescriptor<PersistedTask>())) ?? []
    }

    func fetchRecords(taskId: String? = nil) -> [PersistedCheckinRecord] {
        var descriptor = FetchDescriptor<PersistedCheckinRecord>()
        if let taskId {
            descriptor.predicate = #Predicate { $0.taskId == taskId }
        }
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Task CRUD

    func addTask(_ task: Task) {
        modelContext.insert(PersistedTask(from: task))
        saveOrLog()
    }

    func updateTask(_ task: Task) {
        guard let existing = fetchTasks().first(where: { $0.id == task.id }) else { return }
        existing.name = task.name
        existing.typeRaw = task.type.rawValue
        existing.acceptanceRequired = task.acceptanceRequired
        existing.note = task.note
        existing.targetDate = task.targetDate
        existing.targetWeekday = task.targetWeekday
        existing.targetCount = task.targetCount
        existing.endDate = task.endDate
        saveOrLog()
    }

    /// Cascade-deletes a task and all of its check-in records
    func deleteTask(id: String) {
        for r in fetchRecords(taskId: id) {
            modelContext.delete(r)
        }
        if let t = fetchTasks().first(where: { $0.id == id }) {
            modelContext.delete(t)
        }
        saveOrLog()
    }

    // MARK: - State machine actions (write-back)

    /// Applies an action (complete / pass / fail / revoke / skip) to a task through the StateMachine
    /// pure function and writes the result back.
    /// skip (single-day exemption) goes through the same dictionary reconciliation: it writes a
    /// .skipped record, no extra branch needed.
    func applyAction(taskId: String, action: TaskAction, refDate: Date) {
        guard let persisted = fetchTasks().first(where: { $0.id == taskId }) else { return }
        let value = persisted.toValue
        let currentRecords = fetchRecords(taskId: taskId).map { $0.toValue }

        let newRecords = StateMachine.applyAction(
            task: value,
            records: currentRecords,
            action: action,
            refDate: refDate
        )

        let newById: [String: CheckinRecord] = Dictionary(uniqueKeysWithValues: newRecords.map { ($0.id, $0) })
        let oldById: [String: PersistedCheckinRecord] = Dictionary(uniqueKeysWithValues: fetchRecords(taskId: taskId).map { ($0.id, $0) })

        // Insert / update
        for (id, newVal) in newById {
            if let p = oldById[id] {
                p.statusRaw = newVal.status.rawValue
                p.counted = newVal.counted
                p.periodKey = newVal.periodKey
                p.date = newVal.date
                p.taskId = newVal.taskId
                p.createdAt = newVal.createdAt
            } else {
                modelContext.insert(PersistedCheckinRecord(from: newVal))
            }
        }
        // Delete records that no longer exist
        for (id, p) in oldById where newById[id] == nil {
            modelContext.delete(p)
        }

        saveOrLog()
    }

    // MARK: - Save (failures must be visible)

    /// Saves and prints failures. A silent `try? modelContext.save()` swallows errors, making the UI
    /// look like data persisted when it did not — save errors must be visible.
    private func saveOrLog() {
        do {
            try modelContext.save()
        } catch {
            print("⚠️ [CheckinRepository] 保存失败：\(error)")
        }
    }

    // MARK: - Backup (JSON export / import)

    /// Exports all data as a JSON string: `{ "tasks": [Task], "records": [CheckinRecord] }`
    /// (matches the value types so it can be imported back).
    func exportJSON() throws -> String {
        let payload = CheckinBackup(
            tasks: fetchTasks().map { $0.toValue },
            records: fetchRecords().map { $0.toValue }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(payload), as: UTF8.self)
    }

    /// Imports JSON to restore data: idempotent upsert by id (update existing, insert new; never
    /// deletes existing data). JSON backups are not tied to a schema version, so they are safer than
    /// copying the `.store` directly — they still import after schema changes.
    /// - Returns: (tasks inserted, records inserted)
    @discardableResult
    func importJSON(_ json: String) throws -> (tasks: Int, records: Int) {
        let payload = try JSONDecoder().decode(CheckinBackup.self, from: Data(json.utf8))

        let existingTasks = Dictionary(uniqueKeysWithValues: fetchTasks().map { ($0.id, $0) })
        var taskInserts = 0
        for t in payload.tasks {
            if let existing = existingTasks[t.id] {
                existing.name = t.name
                existing.typeRaw = t.type.rawValue
                existing.acceptanceRequired = t.acceptanceRequired
                existing.note = t.note
                existing.targetDate = t.targetDate
                existing.targetWeekday = t.targetWeekday
                existing.targetCount = t.targetCount
                existing.endDate = t.endDate
                existing.createdAt = t.createdAt
            } else {
                modelContext.insert(PersistedTask(from: t))
                taskInserts += 1
            }
        }

        let existingRecords = Dictionary(uniqueKeysWithValues: fetchRecords().map { ($0.id, $0) })
        var recordInserts = 0
        for r in payload.records {
            if let existing = existingRecords[r.id] {
                existing.taskId = r.taskId
                existing.date = r.date
                existing.statusRaw = r.status.rawValue
                existing.periodKey = r.periodKey
                existing.counted = r.counted
                existing.createdAt = r.createdAt
            } else {
                modelContext.insert(PersistedCheckinRecord(from: r))
                recordInserts += 1
            }
        }

        saveOrLog()
        return (taskInserts, recordInserts)
    }


    // MARK: - CloudKit extension point
    //
    // To enable iCloud sync, switch the ModelConfiguration in CheckinApp.swift to:
    //   ModelConfiguration(for: schema, cloudKitDatabase: .automatic)
    // or set the container: .cloudKit("iCloud.com.checkin.app")
    // No changes to PersistedTask / PersistedCheckinRecord fields are needed.
}
