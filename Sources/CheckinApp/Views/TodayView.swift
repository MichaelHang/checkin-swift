import SwiftUI
import SwiftData
import CheckinCore

/// Today view: aggregates daily tasks, today's specific-date tasks, and period progress cards.
///
/// Data comes in via `@Query` and is rendered through pure derivation; status/progress is
/// fully derived, so it auto-resets on a new day or new period.
struct TodayView: View {
    @Query(sort: \PersistedTask.createdAt, order: .forward) private var persistedTasks: [PersistedTask]
    @Query private var persistedRecords: [PersistedCheckinRecord]
    @Environment(\.modelContext) private var modelContext

    @State private var vm = TaskViewModel()
    @State private var showForm = false
    @State private var detailTaskId: String? = nil

    private var tasks: [Task] { persistedTasks.map { $0.toValue } }
    private var records: [CheckinRecord] { persistedRecords.map { $0.toValue } }
    private var today: String { DateUtil.localDate(DateUtil.now()) }
    private let now = DateUtil.now()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("今日任务")
                let dailies = vm.dailyTasks(tasks, refDate: now).filter { !DateUtil.isEnded($0, on: now) }
                if dailies.isEmpty {
                    emptyHint("暂无每日任务，点右上角 + 添加")
                } else {
                    ForEach(dailies) { task in
                        GlassTaskCard(
                            task: task,
                            status: vm.statusOf(task, records: records, date: today),
                            onComplete: { vm.complete(task, refDate: now, context: modelContext) },
                            onPass: { vm.pass(task, refDate: now, context: modelContext) },
                            onFail: { vm.fail(task, refDate: now, context: modelContext) },
                            onRevoke: { vm.revoke(task, refDate: now, context: modelContext) },
                            onTap: { detailTaskId = task.id },
                            onSkip: { vm.skip(task, refDate: now, context: modelContext) }
                        )
                    }
                }

                let specific = vm.specificTasksForToday(tasks, refDate: now).filter { !DateUtil.isEnded($0, on: now) }
                if !specific.isEmpty {
                    sectionHeader("指定日任务")
                    ForEach(specific) { task in
                        GlassTaskCard(
                            task: task,
                            status: vm.statusOf(task, records: records, date: today),
                            onComplete: { vm.complete(task, refDate: now, context: modelContext) },
                            onPass: { vm.pass(task, refDate: now, context: modelContext) },
                            onFail: { vm.fail(task, refDate: now, context: modelContext) },
                            onRevoke: { vm.revoke(task, refDate: now, context: modelContext) },
                            onTap: { detailTaskId = task.id },
                            onSkip: { vm.skip(task, refDate: now, context: modelContext) }
                        )
                    }
                }

                let periods = vm.periodTasks(tasks).filter { !DateUtil.isEnded($0, on: now) }
                if !periods.isEmpty {
                    sectionHeader("周期任务进度")
                    ForEach(periods) { task in
                        let progress = vm.progressFor(task, records: records, now: DateUtil.now())
                        // Show "skip today" only if the task has no record today yet —
                        // otherwise it would overwrite today's check-in (StateMachine.skip
                        // deletes the day's records first).
                        let hasTodayRecord = records.contains { $0.taskId == task.id && $0.date == today }
                        let periodOnSkip: (() -> Void)? = hasTodayRecord
                            ? nil
                            : { vm.skip(task, refDate: now, context: modelContext) }
                        GlassPeriodCard(
                            task: task,
                            progress: progress,
                            hasAwaiting: vm.hasAwaiting(task, records: records, now: DateUtil.now()),
                            onCheckin: { vm.complete(task, refDate: now, context: modelContext) },
                            onPass: { vm.pass(task, refDate: now, context: modelContext) },
                            onFail: { vm.fail(task, refDate: now, context: modelContext) },
                            onRevoke: { vm.revoke(task, refDate: now, context: modelContext) },
                            onTap: { detailTaskId = task.id },
                            onSkip: periodOnSkip
                        )
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("今日")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showForm = true }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建任务")
            }
        }
        .sheet(isPresented: $showForm) {
            TaskFormView(editTask: nil)
        }
        .sheet(item: Binding(
            get: { detailTaskId.map { SelectedTask(id: $0) } },
            set: { detailTaskId = $0?.id }
        )) { wrapper in
            TaskDetailView(taskId: wrapper.id)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
    }
}

/// Identifiable wrapper required by `sheet(item:)` (keyed by task id).
struct SelectedTask: Identifiable {
    let id: String
}
