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
                if !hasAnyTodayContent {
                    emptyStateView
                } else {
                    todayHeader
                    todayTasksSections
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

    // MARK: - Today aggregates (shared by the header card and the lists below)

    /// Daily + weeklyDay tasks due today (ended tasks excluded) — same set the lists render.
    private var todayDailies: [Task] {
        vm.dailyTasks(tasks, refDate: now).filter { !DateUtil.isEnded($0, on: now) }
    }

    private var todaySpecifics: [Task] {
        vm.specificTasksForToday(tasks, refDate: now).filter { !DateUtil.isEnded($0, on: now) }
    }

    private var todayStatuses: [(task: Task, status: TaskStatus)] {
        (todayDailies + todaySpecifics).map { ($0, vm.statusOf($0, records: records, date: today)) }
    }

    /// Skipped tasks are exempt ("single-day waiver"): they leave both the numerator AND the
    /// denominator — same criteria as the StatsUtil slot model.
    private var todayTotal: Int { todayStatuses.count { $0.status != .skipped } }

    private var todayDone: Int {
        todayStatuses.count { $0.status != .skipped && $0.status.isDone }
    }

    private var todayPeriods: [Task] {
        vm.periodTasks(tasks).filter { !DateUtil.isEnded($0, on: now) }
    }

    /// Whether the today page has any active content at all; drives the full-page empty state.
    private var hasAnyTodayContent: Bool {
        !todayDailies.isEmpty || !todaySpecifics.isEmpty || !todayPeriods.isEmpty
    }

    /// The three sections (daily / specific-date / period), rendered when any content exists.
    @ViewBuilder
    private var todayTasksSections: some View {
        sectionHeader("今日任务")
        let dailies = todayDailies
        if dailies.isEmpty {
            emptyHint("今天没有待做的每日任务")
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

        let specific = todaySpecifics
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

        let periods = todayPeriods
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

    // MARK: - Header card (date + completion ring)

    /// One glance at "which day is it and how am I doing". Counts single-day tasks only;
    /// period tasks (weekly/monthly) keep their own progress cards below.
    private var todayHeader: some View {
        GlassCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headerDateText)
                        .font(.title3.weight(.semibold))
                    Text(headerStatusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if todayTotal > 0 {
                    progressRing
                        .accessibilityLabel("今日完成 \(todayDone)/\(todayTotal)")
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: todayDone)
    }

    private var headerDateText: String {
        let c = DateUtil.components(now)
        return "\(c.month)月\(c.day)日 " + DateUtil.weekdayLabel(DateUtil.weekdayISO(now))
    }

    private var headerStatusText: String {
        if todayTotal == 0 {
            // Distinguish "nothing scheduled" from "scheduled but all skipped today".
            return (todayDailies + todaySpecifics).isEmpty ? "今天没有安排任务" : "今日已全部跳过"
        }
        if todayDone >= todayTotal { return "今日已全部完成" }
        return "还有 \(todayTotal - todayDone) 项未完成"
    }

    /// Round progress ring with done/total in the center; turns green when all done.
    private var progressRing: some View {
        let achieved = todayTotal > 0 && todayDone >= todayTotal
        let ratio = todayTotal > 0 ? min(Double(todayDone) / Double(todayTotal), 1) : 0
        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 7)
            Circle()
                .trim(from: 0, to: ratio)
                .stroke(achieved ? Color.green : Color.accentColor,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(todayDone)/\(todayTotal)")
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(achieved ? Color.green : Color.primary)
        }
        .frame(width: 54, height: 54)
    }

    /// Full-page empty state (no active tasks at all): native placeholder + create action.
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("还没有任务", systemImage: "checkmark.circle.badge.plus")
        } description: {
            Text("创建第一个打卡任务，今日进度和统计会自动跟上")
        } actions: {
            Button("新建任务") { showForm = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
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
