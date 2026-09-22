import SwiftUI

/// Glass card wrapper: unified `.glassEffect()` rounded translucent card.
///
/// - `tint` is optional; when set it applies a `.glassEffect(.tint(...))` highlight
///   (e.g. orange for awaiting review).
/// - Accent colors always come from system colors; no conflicting hardcoded values inside the component.
struct GlassCard<Content: View>: View {
    var tint: Color? = nil
    var cornerRadius: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        let effect: Glass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(effect, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}
