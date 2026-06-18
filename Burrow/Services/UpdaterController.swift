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

        // Force a silent update check on every launch. Per Sparkle's docs this
        // MUST run immediately after the updater starts and before the next
        // runloop cycle — calling it later (e.g. from a SwiftUI `.task`) races
        // the scheduler and no-ops with "sessionInProgress". Gated by the
        // auto-update preference so the Settings toggle stays a kill switch.
        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }

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
}
