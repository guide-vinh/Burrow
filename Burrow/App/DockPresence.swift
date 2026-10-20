import AppKit

/// Takes Burrow out of the Dock while only its menu bar item is left: closing
/// the last window turns the app into an accessory (no Dock icon, no app
/// menu) as long as the disk monitor's status item is showing, and any window
/// opening again brings the Dock icon back. Without the status item the app
/// stays a regular Dock app, so it can always be reached.
@MainActor
enum DockPresence {

    /// Kept in sync by `MenuBarController`. Hiding the status item restores
    /// the Dock icon, otherwise a windowless app would be unreachable.
    static var menuBarItemShown = false {
        didSet { if !menuBarItemShown { setPolicy(.regular) } }
    }

    private static var closeObserver: NSObjectProtocol?

    /// Called once from `AppDelegate`.
    static func start() {
        guard closeObserver == nil else { return }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { _ in
            // The closing window still counts as visible here; decide once
            // it's gone.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { windowClosed() }
            }
        }
    }

    /// A window is opening or being brought forward: show the Dock icon.
    static func windowWillShow() {
        setPolicy(.regular)
    }

    private static func windowClosed() {
        guard menuBarItemShown, !hasOpenWindow else { return }
        setPolicy(.accessory)
    }

    /// A titled window on screen or minimized to the Dock — the status item's
    /// menu and other borderless panels don't count.
    private static var hasOpenWindow: Bool {
        NSApp.windows.contains {
            $0.styleMask.contains(.titled) && ($0.isVisible || $0.isMiniaturized)
        }
    }

    private static func setPolicy(_ policy: NSApplication.ActivationPolicy) {
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }
}
