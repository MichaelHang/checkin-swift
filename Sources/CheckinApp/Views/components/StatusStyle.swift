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

// MARK: - Card hover feedback

/// Foreground overlay that fades in while the pointer rests on a clickable card.
///
/// macOS users expect hoverable affordance on interactive surfaces (`.plain` buttons give none).
/// Uses an explicit overlay (not `brightness`) so it reads clearly on translucent glass;
/// kept subtle (default 6% white / 10% in dark mode) and deliberately no cursor change —
/// pointing-hand is reserved for web-style links per Apple HIG.
struct HoverHighlight: ViewModifier {
    var enabled: Bool = true
    var amount: Double = 0.055
    var cornerRadius: CGFloat = 14

    @State private var isHovered = false

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            // The whole card rect must be hit-testable: blank areas of an HStack don't hit-test
            // by default, which would fire hover only over text/icons.
            .contentShape(Rectangle())
            .overlay {
                if enabled {
                    let opacity = colorScheme == .dark ? amount * 1.8 : amount
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.white.opacity(isHovered ? opacity : 0))
                        .allowsHitTesting(false)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.white.opacity(isHovered ? opacity * 1.2 : 0), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .onHover { isHovered = $0 }
            .animation(.snappy(duration: 0.15), value: isHovered)
    }
}

extension View {
    /// Apply card hover feedback; pass `enabled: false` for non-interactive cards.
    func hoverHighlight(enabled: Bool = true, amount: Double = 0.055,
                        cornerRadius: CGFloat = 14) -> some View {
        modifier(HoverHighlight(enabled: enabled, amount: amount, cornerRadius: cornerRadius))
    }
}
