import XCTest
import SwiftData
import CheckinCore
@testable import CheckinApp

/// SwiftData lightweight migration verification: ensures historical stores (v1/v2 schema) upgrade
/// to the current v3 without data loss and with new fields filled as nil.
///
/// Root cause of "all tasks gone after opening the app": there was previously no migration setup,
/// so old stores incompatible with the new schema would crash or wipe. These tests round-trip a
/// real on-disk store: write old data under the v1 schema, reopen under the current v3 schema +
/// migration plan, and assert the tasks survive with the new columns (targetWeekday/endDate) nil.
@MainActor
final class MigrationTests: XCTestCase {

    /// Writes an old store under the v1 schema, reopens with v3 + the migration plan, verifies full data migration.
    func testV1StoreMigratesToV3WithoutDataLoss() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkin-migration-v1-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        // 1) Write the old store under the v1 schema (v1 fields only, no targetWeekday/endDate)
        let v1Schema = Schema([CheckinSchemaV1.PersistedTask.self, PersistedCheckinRecord.self])
        let v1Config = ModelConfiguration(schema: v1Schema, url: url)
        let v1Container = try ModelContainer(for: v1Schema, configurations: [v1Config])
        let v1Task = CheckinSchemaV1.PersistedTask(
            id: "t-mig-1", name: "读书", typeRaw: "daily",
            acceptanceRequired: false, note: nil, targetDate: nil,
            targetCount: nil, createdAt: "2026-01-01"
        )
        v1Container.mainContext.insert(v1Task)
        try v1Container.mainContext.save()

        // 2) Reopen the same store under the current v3 schema + migration plan
        let currentSchema = Schema([PersistedTask.self, PersistedCheckinRecord.self])
        let currentConfig = ModelConfiguration(schema: currentSchema, url: url)
        let migrated = try ModelContainer(
            for: currentSchema,
            migrationPlan: CheckinMigrationPlan.self,
            configurations: [currentConfig]
        )

        let tasks = try migrated.mainContext.fetch(FetchDescriptor<PersistedTask>())
        XCTAssertEqual(tasks.count, 1, "迁移后任务数应为 1（数据不丢）")
        let t = tasks.first
        XCTAssertEqual(t?.id, "t-mig-1")
        XCTAssertEqual(t?.name, "读书")
        XCTAssertNil(t?.targetWeekday, "v1 旧数据 targetWeekday 应为 nil")
        XCTAssertNil(t?.endDate, "v1 旧数据 endDate 应为 nil")
    }

    /// Writes an old store under the v2 schema (has targetWeekday, no endDate), reopens with v3,
    /// verifies only endDate fills as nil.
    func testV2StoreMigratesToV3WithoutDataLoss() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkin-migration-v2-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let v2Schema = Schema([CheckinSchemaV2.PersistedTask.self, PersistedCheckinRecord.self])
        let v2Config = ModelConfiguration(schema: v2Schema, url: url)
        let v2Container = try ModelContainer(for: v2Schema, configurations: [v2Config])
        let v2Task = CheckinSchemaV2.PersistedTask(
            id: "t-mig-2", name: "健身", typeRaw: "weeklyDay",
            acceptanceRequired: true, note: nil, targetDate: nil,
            targetWeekday: 3, targetCount: nil, createdAt: "2026-02-02"
        )
        v2Container.mainContext.insert(v2Task)
        try v2Container.mainContext.save()

        let currentSchema = Schema([PersistedTask.self, PersistedCheckinRecord.self])
        let currentConfig = ModelConfiguration(schema: currentSchema, url: url)
        let migrated = try ModelContainer(
            for: currentSchema,
            migrationPlan: CheckinMigrationPlan.self,
            configurations: [currentConfig]
        )

        let tasks = try migrated.mainContext.fetch(FetchDescriptor<PersistedTask>())
        XCTAssertEqual(tasks.count, 1, "迁移后任务数应为 1（数据不丢）")
        let t = tasks.first
        XCTAssertEqual(t?.id, "t-mig-2")
        XCTAssertEqual(t?.name, "健身")
        XCTAssertEqual(t?.targetWeekday, 3, "v2 旧数据 targetWeekday 应保留")
        XCTAssertNil(t?.endDate, "v2 旧数据 endDate 应为 nil")
    }

    /// A fresh v3 store must build normally (no error / crash when no old store exists).
    func testFreshV3StoreBuilds() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkin-fresh-v3-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([PersistedTask.self, PersistedCheckinRecord.self])
        let config = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: CheckinMigrationPlan.self,
            configurations: [config]
        )
        let tasks = try container.mainContext.fetch(FetchDescriptor<PersistedTask>())
        XCTAssertEqual(tasks.count, 0, "全新 store 应为空")
    }

    /// Simulates real usage: insert a task into a fresh store and save, reopen at the same URL,
    /// assert the task survives. Verifies that re-entered data persists across restarts.
    func testV3StorePersistsAcrossReopen() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkin-persist-v3-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([PersistedTask.self, PersistedCheckinRecord.self])
        let config = ModelConfiguration(schema: schema, url: url)

        // First session: insert and save
        let container = try ModelContainer(
            for: schema,
            migrationPlan: CheckinMigrationPlan.self,
            configurations: [config]
        )
        let task = CheckinCore.Task(
            id: "persist-1", name: "喝水", type: .daily,
            acceptanceRequired: false, createdAt: "2026-09-08 00:00:00"
        )
        container.mainContext.insert(PersistedTask(from: task))
        try container.mainContext.save()

        // Second session (simulated restart): reopen at the same URL
        let reopened = try ModelContainer(
            for: schema,
            migrationPlan: CheckinMigrationPlan.self,
            configurations: [config]
        )
        let tasks = try reopened.mainContext.fetch(FetchDescriptor<PersistedTask>())
        XCTAssertEqual(tasks.count, 1, "重开后任务应仍在（持久化生效）")
        XCTAssertEqual(tasks.first?.id, "persist-1")
        XCTAssertEqual(tasks.first?.name, "喝水")
    }
}
