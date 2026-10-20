import AppKit
import Combine
import SwiftUI

/// Menu bar status item for the disk monitor, modelled on diskmon's: the
/// fullest disk's used percentage next to a drive icon, a warning triangle
/// once a disk is at or below the threshold, and a menu with each disk,
/// the threshold presets and quick actions. AppKit `NSStatusItem` rather
/// than SwiftUI `MenuBarExtra`, which needs macOS 13.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    static let shared = MenuBarController()

    private var vm: DiskMonitorViewModel?
    private var statusItem: NSStatusItem?
    private var observation: AnyCancellable?

    /// Called once from `AppDelegate`; safe to call again.
    func attach(_ vm: DiskMonitorViewModel) {
        guard self.vm == nil else { return }
        self.vm = vm
        // objectWillChange fires before the new value lands; refresh on the
        // next runloop turn so the menu reads the updated state.
        observation = vm.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    private func refresh() {
        guard let vm, vm.settings.enabled, vm.settings.showInMenuBar else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            DockPresence.menuBarItemShown = false
            return
        }
        let item = statusItem ?? makeStatusItem()
        statusItem = item
        DockPresence.menuBarItemShown = true

        let look = MenuBarFormat.look(vm.visibleReadings, threshold: vm.settings.thresholdPercent,
                                      display: vm.settings.percentDisplay)
        if let button = item.button {
            let image = NSImage(systemSymbolName: look.symbol, accessibilityDescription: "Disk Monitor")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            // Monospaced digits, so the item doesn't change width with every reading.
            button.attributedTitle = NSAttributedString(
                string: look.title.isEmpty ? "" : " \(look.title)",
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)]
            )
            button.toolTip = "Burrow Disk Monitor"
        }
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        return item
    }

    // MARK: - Menu

    /// Built when the menu opens rather than on every state change.
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            guard let vm else { return }
            menu.removeAllItems()
            fill(menu, from: vm)
        }
    }

    private func fill(_ menu: NSMenu, from vm: DiskMonitorViewModel) {

        menu.addItem(disabled("Burrow Disk Monitor"))
        menu.addItem(.separator())

        if vm.visibleReadings.isEmpty {
            menu.addItem(disabled("Not checked yet"))
        }
        for reading in vm.visibleReadings {
            menu.addItem(disabled(MenuBarFormat.line(for: reading, display: vm.settings.percentDisplay)))
        }
        menu.addItem(disabled(MenuBarFormat.schedule(last: vm.lastChecked, next: vm.nextCheck)))
        menu.addItem(.separator())

        let threshold = NSMenuItem(title: "Alert Threshold", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        let current = vm.settings.thresholdPercent
        // A value saved by an earlier version that isn't a preset is listed
        // too, in order, like the tab's picker.
        let choices = Set(DiskMonitorSettings.thresholdPresets + [current]).sorted()
        for value in choices {
            let entry = action("\(MenuBarFormat.percent(value)) free", #selector(setThreshold(_:)))
            entry.representedObject = value
            entry.state = value == current ? .on : .off
            sub.addItem(entry)
        }
        threshold.submenu = sub
        menu.addItem(threshold)

        let display = NSMenuItem(title: "Show Percentage As", action: nil, keyEquivalent: "")
        let displaySub = NSMenu()
        displaySub.autoenablesItems = false
        for mode in DiskMonitorSettings.PercentDisplay.allCases {
            let entry = action(mode.label, #selector(setPercentDisplay(_:)))
            entry.representedObject = mode.rawValue
            entry.state = mode == vm.settings.percentDisplay ? .on : .off
            displaySub.addItem(entry)
        }
        display.submenu = displaySub
        menu.addItem(display)

        let alertOnly = action("Only Post Alerts", #selector(toggleAlertOnly))
        alertOnly.state = vm.settings.alertOnly ? .on : .off
        alertOnly.isEnabled = vm.isSlackConfigured
        menu.addItem(alertOnly)

        let checkNow = action(vm.isChecking ? "Checking…" : "Check Now", #selector(checkNow))
        checkNow.isEnabled = !vm.isChecking
        menu.addItem(checkNow)

        menu.addItem(.separator())
        menu.addItem(action("Open Monitoring…", #selector(openMonitoring)))
        menu.addItem(action("Quit Burrow", #selector(quit), key: "q"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func setThreshold(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        vm?.settings.thresholdPercent = value
    }

    @objc private func setPercentDisplay(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = DiskMonitorSettings.PercentDisplay(rawValue: raw)
        else { return }
        vm?.settings.percentDisplay = mode
    }

    @objc private func toggleAlertOnly() {
        vm?.settings.alertOnly.toggle()
    }

    @objc private func checkNow() {
        guard let vm else { return }
        Task { await vm.check() }
    }

    @objc private func openMonitoring() {
        MonitoringNavigation.request()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Lets the menu bar bring a Burrow window forward on the Monitoring tab,
/// including when every window was closed (the app keeps running for the
/// monitor). The chosen `RootView` reacts to the notification (its window is
/// the notification's object); a newly created one picks up `pending`.
enum MonitoringNavigation {
    static let notification = Notification.Name("fun.burrow.showMonitoring")
    static var pending = false
    /// Windows hosting a `RootView`, held weakly. Kept here rather than as
    /// an NSWindow.identifier, which SwiftUI uses for window restoration.
    static let mainWindows = NSHashTable<NSWindow>.weakObjects()

    @MainActor
    static func request() {
        // Windows of a hidden app (⌘H) report isVisible == false; unhide
        // first so they count, instead of opening a duplicate window.
        let wasHidden = NSApp.isHidden
        if wasHidden { NSApp.unhide(nil) }
        // Back in the Dock first: an accessory app has no menu bar to show.
        DockPresence.windowWillShow()
        NSApp.activate(ignoringOtherApps: true)
        // Only windows hosting RootView — not Settings, which also qualifies
        // as a main window but has no Monitoring tab to switch to.
        let window = mainWindows.allObjects.first {
            $0.isVisible || $0.isMiniaturized || wasHidden
        }
        if let window {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: notification, object: window)
        } else {
            pending = true
            // Nothing to open the window with (⌘N remapped): don't leave a
            // stale request that a later, unrelated window would act on.
            if !openNewWindow() { pending = false }
        }
    }

    /// SwiftUI's WindowGroup adds File → New Window (⌘N); trigger it.
    @MainActor
    private static func openNewWindow() -> Bool {
        guard let items = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items),
              let newWindow = items.first(where: { $0.keyEquivalent == "n" && $0.keyEquivalentModifierMask == .command }),
              let menu = newWindow.menu
        else { return false }
        menu.performActionForItem(at: menu.index(of: newWindow))
        return true
    }
}

/// Weak handle on the NSWindow hosting a `RootView`, filled by
/// `MainWindowMarker`, so the view can tell which window a request targets.
final class HostWindow: ObservableObject {
    weak var window: NSWindow?
}

/// Registers the NSWindow hosting `RootView` in
/// `MonitoringNavigation.mainWindows` so the menu bar can find it.
struct MainWindowMarker: NSViewRepresentable {
    let host: HostWindow

    func makeNSView(context: Context) -> NSView { Marker(host: host) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Marker: NSView {
        let host: HostWindow

        init(host: HostWindow) {
            self.host = host
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                MonitoringNavigation.mainWindows.add(window)
                DockPresence.windowWillShow()
            }
            host.window = window
        }
    }
}

/// Pure text/icon choices for the status item, kept apart for tests.
enum MenuBarFormat {

    /// Icon + title: the fullest readable disk's used % ("74.0%") or free %
    /// ("26.0%"), with one decimal like the menu lines, a warning only when a disk is at or below the threshold, and
    /// "?" when one couldn't be read (not a warning: e.g. an unplugged drive).
    static func look(
        _ readings: [DiskMonitorReport.Reading],
        threshold: Double,
        display: DiskMonitorSettings.PercentDisplay = .used
    ) -> (symbol: String, title: String) {
        let readable = readings.filter { !$0.failed }
        let unreadable = readable.count < readings.count
        guard let fullest = readable.max(by: { $0.usedPercent < $1.usedPercent }) else {
            return ("internaldrive", unreadable ? "?" : "")
        }
        let symbol = DiskMonitorReport.isAlert(readings, threshold: threshold) ? "exclamationmark.triangle" : "internaldrive"
        let percent = display == .used ? fullest.usedPercent : fullest.freePercent
        return (symbol, "\(DiskMonitorReport.percent(percent))%" + (unreadable ? " ?" : ""))
    }

    /// "/  —  73.6% used, 130.7 GB free of 494.4 GB" (as in diskmon's menu),
    /// or "/  —  26.4% free, 130.7 GB of 494.4 GB".
    static func line(for r: DiskMonitorReport.Reading, display: DiskMonitorSettings.PercentDisplay = .used) -> String {
        if r.failed { return "\(r.path)  —  couldn't be read" }
        return "\(r.path)  —  \(usage(r, display))"
    }

    /// The figures shared by the menu and the Monitoring tab.
    static func usage(_ r: DiskMonitorReport.Reading, _ display: DiskMonitorSettings.PercentDisplay) -> String {
        let free = DiskMonitorReport.gb(r.free), total = DiskMonitorReport.gb(r.total)
        switch display {
        // One decimal (like Slack's report), so 4.8% doesn't read as "5%"
        // next to a 5% threshold.
        case .used: return "\(DiskMonitorReport.percent(r.usedPercent))% used, \(free) free of \(total)"
        case .free: return "\(DiskMonitorReport.percent(r.freePercent))% free, \(free) of \(total)"
        }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "HH:mm"
        return f
    }()

    static func schedule(last: Date?, next: Date?) -> String {
        let lastText = last.map { "Last check \(time.string(from: $0))" } ?? "Not checked yet"
        guard let next else { return lastText }
        return "\(lastText) · next \(time.string(from: next))"
    }

    static func percent(_ value: Double) -> String { DiskMonitorReport.threshold(value) }
}
