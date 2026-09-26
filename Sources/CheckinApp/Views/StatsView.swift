import SwiftUI
import AppKit
import SwiftData
import CheckinCore

/// Stats view: how this week went / which tasks slip most / which weekday collapses / trend.
///
/// All metrics live in `StatsUtil` pure functions (complete = any check-in counts,
/// counted=true; window = calendar week); this file is a pure rendering layer.
///
/// **Empty-state guard (critical)**: with no tasks, show an empty hint; any section whose
/// expected count is below `Constants.minSampleForRate` shows the insufficient-sample hint —
/// never fabricate 0%.
struct StatsView: View {
    @Query(sort: \PersistedTask.createdAt, order: .forward) private var persistedTasks: [PersistedTask]
    @Query private var persistedRecords: [PersistedCheckinRecord]

    @State private var vm = StatsViewModel()
    @State private var showForm = false

    private var tasks: [Task] { persistedTasks.map { $0.toValue } }
    private var records: [CheckinRecord] { persistedRecords.map { $0.toValue } }
    private var now: Date { DateUtil.now() }

    var body: some View {
        ScrollView {
            if tasks.isEmpty {
                emptyStateView
            } else {
                let stats = vm.weeklyStats(tasks, records: records, ref: now)
                let byTask = vm.completionByTask(tasks, records: records, ref: now)
                let byWeekday = vm.completionByWeekday(tasks, records: records, ref: now)
                let trend = vm.weeklyTrend(tasks, records: records, ref: now)
                let streak = vm.achievedWeekStreak(tasks, records: records, ref: now)

                VStack(alignment: .leading, spacing: 16) {
                    overviewCards(stats, streak: streak)
                    weakestTasksSection(byTask)
                    weekdaySection(byWeekday)
                    trendSection(trend)
                }
                .padding(16)
            }
        }
        .navigationTitle("统计")
        .sheet(isPresented: $showForm) {
            TaskFormView(editTask: nil)
        }
    }

    // MARK: - Top three cards

