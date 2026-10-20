import AppKit

/// Starts app-wide background work at launch, independent of windows: with
/// "Open at login" or a restored session there may be no window at all, and
/// the disk monitor and its menu bar item must still run.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let diskMonitor = DiskMonitorViewModel()

    /// Unit tests launch the app as their host; a monitor the developer left
    /// on would otherwise post real Slack reports.
    static let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isTestHost else { return }
        diskMonitor.start()
        MenuBarController.shared.attach(diskMonitor)
        DockPresence.start()
    }

    /// Opening Burrow again (Finder, Spotlight) while it only lives in the
    /// menu bar: bring the Dock icon back before SwiftUI opens a window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { DockPresence.windowWillShow() }
        return true
    }
}
