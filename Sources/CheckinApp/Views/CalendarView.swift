import SwiftUI
import SwiftData
import CheckinCore

/// Calendar scope: week / month.
enum CalendarScope: String, CaseIterable, Identifiable {
    case week
    case month

    var id: String { rawValue }
    var label: String { self == .week ? "周" : "月" }
}

/// One task plus its status on a given day.
///
/// An `Identifiable` struct rather than a `(Task, TaskStatus)` tuple: tuples inside
/// `ForEach` blow up SwiftUI type inference.
struct DayTaskItem: Identifiable {
    let task: Task
    let status: TaskStatus

    var id: String { task.id }
}

/// Calendar view: week / month switching, per-day view of tasks and check-in status.
///
/// - Shows only single-day tasks (daily / weekly on a given weekday / specific date).
///   Period tasks (N times per week / month) span the whole period and stay in the period tab.
/// - Tapping a day expands that day's tasks below. Today and past days allow check-in /
///   review / revoke; only future days are read-only (see `canAct`) — backfilling on past
///   days is an explicit user requirement.
/// - **Callbacks must pass `refDate: selected` explicitly**: the state machine uses refDate
///   to decide which day a record lands on; omitting it falls back to `TaskViewModel`'s
///   default `DateUtil.now()` and misattributes the record to today. Pass it in every
///   `dayList` callback.
/// - Badges (see `dayBadgeText`) express which day a record lands on, not whether buttons exist.
struct CalendarView: View {
    @Query(sort: \PersistedTask.createdAt, order: .forward) private var persistedTasks: [PersistedTask]
    @Query private var persistedRecords: [PersistedCheckinRecord]
    @Environment(\.modelContext) private var modelContext

