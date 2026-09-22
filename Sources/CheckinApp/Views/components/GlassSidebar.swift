import SwiftUI

/// Sidebar base: **full-bleed, no corner radius, no padding**.
///
/// Purpose: lay an even glass base under the Sidebar column of `NavigationSplitView`,
/// letting the soft gradient behind RootView show through for depth.
///
/// Do not wrap this in `RoundedRectangle` + padding: the sidebar column of `NavigationSplitView`
/// already has its own native material; layering an inset, rounded glass pane on top reads visually
/// as "a card inside the sidebar". So this fills with a full-edge material and never draws a visible border.
struct GlassSidebar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background {
                Rectangle()
                    .fill(.regularMaterial)
                    .ignoresSafeArea()
            }
    }
}
