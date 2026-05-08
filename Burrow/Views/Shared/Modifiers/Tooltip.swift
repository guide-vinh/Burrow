import AppKit
import SwiftUI

/// Pure-SwiftUI tooltip backed by `onHover` + an overlay. We do not rely on
/// `.help()` because it misbehaves inside `LazyVGrid`/`LazyVStack` and
/// across structural redraws (e.g. an optional column appearing post-scan).
struct TooltipModifier: ViewModifier {
    let text: String
    @State private var isHovering = false
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    // ~0.5s delay before showing, matching macOS feel.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if isHovering { visible = true }
                    }
                } else {
                    visible = false
                }
            }
            .overlay(alignment: .topLeading) {
                if visible && !text.isEmpty {
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                        )
                        .fixedSize()
                        .offset(y: -26)
                        .allowsHitTesting(false)
                        .zIndex(1000)
                        .transition(.opacity)
                }
            }
    }
}

extension View {
    /// Hover tooltip. Use instead of `.help(_:)` when SwiftUI's built-in
    /// helper misbehaves (lazy containers, structural updates, etc.).
    func tooltip(_ text: String) -> some View {
        modifier(TooltipModifier(text: text))
    }
}
