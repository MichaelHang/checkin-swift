import AppKit
import CheckinCore

/// Menu bar mini view.
///
/// Placeholder for now (compiles, no functionality). Planned:
/// - `NSStatusItem` showing today's progress (e.g. 3/5)
/// - Click to open a mini list with one-click check-in / review
/// - Global hotkey to check in (needs `Carbon` / global event monitoring)
final class MenuBarController {
    private var statusItem: NSStatusItem?

    init() {
        // TODO: create the NSStatusItem and wire up today's progress plus a one-click check-in menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = Constants.appName
            button.toolTip = "打卡 · macOS"
        }
    }

    func show() { statusItem?.isVisible = true }
    func hide() { statusItem?.isVisible = false }
}
