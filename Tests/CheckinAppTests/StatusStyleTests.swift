import XCTest
import SwiftUI
import CheckinCore
@testable import CheckinApp

/// Regression lock for the status visual mapping (the App part of task #4 "site-wide terminology
/// and status color overhaul").
///
/// `StatusStyle.swift` centrally defines the five statuses' colors and icons, shared by the today
/// card / calendar cells / day task list / detail page / check-in history. The regression it guards
/// against is **two statuses looking the same** (e.g. a change tinting both awaiting and passed
/// green) — then users cannot tell "awaiting review" from "pass" by color.
///
/// So these tests deliberately do **not** assert concrete colors (`.green` / `.blue` shift with
/// design tweaks; pinning them is brittle). They lock the semantic invariant: five statuses
/// pairwise distinct + icons non-empty and pairwise distinct.
final class StatusStyleTests: XCTestCase {

    /// The five statuses' colors must be pairwise distinct — color is the user's primary means of telling statuses apart.
    func testEveryStatusHasDistinctColor() {
        let all = TaskStatus.allCases
        XCTAssertEqual(all.count, 5, "状态数量变了，本测试的前提需要复核")
        for i in 0..<all.count {
            for j in (i + 1)..<all.count {
                XCTAssertNotEqual(all[i].color, all[j].color,
                                  "\(all[i]) 与 \(all[j]) 颜色相同 → 用户无法区分这两个状态")
            }
        }
    }

    /// Icons must be non-empty and pairwise distinct (non-empty guards against missing entries;
    /// distinct guards against visual confusion)
    func testEveryStatusHasDistinctNonEmptyIcon() {
        let icons = TaskStatus.allCases.map { $0.iconName }
        for (status, icon) in zip(TaskStatus.allCases, icons) {
            XCTAssertFalse(icon.isEmpty, "\(status) 缺少图标名")
        }
        XCTAssertEqual(Set(icons).count, icons.count, "存在两个状态共用同一图标")
    }
}
