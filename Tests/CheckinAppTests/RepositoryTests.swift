import XCTest
import SwiftData
import CheckinCore
@testable import CheckinApp

/// Task CRUD pipeline verification (focuses on locking `updateTask` field completeness).
///
/// `updateTask` once dropped `targetWeekday`: editing a weekly-day task's weekday and saving
/// silently lost the change (while `importJSON` in the same file did copy it). These tests assert
/// every editable field one by one, so adding a new PersistedTask field and forgetting to copy it
/// turns red here.
@MainActor
final class RepositoryTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkin-repo-\(UUID().uuidString).store")
        let schema = Schema([PersistedTask.self, PersistedCheckinRecord.self])
        let config = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(
            for: schema,
            migrationPlan: CheckinMigrationPlan.self,
            configurations: [config]
        )
    }

    /// Editing a task must persist every editable field (including targetWeekday).
    func testUpdateTaskPersistsEveryEditableField() throws {
        let container = try makeContainer()
        let repo = CheckinRepository(modelContext: container.mainContext)

        var task = Task(
            id: "upd-1", name: "背单词", type: .weeklyDay,
            acceptanceRequired: false, createdAt: "2026-09-01 08:00:00"
        )
        task.targetWeekday = 1
        repo.addTask(task)

        task.name = "背单词（改）"
        task.type = .weekly
        task.acceptanceRequired = true
        task.note = "每天 20 个"
        task.targetDate = "2026-10-01"
        task.targetWeekday = 3
        task.targetCount = 5
        task.endDate = "2026-12-31"
        repo.updateTask(task)

        let persisted = try XCTUnwrap(repo.fetchTasks().first { $0.id == "upd-1" })
        XCTAssertEqual(persisted.name, "背单词（改）")
        XCTAssertEqual(persisted.typeRaw, TaskType.weekly.rawValue)
        XCTAssertEqual(persisted.acceptanceRequired, true)
        XCTAssertEqual(persisted.note, "每天 20 个")
        XCTAssertEqual(persisted.targetDate, "2026-10-01")
        XCTAssertEqual(persisted.targetWeekday, 3,
                       "updateTask 漏拷 targetWeekday 会让「编辑每周某天」静默失效")
        XCTAssertEqual(persisted.targetCount, 5)
        XCTAssertEqual(persisted.endDate, "2026-12-31")
    }

    /// createdAt is part of a task's identity; editing must not change it.
    func testUpdateTaskKeepsOriginalCreatedAt() throws {
        let container = try makeContainer()
        let repo = CheckinRepository(modelContext: container.mainContext)

        var task = Task(
            id: "upd-2", name: "跑步", type: .daily,
            acceptanceRequired: false, createdAt: "2026-05-01 07:30:00"
        )
        repo.addTask(task)

        task.name = "跑步（改）"
        repo.updateTask(task)

        let persisted = try XCTUnwrap(repo.fetchTasks().first { $0.id == "upd-2" })
        XCTAssertEqual(persisted.createdAt, "2026-05-01 07:30:00", "编辑不应触碰 createdAt")
    }
}
