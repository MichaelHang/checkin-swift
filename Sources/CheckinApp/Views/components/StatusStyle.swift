import SwiftUI
import CheckinCore

/// Unified visual mapping (color / icon) for task statuses.
///
/// The five statuses render repeatedly in the today card, calendar cells, day task list, detail page
/// and check-in history. Defining them centrally here avoids each site hardcoding colors and the
/// same status looking different across screens.
///
    /// Color semantics:
    /// - `pending` not done → gray (no record at all)
    /// - `awaiting` awaiting review → blue (checked in, waiting for a review action)
    /// - `passed`  pass   → green (done and achieved)
    /// - `failed`  fail   → yellow (attempted but not achieved; **still counts as done**)
    /// - `skipped` skipped → secondary gray (single-day exemption; **not a completion**, distinct
    ///   from pending's gray/circle)
extension TaskStatus {

    var color: Color {
        switch self {
        case .pending:  return .gray
        case .awaiting: return .blue
        case .passed:   return .green
        case .failed:   return .yellow
        case .skipped:  return .secondary
        }
    }

    var iconName: String {
        switch self {
        case .pending:  return "circle"
        case .awaiting: return "hourglass"
        case .passed:   return "checkmark.circle.fill"
        case .failed:   return "xmark.circle.fill"
        case .skipped:  return "minus.circle"
        }
    }
}
