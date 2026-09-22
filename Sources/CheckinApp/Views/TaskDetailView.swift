import SwiftUI
import SwiftData
import CheckinCore

/// Task detail / review panel: view status, check-in history, and streak; perform
/// check-in / review / revoke.
struct TaskDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let taskId: String
    /// The day passed when opening details from a calendar past day; other entries (today /
    /// period tab) default to today. Single-day tasks (daily / weeklyDay / specific date)
    /// use it as refDate to look up that day's records; period tasks (weekly / monthly)
    /// always use now / periodKey and ignore it.
    var workingDate: Date = DateUtil.now()

    @Query private var persistedTasks: [PersistedTask]
    @Query private var persistedRecords: [PersistedCheckinRecord]

    @State private var taskVM = TaskViewModel()
    @State private var periodVM = PeriodViewModel()
    @State private var statsVM = StatsViewModel()
    @State private var showEdit = false
    @State private var confirmDelete = false

    private var task: Task? {
        persistedTasks.first { $0.id == taskId }?.toValue
    }
    private var records: [CheckinRecord] {
        persistedRecords.map { $0.toValue }
    }
    private var today: String { DateUtil.localDate(DateUtil.now()) }
    private var now: Date { DateUtil.now() }

    var body: some View {
        Group {
            if let task {
                content(task)
            } else {
                Text("任务不存在").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func content(_ task: Task) -> some View {
        let isPeriod = (task.type == .weekly || task.type == .monthly)
        let refDate = isPeriod ? now : workingDate
        let statusDate = isPeriod ? today : DateUtil.localDate(workingDate)
        let status = taskVM.statusOf(task, records: records, date: statusDate)
        let progress = isPeriod ? periodVM.progressFor(task, records: records, now: now) : nil
        let hasAwait = taskVM.hasAwaiting(task, records: records, now: now)
        let statusTitle = isPeriod ? "今日状态"
            : (DateUtil.localDate(workingDate) == today ? "今日状态" : "\(DateUtil.localDate(workingDate)) 状态")

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Explicit header (matching TaskFormView's sheet pattern: title + edit + close)
                HStack {
                    Text(task.name)
                        .font(.title.weight(.semibold))
                    Spacer()
                    Button("编辑") { showEdit = true }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("编辑任务：\(task.name)")
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("关闭")
                }

                // Basic info
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        infoRow("类型", Constants.taskTypeLabel(task.type))
                        infoRow("需要过关", task.acceptanceRequired ? "是" : "否")
                        if let note = task.note, !note.isEmpty {
                            infoRow("备注", note)
                        }
                        if task.type == .specificDate, let td = task.targetDate {
                            infoRow("指定日期", td)
                        }
                        if task.type == .weeklyDay, let wd = task.targetWeekday {
                            infoRow("重复", "每\(DateUtil.weekdayLabel(wd))")
                        }
                        if let tc = task.targetCount {
                            infoRow("次数目标", "\(tc)")
                        }
                        if let ed = task.endDate {
                            infoRow("结束时间", ed)
                        }
                    }
                }

                // Status
                GlassCard {
                    HStack {
                        Text(statusTitle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Label(Constants.taskStatusLabel(status),
                              systemImage: status.iconName)
                            .foregroundStyle(status.color)
                    }
                }

                // Daily task streak
                if task.type == .daily {
                    GlassCard {
                        HStack {
                            Text("连续天数").foregroundStyle(.secondary)
                            Spacer()
                            Label("连续 \(statsVM.streakFor(task, records: records)) 天",
                                  systemImage: "flame.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // Action buttons
                if isPeriod {
                    if let progress {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("本周期进度：\(progress.done)/\(progress.target)（\(progress.percent)%）")
                                Text("状态：\(Constants.periodStatusLabel(progress.status))")
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Button("打卡") { taskVM.complete(task, refDate: refDate, context: modelContext) }
                                        .buttonStyle(.borderedProminent)
                                        .accessibilityLabel("打卡：\(task.name)")
                                    if hasAwait {
                                        Button("过关") { taskVM.pass(task, refDate: refDate, context: modelContext) }
                                            .buttonStyle(.borderedProminent)
                                            .tint(.green)
                                            .accessibilityLabel("过关：\(task.name)")
                                        Button("没过关") { taskVM.fail(task, refDate: refDate, context: modelContext) }
                                            .buttonStyle(.borderedProminent)
                                            .tint(.yellow)
                                            .accessibilityLabel("没过关：\(task.name)")
                                        Button("撤销") { taskVM.revoke(task, refDate: refDate, context: modelContext) }
                                            .buttonStyle(.bordered)
                                            .accessibilityLabel("撤销：\(task.name)")
                                    }
                                    // Single-day exemption: skip today (refDate is now, matching the period actions above)
                                    Button("跳过今天") { taskVM.skip(task, refDate: refDate, context: modelContext) }
                                        .buttonStyle(.bordered)
                                        .accessibilityLabel("跳过今天：\(task.name)")
                                }
                            }
                        }
                    }
                } else {
                    // On a future day, the check-in button must be hidden for single-day tasks —
                    // see `CalendarDayPolicy.canAct`. Skip / restore are exempt (`canSkip` is always
                    // true): skipping a future day ahead of time, and undoing that skip, are legitimate.
                    let canAct = CalendarDayPolicy.canAct(selected: refDate, now: now)
                    let canSkip = CalendarDayPolicy.canSkip(selected: refDate, now: now)
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            if !canAct {
                                HStack {
                                    Image(systemName: "clock.badge")
                                        .foregroundStyle(.secondary)
                                    Text("未到（\(DateUtil.localDate(refDate))）")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                            }
                            HStack(spacing: 8) {
                                switch status {
                                case .pending:
                                    if canAct {
                                        Button("完成") { taskVM.complete(task, refDate: refDate, context: modelContext) }
                                            .buttonStyle(.borderedProminent)
                                            .accessibilityLabel("完成：\(task.name)")
                                    }
                                    if canSkip {
                                        Button("跳过") { taskVM.skip(task, refDate: refDate, context: modelContext) }
                                            .buttonStyle(.bordered)
                                            .accessibilityLabel("跳过：\(task.name)")
                                    }
                                case .awaiting:
                                    Button("过关") { taskVM.pass(task, refDate: refDate, context: modelContext) }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.green)
                                        .accessibilityLabel("过关：\(task.name)")
                                    Button("没过关") { taskVM.fail(task, refDate: refDate, context: modelContext) }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.yellow)
                                        .accessibilityLabel("没过关：\(task.name)")
                                case .passed, .failed:
                                    EmptyView()
                                case .skipped:
                                    Text("已跳过")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                if status != .pending && status != .skipped {
                                    Button("撤销") { taskVM.revoke(task, refDate: refDate, context: modelContext) }
                                        .buttonStyle(.bordered)
                                        .accessibilityLabel("撤销：\(task.name)")
                                }
                                if status == .skipped && canSkip {
                                    // Restore = revoke (gated by canSkip, not canAct, so a future-day skip can be undone)
                                    Button("恢复") { taskVM.revoke(task, refDate: refDate, context: modelContext) }
                                        .buttonStyle(.bordered)
                                        .accessibilityLabel("恢复：\(task.name)")
                                }
                            }
                        }
                    }
                }

                sectionHeader("打卡历史")
                let history = records
                    .filter { $0.taskId == task.id }
                    .sorted { $0.date > $1.date }
                if history.isEmpty {
                    Text("暂无记录").font(.caption).foregroundStyle(.secondary).padding(10)
                } else {
                    ForEach(history) { r in
                        GlassCard(cornerRadius: 12) {
                            HStack {
                                Text(r.date)
                                Spacer()
                                if let pk = r.periodKey { Text(pk).foregroundStyle(.secondary) }
                                Text(Constants.taskStatusLabel(r.status))
                                    .foregroundStyle(r.status.color)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                Button {
                    confirmDelete = true
                } label: {
                    Text("删除任务")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(16)
        }
        .alert("确认删除", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                statsVM.deleteTask(id: task.id, context: modelContext)
                dismiss()
            }
        } message: {
            Text("删除后该任务及其全部打卡记录将不可恢复。")
        }
        .sheet(isPresented: $showEdit) {
            TaskFormView(editTask: task)
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(.primary)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
