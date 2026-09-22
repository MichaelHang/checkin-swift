import Foundation

/// Derived status for period (weekly / monthly) tasks.
@frozen public enum PeriodStatus: String, Codable, CaseIterable {
    case inProgress
    case completed      // target met
    case failed         // window ended with target not met
    case noExpectation  // no doable days (whole period skipped → effectiveTarget == 0)
}
//
// Why a separate `noExpectation` instead of reusing `.completed`:
// with `effectiveTarget == 0`, reusing `.completed` would contradict `achieved == false` —
// it would show "achieved" while nothing was achieved; a separate case honestly expresses
// "no doable days this week / month".

/// Derived period progress.
public struct PeriodProgress: Codable, Equatable {
    public var done: Int
    public var target: Int
    public var percent: Int       // 0–100
    public var achieved: Bool     // done >= target
    public var status: PeriodStatus

    public init(done: Int, target: Int, percent: Int, achieved: Bool, status: PeriodStatus) {
        self.done = done
        self.target = target
        self.percent = percent
        self.achieved = achieved
        self.status = status
    }
}