    @State private var vm = TaskViewModel()
    @State private var scope: CalendarScope = .week
    @State private var anchor: Date = DateUtil.now()
    @State private var selected: Date = DateUtil.now()
    @State private var showForm = false
    @State private var detailTaskId: String? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private var tasks: [Task] { persistedTasks.map { $0.toValue } }
    private var records: [CheckinRecord] { persistedRecords.map { $0.toValue } }
    private var now: Date { DateUtil.now() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerControls
                weekdayHeader
                grid
                Divider()
                selectedDaySection
            }
            .padding(16)
        }
        .navigationTitle("日历")
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
            TaskDetailView(taskId: wrapper.id, workingDate: selected)
        }
    }

    // MARK: - Header controls (scope / paging / back to today)

    private var headerControls: some View {
        HStack(spacing: 10) {
            Picker("范围", selection: $scope) {
                Text("周").tag(CalendarScope.week)
                Text("月").tag(CalendarScope.month)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 150)

            Button { move(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.bordered)
                .accessibilityLabel("上一个\(scope.label)")

            Text(titleText)
                .font(.headline)
                .frame(minWidth: 160)

            Button { move(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.bordered)
                .accessibilityLabel("下一个\(scope.label)")

            Spacer(minLength: 8)

            Button("今天") { goToday() }
                .buttonStyle(.bordered)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 6) {
            ForEach(DateUtil.weekdayLabels, id: \.self) { w in
                Text(w)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Grid

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(gridDays, id: \.timeIntervalSince1970) { day in
                switch scope {
                case .month:
                    MonthDayCell(
                        date: day,
                        inMonth: DateUtil.isInMonth(day, year: monthComponents.year,
                                                   month: monthComponents.month),
                        isToday: CalendarDayPolicy.isToday(day, now: now),
                        isSelected: DateUtil.localDate(day) == DateUtil.localDate(selected),
                        statuses: previewItems(day).map { $0.status }
                    ) { selected = day }
                case .week:
                    WeekDayCell(
                        date: day,
                        isToday: CalendarDayPolicy.isToday(day, now: now),
                        isSelected: DateUtil.localDate(day) == DateUtil.localDate(selected),
                        items: previewItems(day)
                    ) { selected = day }
                }
            }
        }
    }

    // MARK: - Selected-day tasks

    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            dayTitle
            dayList
        }
    }

    private var dayTitle: some View {
        HStack(spacing: 8) {
            Text(DateUtil.formatCNDate(selected))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
            if let badge = dayBadgeText {
                Text(badge)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Badge text for the selected day (semantics in `CalendarDayPolicy.badge`).
    private var dayBadgeText: String? {
        CalendarDayPolicy.badge(selected: selected, now: now)
    }

    @ViewBuilder
    private var dayList: some View {
        let items = dayItems(selected)
        if items.isEmpty {
            Text("这天没有任务")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        } else {
            ForEach(items) { item in
                DayTaskRow(
                    task: item.task,
                    status: item.status,
                    canAct: canActOnSelectedDay,
                    canSkip: canSkipOnSelectedDay,
                    // ⚠️ Every callback must pass `refDate: selected` explicitly: the default is now(),
                    // and omitting it records past-day actions on today (future-day check-ins are
                    // already blocked by canAct).
                    onComplete: { vm.complete(item.task, refDate: selected, context: modelContext) },
                    onPass: { vm.pass(item.task, refDate: selected, context: modelContext) },
                    onFail: { vm.fail(item.task, refDate: selected, context: modelContext) },
                    onRevoke: { vm.revoke(item.task, refDate: selected, context: modelContext) },
                    onSkip: { vm.skip(item.task, refDate: selected, context: modelContext) },
                    onTap: { detailTaskId = item.task.id }
                )
            }
        }
    }

    // MARK: - Derived values

    private var monthComponents: (year: Int, month: Int) {
        let c = DateUtil.components(anchor)
        return (c.year, c.month)
    }

    private var gridDays: [Date] {
        switch scope {
        case .week: return DateUtil.weekDays(anchor)
        case .month:
            let c = monthComponents
            return DateUtil.monthGrid(year: c.year, month: c.month)
        }
    }

    private var titleText: String {
        switch scope {
        case .month:
            let c = monthComponents
            return "\(c.year)年\(c.month)月"
        case .week:
            let days = DateUtil.weekDays(anchor)
            guard let first = days.first, let last = days.last else { return "" }
            return "\(DateUtil.localDate(first)) ~ \(DateUtil.localDate(last))"
        }
    }

    /// Single-day tasks for a date plus each one's status on that day.
    private func dayItems(_ date: Date) -> [DayTaskItem] {
        let key = DateUtil.localDate(date)
        return tasks
            .filter { isActiveOn($0, date: date) }
            .map { DayTaskItem(task: $0, status: vm.statusOf($0, records: records, date: key)) }
    }

    /// Items for grid cell previews: skipped (.skipped) tasks take no preview slot.
    ///
    /// A skip is a single-day exemption; keeping it in the preview would crowd real progress
    /// out of the first 3 dots/rows. The full list (skipped included, with restore) stays in
    /// the selected-day list (`dayList`), which is the action entry point.
    private func previewItems(_ date: Date) -> [DayTaskItem] {
        dayItems(date).filter { $0.status != .skipped }
    }

    /// Whether a single-day task should appear on that date; period tasks never enter the calendar.
    private func isActiveOn(_ task: Task, date: Date) -> Bool {
        guard !DateUtil.isEnded(task, on: date) else { return false }
        switch task.type {
        case .daily: return true
        case .weeklyDay: return task.targetWeekday == DateUtil.weekdayISO(date)
        case .specificDate: return task.targetDate == DateUtil.localDate(date)
        case .weekly, .monthly: return false
        }
    }

    /// Whether the selected day allows actions: today + past days allow check-in / review / revoke; future days are read-only.
    private var canActOnSelectedDay: Bool {
        CalendarDayPolicy.canAct(selected: selected, now: now)
    }

    /// Whether skip / restore is allowed on the selected day: always true.
    ///
    /// Kept as a wrapper so the semantics stay in `CalendarDayPolicy.canSkip` (skipping a
    /// future day is legal — see its docs) instead of scattering that knowledge in the view.
    private var canSkipOnSelectedDay: Bool {
        CalendarDayPolicy.canSkip(selected: selected, now: now)
    }

    private func move(_ delta: Int) {
        switch scope {
        case .week: anchor = DateUtil.addingDays(delta * 7, to: anchor)
        case .month: anchor = DateUtil.addingMonths(delta, to: anchor)
        }
    }

    private func goToday() {
        anchor = now
        selected = now
    }
}

// MARK: - Month view cell

private struct MonthDayCell: View {
    let date: Date
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let statuses: [TaskStatus]
    let onTap: () -> Void

    private var dayNumber: String { "\(DateUtil.components(date).day)" }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(dayNumber)
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundStyle(dayForeground)
                dotRow
                    .frame(height: 10)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .top)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(cellBackground)
        .overlay(cellBorder)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var dotRow: some View {
        if statuses.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 3) {
                ForEach(Array(statuses.prefix(3).enumerated()), id: \.offset) { _, s in
                    Circle().fill(s.color).frame(width: 7, height: 7)
                }
                if statuses.count > 3 {
                    Text("+\(statuses.count - 3)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var dayForeground: Color {
        if !inMonth { return .secondary.opacity(0.45) }
        return isToday ? .accentColor : .primary
    }

    private var cellBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
    }

    private var cellBorder: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Color.accentColor, lineWidth: isToday ? 1.5 : 0)
    }

    private var accessibilityText: String {
        "\(DateUtil.formatCNDate(date))，\(statuses.count) 个任务"
    }
}

// MARK: - Week view cell

private struct WeekDayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let items: [DayTaskItem]
    let onTap: () -> Void

    private var dayNumber: String { "\(DateUtil.components(date).day)" }
    private var weekdayText: String { DateUtil.weekdayLabel(DateUtil.weekdayISO(date)) }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(weekdayText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(dayNumber)
                        .font(.headline.weight(isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Color.accentColor : Color.primary)
                }
                ForEach(Array(items.prefix(3))) { item in
                    HStack(spacing: 5) {
                        Circle().fill(item.status.color).frame(width: 7, height: 7)
                        Text(item.task.name)
                            .font(.subheadline)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                if items.count > 3 {
                    Text("+\(items.count - 3)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, lineWidth: isToday ? 1.5 : 0)
        }
        .accessibilityLabel("\(DateUtil.formatCNDate(date))，\(items.count) 个任务")
    }
}

// MARK: - Selected-day task row

private struct DayTaskRow: View {
    let task: Task
    let status: TaskStatus
    let canAct: Bool
    let canSkip: Bool
    let onComplete: () -> Void
    let onPass: () -> Void
    let onFail: () -> Void
    let onRevoke: () -> Void
    let onSkip: () -> Void
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: {
            rowContent
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .glassEffect(
            status == .awaiting ? Glass.regular.tint(.blue.opacity(0.15)) : Glass.regular,
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Image(systemName: status.iconName)
                .foregroundStyle(status.color)
            infoColumn
            Spacer(minLength: 8)
            // ⚠️ Restore (= revoke) on a future day must not go through `canAct` (it blocks future
            // days), or a skip made in advance could never be undone. Skipped state is gated by
            // `canSkip` instead.
            if canAct || (status == .skipped && canSkip) { actions }
        }
    }

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.name)
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
            HStack(spacing: 6) {
                Text(Constants.taskStatusLabel(status))
                    .font(.subheadline)
                    .foregroundStyle(status.color)
                if let rec = recurrenceText {
                    Text(rec)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// weeklyDay → weekday label; specificDate → the date; daily → nil.
    private var recurrenceText: String? {
        if task.type == .weeklyDay, let wd = task.targetWeekday {
            return "每\(DateUtil.weekdayLabel(wd))"
        }
        if task.type == .specificDate, let td = task.targetDate {
            return td
        }
        return nil
    }

    @ViewBuilder
    private var actions: some View {
        switch status {
        case .pending:
            HStack(spacing: 8) {
                // "Complete" still respects the future-day read-only rule.
                if canAct {
                    Button("完成") { onComplete() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("完成任务：\(task.name)")
                }
                // "Skip" always shows (not gated by canAct): marking a future day off ahead of time is legitimate.
                Button("跳过") { onSkip() }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("跳过：\(task.name)")
            }
        case .awaiting:
            HStack(spacing: 8) {
                Button("过关") { onPass() }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .accessibilityLabel("过关：\(task.name)")
                Button("没过关") { onFail() }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .accessibilityLabel("没过关：\(task.name)")
                Button("撤销") { onRevoke() }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("撤销：\(task.name)")
            }
        case .passed, .failed:
            Button("撤销") { onRevoke() }
                .buttonStyle(.bordered)
                .accessibilityLabel("撤销：\(task.name)")
        case .skipped:
            HStack(spacing: 8) {
                Text("已跳过")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                // "Restore" = revoke, gated by canSkip (not canAct — see the note in rowContent).
                if canSkip {
                    Button("恢复") { onRevoke() }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("恢复：\(task.name)")
                }
            }
        }
    }
}
