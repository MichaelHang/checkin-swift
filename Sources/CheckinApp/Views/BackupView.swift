import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import CheckinCore

// Compiled in debug builds only: on Release the whole backup UI (and its export/import
// entries) is kept out of the binary. Matches the `#if DEBUG` branches in RootView.
#if DEBUG

/// Data backup: JSON export / import.
///
/// The JSON backup is not tied to the SwiftData schema version (it stores only plain value
/// types Task / CheckinRecord), so it stays importable even after model changes — the
/// portable safety net the database file itself cannot provide.
struct BackupView: View {
    @Query(sort: \PersistedTask.createdAt, order: .forward) private var tasks: [PersistedTask]
    @Query private var records: [PersistedCheckinRecord]
    @Environment(\.modelContext) private var modelContext

    @State private var message: String = ""
    @State private var isError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("数据备份")
                .font(.title2)
                .fontWeight(.semibold)

            Text("当前：\(tasks.count) 个任务 · \(records.count) 条打卡记录")
                .foregroundStyle(.secondary)

            Text("导出为 JSON 存到安全位置；万一数据被删或调试出问题，用「导入备份」即可还原。JSON 不绑定数据库版本，比直接复制数据库文件更稳。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("导出备份…") { exportBackup() }
                Button("导入备份…") { importBackup() }
            }

            if !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(isError ? Color.red : Color.green)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 380, minHeight: 260)
        .navigationTitle("备份")
    }

    private var repo: CheckinRepository { CheckinRepository(modelContext: modelContext) }

    // MARK: - Export

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "checkin-backup-\(Self.timestamp()).json"
        panel.allowedContentTypes = [UTType.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let json = try repo.exportJSON()
            try json.write(to: url, atomically: true, encoding: .utf8)
            message = "已导出到：\(url.path)"
            isError = false
        } catch {
            message = "导出失败：\(error.localizedDescription)"
            isError = true
        }
    }

    // MARK: - Import

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let json = try String(contentsOf: url, encoding: .utf8)
            let result = try repo.importJSON(json)
            message = "导入完成：新增 \(result.tasks) 个任务、\(result.records) 条记录（已存在的按 id 更新，不会删除现有数据）"
            isError = false
        } catch {
            message = "导入失败：\(error.localizedDescription)"
            isError = true
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: Date())
    }
}

#endif
