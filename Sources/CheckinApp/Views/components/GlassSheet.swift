import SwiftUI

/// Glass wrapper for dialogs / forms (sheet content container, `.glassEffect()`).
struct GlassSheet<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassEffect(Glass.regular, in: RoundedRectangle(cornerRadius: 24))
            .presentationBackground(.ultraThinMaterial)
    }
}