    private func overviewCards(_ stats: WeeklyStats, streak: Int) -> some View {
        let enough = stats.expected >= Constants.minSampleForRate
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                statBox(
                    title: "本周完成率",
                    value: enough ? percent(stats.rate) : "—",
                    subtitle: "已做 \(stats.done) / 应做 \(stats.expected)"
                )
                statBox(
                    title: "本周过关率",
                    value: percent(stats.passRate),
                    subtitle: stats.judged == 0 ? "暂无判定" : "过关 \(stats.passed) / 已判 \(stats.judged)"
                )
                statBox(
                    title: "连续达标周",
                    value: "\(streak) 周",
                    subtitle: "达标线 \(Int(Constants.achieveRatio * 100))%"
                )
            }
            if !enough {
                insufficientHint
            }
        }
    }

    // MARK: - Weakest tasks

    private func weakestTasksSection(_ items: [TaskCompletion]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("哪些任务总在漏")
            let expectedTotal = items.reduce(0) { $0 + $1.expected }
            if expectedTotal < Constants.minSampleForRate || items.isEmpty {
                insufficientHint
            } else {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(items.prefix(8))) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(item.name)
                                        .font(.subheadline.weight(.medium))
                                    Spacer(minLength: 8)
                                    Text("\(item.done)/\(item.expected)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(percent(item.rate))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(tint(for: item.rate))
                                }
                                RateBar(rate: item.rate ?? 0, tint: tint(for: item.rate))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Weakest weekday

    private func weekdaySection(_ items: [WeekdayCompletion]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("一周里哪天最容易崩")
            let expectedTotal = items.reduce(0) { $0 + $1.expected }
            if expectedTotal < Constants.minSampleForRate {
                insufficientHint
            } else {
                GlassCard {
                    BarChart(
                        data: items.map { BarDatum(id: $0.label, label: $0.label, rate: $0.rate) },
                        height: 120
                    )
                }
            }
        }
    }

    // MARK: - Four-week completion trend

    private func trendSection(_ items: [WeekTrend]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                sectionHeader("近四周完成率趋势")
                Text("每周平均完成率")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if items.allSatisfy({ $0.rate == nil }) {
                insufficientHint
            } else {
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        // Newest first: current week on top (trend comes back ascending, so reversed gives descending).
                        ForEach(Array(items.reversed())) { item in
                            TrendBarRow(label: item.label, rate: item.rate)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func statBox(title: String, value: String, subtitle: String) -> some View {
        GlassCard {
            VStack(spacing: 6) {
                Text(value)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Shared "insufficient sample" hint (replaces any 0% display).
    private var insufficientHint: some View {
        Text("样本不足，继续打卡后显示")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Full-page empty state (no tasks yet): native placeholder + create action.
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("还没有任务", systemImage: "chart.bar")
        } description: {
            Text("创建任务并打卡后，这里会自动生成统计")
        } actions: {
            Button("新建任务") { showForm = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    /// nil → "—"; otherwise a rounded percentage (never fabricates 0% for alignment).
    private func percent(_ rate: Double?) -> String {
        guard let rate else { return "—" }
        return "\(Int((rate * 100).rounded()))%"
    }

    /// Low = red / mid = yellow / at-target = green.
    private func tint(for rate: Double?) -> Color {
        guard let rate else { return .secondary }
        if rate >= Constants.achieveRatio { return .green }
        if rate >= 0.5 { return .yellow }
        return .red
    }
}

// MARK: - Bars (no third-party chart library)

/// Horizontal rate bar (used by the weakest-items list).
private struct RateBar: View {
    let rate: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(tint)
                    .frame(width: max(2, geo.size.width * CGFloat(min(max(rate, 0), 1))))
            }
            .frame(height: 8)
        }
        .frame(height: 8)
    }
}

/// Data for one bar (shared by the weekday and week-trend charts).
private struct BarDatum: Identifiable {
    let id: String
    let label: String
    let rate: Double?
}

/// Vertical bar chart: centered cluster of fixed-width columns (full-width stretching left
/// the bars thin and scattered). Weekday labels only for now (2 chars fit a 36pt column);
/// longer labels would need a wider column.
private struct BarChart: View {
    let data: [BarDatum]
    var height: CGFloat
    /// Bar width (= column width), wide enough to read the differences.
    private let barWidth: CGFloat = 36

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(data) { datum in
                VStack(spacing: 6) {
                    Text(shortText(datum.rate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    barBody(datum.rate)
                    Text(datum.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: barWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func barBody(_ rate: Double?) -> some View {
        let ratio = CGFloat(min(max(rate ?? 0, 0), 1))
        // Column width == bar width, so no extra centering (the outer VStack is already barWidth wide).
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(0.10))
                .frame(width: barWidth, height: height)
            // No fill at 0% (a 2pt bar would read as an underline).
            if ratio > 0 {
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(
                        colors: [BarTint.light, BarTint.base],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: barWidth, height: max(2, height * ratio))
            }
        }
        .frame(width: barWidth, height: height)
    }

    private func shortText(_ rate: Double?) -> String {
        guard let rate else { return "—" }
        return "\(Int((rate * 100).rounded()))%"
    }
}

/// Bar fill color: Apple system blue, not `accentColor`. `Color.accentColor` follows the
/// user's system tint (purple / green / multicolor), which skews data visualization;
/// fixed Apple blue adapts to light and dark mode automatically.
private enum BarTint {
    /// System blue: light #007AFF / dark #0A84FF.
    static let base = Color(nsColor: .systemBlue)
    /// Gradient end light blue #4DA8FF (solid color, not .opacity, to avoid graying out in dark mode).
    static let light = Color(red: 0.30, green: 0.66, blue: 1.0)
}

/// Trend row: label left / capsule bar center (Apple blue gradient) / percent right.
/// A horizontal list reads better than a 7-column chart for 4 data points.
private struct TrendBarRow: View {
    let label: String
    let rate: Double?

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(width: 56, alignment: .leading)
            bar
            Text(percent)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 48, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                if let r = rate, r > 0 {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [BarTint.base, BarTint.light],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: max(2, geo.size.width * CGFloat(min(max(r, 0), 1))))
                }
            }
        }
        .frame(height: 18)
    }

    private var percent: String {
        guard let rate else { return "—" }
        return "\(Int((rate * 100).rounded()))%"
    }
}
