import Foundation

/// Global constants and default configuration (CheckinCore depends on Foundation only).
public enum Constants {
    // MARK: Schema / container names (kept consistent across files)
    public static let schemaName = "CheckinSchema"
    public static let containerName = "CheckinContainer"

    // MARK: Store location (pinned explicitly; see CheckinApp.storeURL)
    /// Folder under Application Support holding all data; back up the whole folder
    public static let storeFolderName = "CheckinApp"
    /// SwiftData store file name
    public static let storeFileName = "checkin.store"
    /// Legacy default store (SwiftData wrote to Application Support/default.store when no URL was set)
    public static let legacyStoreFileName = "default.store"

    // MARK: App name
    public static let appName = "打卡"

    // MARK: Defaults
    public static let defaultTargetCount = 5
    public static let minTargetCount = 1
    public static let maxTargetCount = 999

    // MARK: Statistics thresholds (used by the stats page)
    /// Achieved threshold: a week counts as achieved when its completion rate >= this (basis of the achieved-week streak; the UI must label it)
    public static let achieveRatio: Double = 0.8
    /// Minimum sample: below this many expected actions in a week, the completion rate is hidden (avoids a wall of 0% for new users)
    public static let minSampleForRate = 3

    // MARK: Compact window thresholds
    public static let compactWidthThreshold: CGFloat = 480
    public static let minWindowWidth: CGFloat = 390
    public static let minWindowHeight: CGFloat = 480

    // MARK: Label mapping (centralized for reuse and unit testing)
    public static func taskTypeLabel(_ t: TaskType) -> String {
        switch t {
        case .daily: return "每日"
        case .specificDate: return "指定日"
        case .weeklyDay: return "每周某天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        }
    }

    /// Task status labels (not done / awaiting / pass / fail / skipped)
    public static func taskStatusLabel(_ s: TaskStatus) -> String {
        switch s {
        case .pending: return "未完成"
        case .awaiting: return "待判定"
        case .passed: return "过关"
        case .failed: return "没过关"
        case .skipped: return "已跳过"
        }
    }

    public static func periodStatusLabel(_ s: PeriodStatus) -> String {
        switch s {
        case .inProgress: return "进行中"
        case .completed: return "达标"
        case .failed: return "未达成"
        case .noExpectation: return "无可做天数"
        }
    }

    /// Period window label (this week / this month)
    public static func periodWindowLabel(_ t: TaskType) -> String {
        switch t {
        case .weekly: return "本周"
        case .monthly: return "本月"
        default: return ""
        }
    }
}
