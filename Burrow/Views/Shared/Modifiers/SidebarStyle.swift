import SwiftUI

/// Sidebar treatment: surface-secondary fill, no border lines. Per
/// the design directions in CLAUDE_CODE_KICKOFF.md.
struct SidebarStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.surfaceSecondary)
    }
}

extension View {
    func sidebarStyle() -> some View { modifier(SidebarStyle()) }
}
