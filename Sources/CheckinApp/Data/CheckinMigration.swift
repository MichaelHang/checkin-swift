import Foundation
import SwiftData
import CheckinCore

/// SwiftData versioned schema and lightweight migration plan.
///
/// `PersistedTask` gained fields over time (`targetWeekday` for the weekly-on-a-given-weekday feature;
/// `endDate` for period end dates), but the project had no migration setup, so legacy stores were
/// incompatible with the new schema and `ModelContainer` threw at launch (crash / empty store after reset).
/// This adds VersionedSchema + SchemaMigrationPlan so legacy stores are lightweight-migrated at launch
/// (new optional columns only) instead of losing data on model changes.
///
/// Key constraint (SwiftData lightweight migration matches entities by name):
/// historical versions must declare the `@Model` as a nested type with the SAME name inside the
/// VersionedSchema enum (e.g. `CheckinSchemaV1.PersistedTask`), so its simple name stays
/// "PersistedTask" and SwiftData recognizes it as the same entity with new columns. Distinct top-level
/// class names (`PersistedTaskV1` / `PersistedTaskV2`) would count as different entities and
/// lightweight migration would not apply. The current v3 reuses the top-level
/// `PersistedTask` / `PersistedCheckinRecord` (simple names "PersistedTask" / "PersistedCheckinRecord"),
/// matching the historical versions so they are recognized as the same entities.
///
/// Version history (fields match the historical schemas):
/// - v1: original schema (no `targetWeekday` / `endDate`)
/// - v2: + `targetWeekday` (weekly on a given weekday feature)
/// - v3: + `endDate` (period end date feature; the current schema)

// MARK: - Versioned schema

enum CheckinSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [PersistedTask.self, PersistedCheckinRecord.self]
    }

    /// v1 historical task entity (no targetWeekday / endDate). Only for schema comparison during migration.
    @Model
    final class PersistedTask {
        @Attribute(.unique) var id: String
        var name: String
        var typeRaw: String
        var acceptanceRequired: Bool
        var note: String?
        var targetDate: String?
        var targetCount: Int?
        var createdAt: String

        init(id: String, name: String, typeRaw: String, acceptanceRequired: Bool,
             note: String?, targetDate: String?, targetCount: Int?, createdAt: String) {
            self.id = id
            self.name = name
            self.typeRaw = typeRaw
            self.acceptanceRequired = acceptanceRequired
            self.note = note
            self.targetDate = targetDate
            self.targetCount = targetCount
            self.createdAt = createdAt
        }
    }
}

enum CheckinSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [PersistedTask.self, PersistedCheckinRecord.self]
    }

    /// v2 historical task entity (+ targetWeekday). Only for schema comparison during migration.
    @Model
    final class PersistedTask {
        @Attribute(.unique) var id: String
        var name: String
        var typeRaw: String
        var acceptanceRequired: Bool
        var note: String?
        var targetDate: String?
        var targetWeekday: Int?
        var targetCount: Int?
        var createdAt: String

        init(id: String, name: String, typeRaw: String, acceptanceRequired: Bool,
             note: String?, targetDate: String?, targetWeekday: Int?, targetCount: Int?, createdAt: String) {
            self.id = id
            self.name = name
            self.typeRaw = typeRaw
            self.acceptanceRequired = acceptanceRequired
            self.note = note
            self.targetDate = targetDate
            self.targetWeekday = targetWeekday
            self.targetCount = targetCount
            self.createdAt = createdAt
        }
    }
}

enum CheckinSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        // Current production entities (top-level classes in PersistedTask.swift / PersistedCheckinRecord.swift);
        // their simple names match the historical versions
        [PersistedTask.self, PersistedCheckinRecord.self]
    }
}

// MARK: - Migration plan

enum CheckinMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CheckinSchemaV1.self, CheckinSchemaV2.self, CheckinSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }

    /// v1 → v2: adds optional column `targetWeekday`; lightweight migration (SwiftData infers the mapping, existing rows get nil)
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: CheckinSchemaV1.self,
        toVersion: CheckinSchemaV2.self
    )

    /// v2 → v3: adds optional column `endDate`; lightweight migration (SwiftData infers the mapping, existing rows get nil)
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: CheckinSchemaV2.self,
        toVersion: CheckinSchemaV3.self
    )
}
