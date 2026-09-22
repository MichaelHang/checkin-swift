import SwiftUI
import CheckinCore

/// Period progress card (N/M + percent bar). Shared by weekly/monthly tasks.
///
/// Pure presentation component: renders N/M, the percent bar and the status badge from `progress`;
/// actions are surfaced via callbacks. Highlights when `progress.achieved`.
///
/// `showActions` (default true) controls the review buttons; `showStatus` (default true) controls the
/// status badge, status-colored text and progress bar. The period tab passes
/// `showActions: false, showStatus: false` → a pure definition card (name / period window / target
/// count); the whole card is tappable (`onTap`) to open the edit form.
///
/// Apple-style notes: the progress bar gradient and accent both use `Color.accentColor`
/// (system-following), no hardcoded indigo/purple; status colors use semantic colors
/// (green = achieved / yellow = not achieved / accent = in progress).
struct GlassPeriodCard: View {
    let task: Task
    let progress: PeriodProgress
    let hasAwaiting: Bool
    var windowRange: String? = nil
    let onCheckin: () -> Void
    let onPass: () -> Void
    let onFail: () -> Void
    let onRevoke: () -> Void
    var onTap: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil
    var showActions: Bool = true
    var showStatus: Bool = true

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(task.name)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    Text(windowRange ?? Constants.periodWindowLabel(task.type))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if showStatus { statusBadge }
                }

                HStack(spacing: 10) {
                    if showStatus {
                        Text("\(progress.done)/\(progress.target)")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(Constants.periodStatusLabel(progress.status))
                            .font(.subheadline)
                            .foregroundStyle(statusColor)
                    } else {
                        Text("目标 \(progress.target) 次")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }

                if showStatus { progressBar }

                if showActions && hasAwaiting {
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
                }

                if showActions, let onSkip {
                    HStack(spacing: 8) {
                        Button("跳过今天") { onSkip() }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("跳过今天：\(task.name)")
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .glassEffect(
            showStatus && progress.achieved ? Glass.regular.tint(.green.opacity(0.12)) : Glass.regular,
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    // MARK: - Status badge

    @ViewBuilder
    private var statusBadge: some View {
        switch progress.status {
        case .inProgress:
            Image(systemName: "circle").foregroundStyle(.tint)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.yellow)
        case .noExpectation:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch progress.status {
        case .inProgress: return .accentColor
        case .completed: return .green
        case .failed: return .yellow
        case .noExpectation: return .secondary
        }
    }

    // MARK: - Percent bar (translucent track + gradient fill in system accent color)

    private var progressBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fill = w * CGFloat(progress.percent) / 100.0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.12))
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.55)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, fill))
            }
            .frame(height: 8)
        }
        .frame(height: 8)
    }
}
