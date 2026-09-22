import XCTest
import CheckinCore

/// Minimal placeholder tests: ensure `swift test` runs.
/// Full business contract tests (DateUtil / StateMachine / PeriodUtil / StreakUtil) were added in the QA phase.
final class IdUtilTests: XCTestCase {

    func testGenIdNotEmpty() {
        let id = IdUtil.genId()
        XCTAssertFalse(id.isEmpty, "genId 不应返回空字符串")
    }

    func testGenIdUnique() {
        let a = IdUtil.genId()
        let b = IdUtil.genId()
        XCTAssertNotEqual(a, b, "两次 genId 应互不相同")
    }

    func testGenIdFormat() {
        let id = IdUtil.genId()
        // A UUID string is 8-4-4-4-12, 36 characters total
        XCTAssertEqual(id.count, 36, "UUID 字符串长度应为 36")
    }
}
