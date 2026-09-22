import XCTest
import SwiftData
import CheckinCore
@testable import CheckinApp

/// Backup pipeline verification: JSON export → import into a fresh store → full data restoration.
///
/// JSON backup is schema-independent (Task / CheckinRecord are pure Codable value types), unlike the
/// `.store` file which is tightly bound to the schema version and may fail to open after schema
/// changes — making JSON the reliable long-term restore path. These tests prove the export–import
/// round-trip is lossless.
@MainActor
final class BackupTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkin-backup-\(UUID().uuidString).store")
        let schema = Schema([PersistedTask.self, PersistedCheckinRecord.self])
        let config = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(
            for: schema,
            migrationPlan: CheckinMigrationPlan.self,
            configurations: [config]
        )
    }

    /// Exported JSON must contain all tasks and records and decode back into the same structure.
    func testExportJSONContainsAllData() throws {
        let container = try makeContainer()
        let repo = CheckinRepository(modelContext: container.mainContext)

        var task = Task(
            id: "bk-1", name: "背单词", type: .weeklyDay,
            acceptanceRequired: true, createdAt: "2026-09-09 10:00:00"
        )
        task.targetWeekday = 3
        task.targetCount = 5
        repo.addTask(task)

        let record = CheckinRecord(
            id: "bk-r-1", taskId: "bk-1", date: "2026-09-09",
            status: .passed, periodKey: "2026-W37",
            counted: true, createdAt: "2026-09-09 10:05:00"
        )
        container.mainContext.insert(PersistedCheckinRecord(from: record))
        try container.mainContext.save()

        let json = try repo.exportJSON()
        let decoded = try JSONDecoder().decode(CheckinBackup.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.tasks.count, 1, "导出应包含 1 个任务")
        XCTAssertEqual(decoded.records.count, 1, "导出应包含 1 条记录")
        XCTAssertEqual(decoded.tasks.first?.name, "背单词")
        XCTAssertEqual(decoded.tasks.first?.targetWeekday, 3, "周期性字段不得丢失")
        XCTAssertEqual(decoded.records.first?.status, .passed)
    }

    /// Importing into a fresh empty store must restore all data (the core "backup can save you" assertion).
    func testImportJSONRestoresIntoEmptyStore() throws {
        let source = try makeContainer()
        let sourceRepo = CheckinRepository(modelContext: source.mainContext)

        var task = Task(
            id: "bk-2", name: "跑步", type: .daily,
            acceptanceRequired: false, createdAt: "2026-09-09 11:00:00"
        )
        task.note = "每天 3 公里"
        sourceRepo.addTask(task)
        let record = CheckinRecord(
            id: "bk-r-2", taskId: "bk-2", date: "2026-09-09",
            status: .awaiting, periodKey: nil,
            counted: true, createdAt: "2026-09-09 11:01:00"
        )
        source.mainContext.insert(PersistedCheckinRecord(from: record))
        try source.mainContext.save()

        let json = try sourceRepo.exportJSON()

        // Import into a fresh empty store (simulates a new machine / restore after a wipe)
        let target = try makeContainer()
        let targetRepo = CheckinRepository(modelContext: target.mainContext)
        XCTAssertEqual(targetRepo.fetchTasks().count, 0, "导入前应为空")

        let result = try targetRepo.importJSON(json)
        XCTAssertEqual(result.tasks, 1, "应新增 1 个任务")
        XCTAssertEqual(result.records, 1, "应新增 1 条记录")

        let restored = targetRepo.fetchTasks().first
        XCTAssertEqual(restored?.id, "bk-2")
        XCTAssertEqual(restored?.name, "跑步")
        XCTAssertEqual(restored?.note, "每天 3 公里", "备注应还原")
        XCTAssertEqual(targetRepo.fetchRecords().first?.statusRaw, "awaiting")
    }

    /// Re-importing the same JSON must not duplicate data (idempotent upsert).
    func testImportIsIdempotent() throws {
        let container = try makeContainer()
        let repo = CheckinRepository(modelContext: container.mainContext)
        repo.addTask(Task(
            id: "bk-3", name: "冥想", type: .daily,
            acceptanceRequired: false, createdAt: "2026-09-09 12:00:00"
        ))
        let json = try repo.exportJSON()

        _ = try repo.importJSON(json)
        _ = try repo.importJSON(json)
        XCTAssertEqual(repo.fetchTasks().count, 1, "重复导入不得产生重复任务")
    }

    /// Export a skipped record → import → statusRaw is still "skipped" (skip status round-trips losslessly).
    func testExportImportRoundTripsSkippedRecord() throws {
        let source = try makeContainer()
        let sourceRepo = CheckinRepository(modelContext: source.mainContext)
        sourceRepo.addTask(Task(id: "bk-skip", name: "背单词", type: .weeklyDay,
                                acceptanceRequired: false, createdAt: "2026-09-09 10:00:00"))
        let record = CheckinRecord(id: "bk-r-skip", taskId: "bk-skip", date: "2026-09-09",
                                   status: .skipped, periodKey: nil,
                                   counted: false, createdAt: "2026-09-09 10:05:00")
        source.mainContext.insert(PersistedCheckinRecord(from: record))
        try source.mainContext.save()

        let json = try sourceRepo.exportJSON()
        let target = try makeContainer()
        let targetRepo = CheckinRepository(modelContext: target.mainContext)
        let result = try targetRepo.importJSON(json)
        XCTAssertEqual(result.records, 1, "应新增 1 条跳过记录")

        let restored = targetRepo.fetchRecords().first
        XCTAssertEqual(restored?.statusRaw, "skipped", "skipped 记录应原样还原，不得降级")
        XCTAssertEqual(restored?.counted, false, "counted=false 应保留")
    }

    /// Old exports carry status "completed" (the pre-rename value of passed):
    /// import must migrate it to .passed instead of failing the whole decode — same behavior as the
    /// `TaskStatus.decode(raw:)` used when reading the SwiftData store (the JSON path goes through
    /// TaskStatus's custom init(from:)).
    func testImportLegacyCompletedStatusMigratesToPassed() throws {
        let container = try makeContainer()
        let repo = CheckinRepository(modelContext: container.mainContext)

        let legacyJSON = """
        {
          "tasks": [
            {"id":"legacy-1","name":"旧任务","type":"daily","acceptanceRequired":false,
             "createdAt":"2026-01-01 08:00:00"}
          ],
          "records": [
            {"id":"legacy-r-1","taskId":"legacy-1","date":"2026-01-01","status":"completed",
             "counted":true,"createdAt":"2026-01-01 08:05:00"}
          ]
        }
        """
        let result = try repo.importJSON(legacyJSON)
        XCTAssertEqual(result.tasks, 1, "旧 JSON 应能完整导入，不得解码失败")
        XCTAssertEqual(result.records, 1)

        let restored = try XCTUnwrap(repo.fetchRecords().first)
        XCTAssertEqual(restored.statusRaw, "passed", "旧状态 completed 落库应为 passed")
        XCTAssertEqual(restored.counted, true)
        XCTAssertEqual(restored.toValue.status, .passed)
    }
}
