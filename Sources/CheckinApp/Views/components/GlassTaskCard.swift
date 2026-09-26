import SwiftUI
import CheckinCore

/// Today task row (status badge + completion actions).
///
/// Pure presentation component: renders different badges and action buttons from `status`; actions
/// are surfaced via callbacks. Awaiting review gets a blue tint highlight; pass green / fail yellow
/// / not-done gray.
///
/// `showActions` (default true) controls the action buttons; `showStatus` (default true) controls
/// the status badge and status highlight. The period tab passes `showActions: false, showStatus: false`
/// → a pure definition card (name / note / recurrence); the whole card is tappable (`onTap`) to open
/// the edit form.
///
/// Apple-style notes: accent follows the system accent color (`.borderedProminent` follows it by
/// default, no hardcoded indigo); semantic colors (green = pass / yellow = fail / blue = awaiting)
/// are kept; buttons get accessibility labels.
struct GlassTaskCard: View {
    let task: Task
    let status: TaskStatus
    let onComplete: () -> Void
    let onPass: () -> Void
    let onFail: () -> Void
    let onRevoke: () -> Void
    var onTap: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil
    var showActions: Bool = true
    var showStatus: Bool = true

    private var isAwaiting: Bool { showStatus && status == .awaiting }

    /// Done states (pass / fail / skipped) render dimmed in status mode so remaining work
    /// stands out. Awaiting stays highlighted (it still needs review); definition-mode cards
    /// (`showStatus == false`, period tab) are never dimmed.
    private var isDeemphasized: Bool {
        showStatus && (status == .passed || status == .failed || status == .skipped)
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 12) {
                if showStatus { statusBadge }
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.name)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(isDeemphasized ? Color.secondary : Color.primary)
                    if let note = task.note, !note.isEmpty {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let rec = recurrenceText {
                        Text(rec)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.quaternary))
                    }
                }
                Spacer(minLength: 8)
                if showActions {
                    actionButtons
                        .transition(.opacity.combined(with: .scale(0.9, anchor: .trailing)))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isAwaiting ? Glass.regular.tint(.blue.opacity(0.15)) : Glass.regular,
            in: RoundedRectangle(cornerRadius: 14)
        )
        .opacity(isDeemphasized ? 0.72 : 1)
        .animation(.snappy(duration: 0.25), value: status)
        .hoverHighlight(enabled: onTap != nil)
    }

    // MARK: - Recurrence badge

    /// Recurrence badge text; hidden for daily (no information in the "today" context)
    private var recurrenceText: String? {
        if task.type == .weeklyDay, let wd = task.targetWeekday {
            return "每\(DateUtil.weekdayLabel(wd))"
        }
        if task.type == .specificDate, let td = task.targetDate {
            return td
        }
        return nil
    }

    // MARK: - Status badge

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .pending:
            Circle().fill(Color.gray.opacity(0.5)).frame(width: 12, height: 12)
        case .skipped:
            Image(systemName: status.iconName).foregroundStyle(status.color)
        default:
            Image(systemName: status.iconName).foregroundStyle(status.color)
        }
    }

    // MARK: - Action buttons (accent follows system accent; semantic colors kept)

    @ViewBuilder
    private var actionButtons: some View {
        switch status {
        case .pending:
            HStack(spacing: 8) {
                Button("完成") { onComplete() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("完成任务：\(task.name)")
                if let onSkip {
                    Button("跳过") { onSkip() }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("跳过：\(task.name)")
                }
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
                Button("恢复") { onRevoke() }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("恢复：\(task.name)")
            }
        }
    }
}

/// Status label text (always via the Constants label mapping)
extension GlassTaskCard {
    static func label(for status: TaskStatus) -> String {
        Constants.taskStatusLabel(status)
    }
}
