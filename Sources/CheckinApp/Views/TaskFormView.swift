import SwiftUI
import SwiftData
import CheckinCore

/// New / edit task form. Fields shown dynamically by type:
/// - Specific date: year / month / day menus
/// - Weekly / monthly: count target
/// - Common: acceptance-review toggle, note
///
/// Specific date avoids the system `DatePicker`: on macOS it pads single digits in CJK
/// date text ("2026年 9月 7 日"), which reads as a layout bug. Three `.menu` pickers
/// render without padding.
struct TaskFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let editTask: Task?
    var initialType: TaskType = .daily

    @State private var name: String = ""
    @State private var type: TaskType = .daily
    @State private var targetDate: Date = DateUtil.now()
    @State private var selWeekday: Int = 1
    @State private var targetCount: Int = Constants.defaultTargetCount
    @State private var acceptanceRequired: Bool = false
    @State private var note: String = ""
    @State private var endEnabled: Bool = false
    @State private var endDate: Date = DateUtil.now()

    init(editTask: Task?, initialType: TaskType = .daily) {
        self.editTask = editTask
        self.initialType = initialType

        // Use the stored date when editing; otherwise default to today
        let base: Date
        if let t = editTask {
            base = DateUtil.parseLocalDate(
                t.targetDate ?? DateUtil.localDate(DateUtil.now())
            ) ?? DateUtil.now()
            _name = State(initialValue: t.name)
            _type = State(initialValue: t.type)
            _targetCount = State(initialValue: t.targetCount ?? Constants.defaultTargetCount)
            _acceptanceRequired = State(initialValue: t.acceptanceRequired)
            _note = State(initialValue: t.note ?? "")
        } else {
            base = DateUtil.now()
            _type = State(initialValue: initialType)
        }

        _targetDate = State(initialValue: base)
        _selWeekday = State(initialValue: editTask?.targetWeekday ?? 1)

        if let ed = editTask?.endDate {
            _endEnabled = State(initialValue: true)
            _endDate = State(initialValue: DateUtil.parseLocalDate(ed) ?? DateUtil.now())
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Year range: 3 years back to 5 years ahead (covers backfill and advance scheduling).
    private var yearRange: ClosedRange<Int> {
        let y = DateUtil.components(DateUtil.now()).year
        return (y - 3)...(y + 5)
    }

    var body: some View {
        GlassSheet {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(editTask == nil ? "新建任务" : "编辑任务")
                        .font(.headline)
                    Spacer()
                    Button("取消") { dismiss() }
                        .buttonStyle(.bordered)
                }

                Group {
                    TextField("任务名称", text: $name)
                        .textFieldStyle(.roundedBorder)

                    Picker("任务类型", selection: $type) {
                        ForEach(TaskType.allCases) { t in
                            Text(Constants.taskTypeLabel(t)).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)

                    if type == .specificDate {
                        specificDateRow
                    }

                    if type == .weeklyDay {
                        weekdayRow
                    }

                    if type == .weekly || type == .monthly {
                        Stepper("次数目标：\(targetCount)", value: $targetCount,
                                in: Constants.minTargetCount...Constants.maxTargetCount)
                    }

                    if type == .weekly || type == .monthly || type == .weeklyDay {
                        Toggle("设置结束时间", isOn: $endEnabled)
                        if endEnabled {
                            DateMenuView(date: $endDate, yearRange: yearRange)
                        }
                    }

                    Toggle("需要过关", isOn: $acceptanceRequired)

                    TextField("备注（可选）", text: $note)
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    save()
                    dismiss()
                } label: {
                    Text(editTask == nil ? "创建" : "保存")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(!canSave)
            }
        }
        .frame(minWidth: 340, minHeight: 360)
    }

    // MARK: - Specific date (year / month / day menus)

    private var specificDateRow: some View {
        HStack(spacing: 8) {
            Text("指定日期")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            DateMenuView(date: $targetDate, yearRange: yearRange)
        }
    }

    // MARK: - Year / month / day pickers (reusable)

    /// Three `.menu` pickers (year/month/day) with no CJK digit padding.
    /// When a month change overflows the day (e.g. 31 → February), clamps to that month's last day.
    /// Holds internal selYear/selMonth/selDay state and writes back to `$date`.
    private struct DateMenuView: View {
        @Binding var date: Date
        var yearRange: ClosedRange<Int>

        @State private var selYear: Int = 1
        @State private var selMonth: Int = 1
        @State private var selDay: Int = 1

        init(date: Binding<Date>, yearRange: ClosedRange<Int>) {
            self._date = date
            self.yearRange = yearRange
            let c = DateUtil.components(date.wrappedValue)
            self._selYear = State(initialValue: c.year)
            self._selMonth = State(initialValue: c.month)
            self._selDay = State(initialValue: c.day)
        }

        private var maxDay: Int {
            DateUtil.daysInMonth(year: selYear, month: selMonth)
        }

        var body: some View {
            Picker("年", selection: $selYear) {
                ForEach(yearRange, id: \.self) { y in
                    Text(verbatim: "\(y)年").tag(y)
                }
            }
            .labelsHidden()
            .onChange(of: selYear) { rebuildDate() }

            Picker("月", selection: $selMonth) {
                ForEach(1...12, id: \.self) { m in
                    Text(verbatim: "\(m)月").tag(m)
                }
            }
            .labelsHidden()
            .onChange(of: selMonth) { rebuildDate() }

            Picker("日", selection: $selDay) {
                ForEach(1...maxDay, id: \.self) { d in
                    Text(verbatim: "\(d)日").tag(d)
                }
            }
            .labelsHidden()
            .onChange(of: selDay) { rebuildDate() }
        }

        private func rebuildDate() {
            let day = min(selDay, maxDay)
            if day != selDay { selDay = day }
            date = DateUtil.date(year: selYear, month: selMonth, day: day)
        }
    }

    // MARK: - Weekly on a given weekday (weekday picker)

    private var weekdayRow: some View {
        HStack(spacing: 8) {
            Text("每周某天")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Picker("星期", selection: $selWeekday) {
                ForEach(1...7, id: \.self) { w in
                    Text(DateUtil.weekdayLabel(w)).tag(w)
                }
            }
            .labelsHidden()
        }
    }

    private func save() {
        let repo = CheckinRepository(modelContext: modelContext)
        let task = Task(
            id: editTask?.id ?? IdUtil.genId(),
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            acceptanceRequired: acceptanceRequired,
            note: note.isEmpty ? nil : note,
            targetDate: type == .specificDate ? DateUtil.localDate(targetDate) : nil,
            targetWeekday: type == .weeklyDay ? selWeekday : nil,
            targetCount: (type == .weekly || type == .monthly)
                ? max(Constants.minTargetCount, targetCount) : nil,
            endDate: endEnabled ? DateUtil.localDate(endDate) : nil,
            createdAt: editTask?.createdAt ?? DateUtil.isoDateTime(DateUtil.now())
        )
        if editTask != nil {
            repo.updateTask(task)
        } else {
            repo.addTask(task)
        }
    }
}
