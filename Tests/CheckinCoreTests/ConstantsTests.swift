import XCTest
import CheckinCore

/// Regression lock for product terminology (the CheckinCore part of task #4 "site-wide terminology
/// and status color overhaul").
///
/// The label mappings in `Constants` are **user-visible product copy** (rendered by the home card,
/// calendar, detail page and check-in history) and `Constants.swift`'s own comments call for
/// "centralized, reusable, unit-testable" — yet there were no tests, so terminology could drift
/// silently. This file pins the vocabulary.
///
/// Note: these assertions are the **product-decided Chinese vocabulary**, not implementation
/// details. Changing copy means changing these tests deliberately, through review — not letting
/// it drift.
final class ConstantsTests: XCTestCase {

    // MARK: - Task status vocabulary

    /// The five statuses' labels are the product vocabulary, asserted verbatim below.
    func testTaskStatusLabelsMatchProductVocabulary() {
        XCTAssertEqual(Constants.taskStatusLabel(.pending), "未完成")
        XCTAssertEqual(Constants.taskStatusLabel(.awaiting), "待判定")
        XCTAssertEqual(Constants.taskStatusLabel(.passed), "过关")
        XCTAssertEqual(Constants.taskStatusLabel(.failed), "没过关")
        XCTAssertEqual(Constants.taskStatusLabel(.skipped), "已跳过")
    }

    /// Locks the vocabulary as a whole: adding a status without a label surfaces here (set inequality).
    func testTaskStatusVocabularyIsExactlyFiveTerms() {
        let labels = Set(TaskStatus.allCases.map { Constants.taskStatusLabel($0) })
        XCTAssertEqual(labels, ["未完成", "待判定", "过关", "没过关", "已跳过"],
                       "状态词汇表被改动了 —— 若不是有意为之，说明文案漂移了")
        XCTAssertEqual(labels.count, TaskStatus.allCases.count, "五个状态不应共用同一文案")
    }

    // MARK: - Task type vocabulary

    func testTaskTypeLabelsMatchProductVocabulary() {
        XCTAssertEqual(Constants.taskTypeLabel(.daily), "每日")
        XCTAssertEqual(Constants.taskTypeLabel(.specificDate), "指定日")
        XCTAssertEqual(Constants.taskTypeLabel(.weeklyDay), "每周某天")
        XCTAssertEqual(Constants.taskTypeLabel(.weekly), "每周")
        XCTAssertEqual(Constants.taskTypeLabel(.monthly), "每月")
    }

    /// Every type must have a non-empty label (guards against blank labels in the UI)
    func testEveryTaskTypeHasNonEmptyLabel() {
        for t in TaskType.allCases {
            XCTAssertFalse(Constants.taskTypeLabel(t).isEmpty, "\(t) 的文案不应为空")
        }
    }

    // MARK: - Period status / period window

    func testPeriodStatusLabelsMatchProductVocabulary() {
        XCTAssertEqual(Constants.periodStatusLabel(.inProgress), "进行中")
        XCTAssertEqual(Constants.periodStatusLabel(.completed), "达标")
        XCTAssertEqual(Constants.periodStatusLabel(.failed), "未达成")
        XCTAssertEqual(Constants.periodStatusLabel(.noExpectation), "无可做天数")
    }

    /// The period window label only applies to period tasks (weekly / monthly); others return an empty string
    func testPeriodWindowLabelOnlyForPeriodTasks() {
        XCTAssertEqual(Constants.periodWindowLabel(.weekly), "本周")
        XCTAssertEqual(Constants.periodWindowLabel(.monthly), "本月")
        XCTAssertEqual(Constants.periodWindowLabel(.daily), "")
        XCTAssertEqual(Constants.periodWindowLabel(.weeklyDay), "")
        XCTAssertEqual(Constants.periodWindowLabel(.specificDate), "")
    }
}
