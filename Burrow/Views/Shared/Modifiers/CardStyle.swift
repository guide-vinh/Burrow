import SwiftUI

/// Surface-secondary fill with large continuous corners. Used for the
/// grouped category cards in the Clean tab body. Per UI_ARCH section 5
/// the gap *between* rows is the divider — never add hairlines inside
/// the card.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}
