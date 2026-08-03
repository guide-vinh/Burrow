import AppKit
import SwiftUI

/// Floating tooltip panel shared by every `.tooltip(_:)` call-site.
/// A borderless non-activating NSPanel positioned at the mouse can never
/// be cut off by card `clipShape`s or scroll-view bounds — the previous
/// overlay-based version clipped at the edges of each card.
private final class TooltipPanel {
    static let shared = TooltipPanel()

    private let panel: NSPanel
    private let label: NSTextField
    private let container: NSView

    private static let padH: CGFloat = 6
    private static let padV: CGFloat = 3
    private static let maxWidth: CGFloat = 400

    private init() {
        label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.drawsBackground = false
        label.isSelectable = false

        container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 4
        container.layer?.borderWidth = 1
        container.addSubview(label)

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.contentView = container
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(_ text: String) {
        guard !text.isEmpty else { return }

        label.stringValue = text
        label.preferredMaxLayoutWidth = Self.maxWidth
        var size = label.intrinsicContentSize
        size.width = min(size.width, Self.maxWidth)
        label.frame = NSRect(x: Self.padH, y: Self.padV, width: size.width, height: size.height)

        // Resolve dynamic colors at show-time so appearance switches are honored.
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            container.layer?.borderColor = NSColor.separatorColor.cgColor
        }

        let frameSize = NSSize(
            width: size.width + Self.padH * 2,
            height: size.height + Self.padV * 2
        )
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x + 4, y: mouse.y - 22 - frameSize.height)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            let visible = screen.visibleFrame
            origin.x = max(min(origin.x, visible.maxX - frameSize.width), visible.minX)
            if origin.y < visible.minY {
                origin.y = mouse.y + 22  // no room below the cursor — flip above
            }
        }

        panel.setFrame(NSRect(origin: origin, size: frameSize), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

/// Hover tracking for the shared tooltip panel. We do not rely on
/// `.help()` because it misbehaves inside `LazyVGrid`/`LazyVStack` and
/// across structural redraws (e.g. an optional column appearing post-scan).
struct TooltipModifier: ViewModifier {
    let text: String
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    // ~0.5s delay before showing, matching macOS feel.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if isHovering { TooltipPanel.shared.show(text) }
                    }
                } else {
                    TooltipPanel.shared.hide()
                }
            }
            .onDisappear {
                if isHovering { TooltipPanel.shared.hide() }
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
