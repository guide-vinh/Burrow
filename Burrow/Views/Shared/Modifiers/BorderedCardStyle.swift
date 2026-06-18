import SwiftUI

/// Secondary-surface card with a subtle hairline border and large
/// continuous corners. Used by the Analyze tab's storage / capacity /
/// folder cards, which read against the primary surface. Unlike
/// `CardStyle`, this one draws an outline (matching the Analyze mockup).
struct BorderedCardStyle: ViewModifier {
    var cornerRadius: CGFloat = Radius.lg

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.surfaceSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.borderSubtle, lineWidth: 1)
            )
    }
}

extension View {
    func borderedCard(cornerRadius: CGFloat = Radius.lg) -> some View {
        modifier(BorderedCardStyle(cornerRadius: cornerRadius))
    }
}
