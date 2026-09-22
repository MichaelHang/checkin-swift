import SwiftUI
import SwiftData
import CheckinCore

/// Check-in — native macOS app entry point (Swift 6.3 + SwiftUI + SwiftData, macOS 26+).
///
/// - Configures the `ModelContainer` (`CheckinContainer` with `PersistedTask` / `PersistedCheckinRecord`).
/// - Window can shrink to ≈390pt (`defaultMinSize(width: 390)`); standard traffic lights / zoom / close.
/// - iCloud sync reserved: switch the `ModelConfiguration` below to CloudKit (see CheckinRepository).
@main
struct CheckinApp: App {

    let container: ModelContainer

    init() {
        let schema = Schema([
            PersistedTask.self,
            PersistedCheckinRecord.self
        ])
        // Pin the store location explicitly (no reliance on the SwiftData default path):
        // ~/Library/Application Support/CheckinApp/checkin.store
        // Rationale: a known data location that can be backed up as a whole folder.
        let storeURL = Self.makeStoreURL()
        // iCloud extension point: replace with
        //   ModelConfiguration(for: schema, cloudKitDatabase: .automatic)
        // or ModelConfiguration(cloudKitDatabase: .automatic) and set the container to .cloudKit("iCloud.com.checkin.app")
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        do {
            // Enable lightweight migration: legacy stores (v1/v2 schema) upgrade to the current v3 at launch, avoiding crashes / data loss
            container = try ModelContainer(for: schema, migrationPlan: CheckinMigrationPlan.self, configurations: [configuration])
        } catch {
            // Fallback: migration failed (historical schema does not match the rebuilt schema). Never delete
            // the on-disk store — keep it so data can be recovered from a backup; the error below gives clear guidance.
            fatalError("无法创建/迁移 ModelContainer（\(Constants.containerName)）：\(error)。数据文件：\(storeURL.path)。若曾清过 Application Support/\(Constants.storeFolderName) 目录，旧数据已物理删除；可用「备份」tab 导出的 JSON 还原。")
        }
    }

    /// Pinned store path: ~/Library/Application Support/CheckinApp/checkin.store
    /// Creates the folder if missing (SwiftData does not create intermediate directories).
    private static func makeStoreURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent(Constants.storeFolderName, isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let target = folder.appendingPathComponent(Constants.storeFileName, isDirectory: false)
        // One-time relocation: earlier builds did not pin a URL, so SwiftData defaulted to
        // Application Support/default.store. When the new location is empty and the legacy store exists,
        // copy the whole set (store/-wal/-shm) so an upgrade cannot look like data loss.
        if !fm.fileExists(atPath: target.path) {
            Self.migrateLegacyStore(to: target)
        }
        return target
    }

    /// Copies the legacy default store `default.store` to the new location as a whole set (store / -wal / -shm — all three files are required).
    private static func migrateLegacyStore(to target: URL) {
        let fm = FileManager.default
        let legacy = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Constants.legacyStoreFileName, isDirectory: false)
        guard fm.fileExists(atPath: legacy.path) else { return }
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: legacy.path + suffix)
            let dst = URL(fileURLWithPath: target.path + suffix)
            guard fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) else { continue }
            try? fm.copyItem(at: src, to: dst)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
        }
        // Window can shrink to ≈390pt (min size enforced by RootView's .frame(minWidth:minHeight:))
        .windowResizability(.contentMinSize)
    }
}
