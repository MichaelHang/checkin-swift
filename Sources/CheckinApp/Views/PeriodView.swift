import SwiftUI
import SwiftData
import CheckinCore

/// Period view: daily | weekly | monthly | weekly-day switching; views and edits task definitions.
///
/// This tab manages definitions only — view / edit them (move a weekday, toggle the
/// acceptance review); no check-ins, no status changes, no status display. Single-day types
/// (daily / weeklyDay) render one card per definition with no status badge and no action
/// buttons; weekly / monthly show the read-only "N times" target and period window. Tapping
/// anywhere on a card opens the edit form (`TaskFormView(editTask:)`). Per-day expansion
/// and status changes live in the calendar / today views.
struct PeriodView: View {
    @Query(sort: \PersistedTask.createdAt, order: .forward) private var persistedTasks: [PersistedTask]
    @Query private var persistedRecords: [PersistedCheckinRecord]
    @Environment(\.modelContext) private var modelContext

    @State private var vm = PeriodViewModel()
    @State private var taskVM = TaskViewModel()
    @State private var scope: TaskType = .daily
    @State private var showForm = false
    @State private var editTaskId: String? = nil

    private var tasks: [Task] { persistedTasks.map { $0.toValue } }
    private var records: [CheckinRecord] { persistedRecords.map { $0.toValue } }
    private var now: Date { DateUtil.now() }

    private var scopedTasks: [Task] {
        switch scope {
        case .weekly: return vm.weeklyTasks(tasks)
        case .monthly: return vm.monthlyTasks(tasks)
        case .weeklyDay: return vm.weeklyDayTasks(tasks)
        case .daily: return vm.dailyTasks(tasks)
        default: return []
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("范围", selection: $scope) {
                    Text("每日").tag(TaskType.daily)
                    Text("每周").tag(TaskType.weekly)
                    Text("每月").tag(TaskType.monthly)
                    Text("每周某天").tag(TaskType.weeklyDay)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Text("点击任务卡片任意位置可查看或编辑")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if scopedTasks.isEmpty {
                    Text(scope == .daily ? "暂无每日任务，点右上角 + 添加"
                         : scope == .weekly ? "暂无每周任务，点右上角 + 添加"
                         : scope == .monthly ? "暂无每月任务，点右上角 + 添加"
                         : "暂无每周某天任务，点右上角 + 添加")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                } else if scope == .daily {
                    ForEach(vm.dailyTasks(tasks)) { task in
                        let status = taskVM.statusOf(task, records: records, date: DateUtil.localDate(now))
                        GlassTaskCard(
                            task: task,
                            status: status,
                            onComplete: { taskVM.complete(task, refDate: now, context: modelContext) },
                            onPass: { taskVM.pass(task, refDate: now, context: modelContext) },
                            onFail: { taskVM.fail(task, refDate: now, context: modelContext) },
                            onRevoke: { taskVM.revoke(task, refDate: now, context: modelContext) },
                            onTap: { editTaskId = task.id },
                            showActions: false,
                            showStatus: false
                        )
                    }
                } else if scope == .weeklyDay {
                    ForEach(vm.weeklyDayTasks(tasks)) { task in
                        let occ = DateUtil.occurrenceInWeek(weekday: task.targetWeekday ?? 1, now: now)
                        let status = taskVM.statusOf(task, records: records, date: DateUtil.localDate(occ))
                        GlassTaskCard(
                            task: task,
                            status: status,
                            onComplete: { taskVM.complete(task, refDate: occ, context: modelContext) },
                            onPass: { taskVM.pass(task, refDate: occ, context: modelContext) },
                            onFail: { taskVM.fail(task, refDate: occ, context: modelContext) },
                            onRevoke: { taskVM.revoke(task, refDate: occ, context: modelContext) },
                            onTap: { editTaskId = task.id },
                            showActions: false,
                            showStatus: false
                        )
                    }
                } else {
                    ForEach(scopedTasks) { task in
                        let progress = vm.progressFor(task, records: records, now: now)
                        GlassPeriodCard(
                            task: task,
                            progress: progress,
                            hasAwaiting: vm.hasAwaiting(task, records: records, now: now),
                            windowRange: vm.periodWindowText(task, now: now),
                            onCheckin: { vm.checkin(task, context: modelContext) },
                            onPass: { vm.pass(task, context: modelContext) },
                            onFail: { vm.fail(task, context: modelContext) },
                            onRevoke: { vm.revoke(task, context: modelContext) },
                            onTap: { editTaskId = task.id },
                            showActions: false,
                            showStatus: false
                        )
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(scope == .daily ? "每日任务" : scope == .weekly ? "本周任务" : scope == .monthly ? "本月任务" : "每周某天任务")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showForm = true }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建任务")
            }
        }
        .sheet(isPresented: $showForm) {
            TaskFormView(editTask: nil, initialType: scope)
        }
        .sheet(item: Binding(
            get: { editTaskId.map { SelectedTask(id: $0) } },
            set: { editTaskId = $0?.id }
        )) { wrapper in
            if let task = tasks.first(where: { $0.id == wrapper.id }) {
                TaskFormView(editTask: task)
            }
        }
    }
}
