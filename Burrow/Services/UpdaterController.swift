import Foundation
import Sparkle

/// Owns the Sparkle `SPUStandardUpdaterController` and exposes the bits the
/// rest of the app needs (a published `canCheckForUpdates`, an
/// `automaticallyChecksForUpdates` toggle, and a `checkForUpdates()` action).
@MainActor
final class UpdaterController: ObservableObject {

    private let controller: SPUStandardUpdaterController

    @Published private(set) var canCheckForUpdates = false

    init() {
        // startingUpdater: true — Sparkle starts scheduled checks immediately
        // using SUEnableAutomaticChecks / SUScheduledCheckInterval from
        // Info.plist. No delegate yet; defaults are good enough for v0.1.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Mirror the updater's `canCheckForUpdates` into a Published value so
        // SwiftUI menu/button items can `.disabled(!vm.canCheckForUpdates)`.
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Bound to the `Automatically check for updates` toggle in Settings.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Silent launch-time probe. Sparkle only surfaces UI if a new
    /// version is found; otherwise it's a no-op. Skipped when the user
    /// has turned off auto-update in Settings so the toggle remains a
    /// proper kill switch.
    func checkOnLaunch() {
        guard controller.updater.automaticallyChecksForUpdates else { return }
        controller.updater.checkForUpdatesInBackground()
    }
}
