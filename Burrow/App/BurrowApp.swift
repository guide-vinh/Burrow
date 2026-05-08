import SwiftUI

@main
struct BurrowApp: App {
    @StateObject private var updater = UpdaterController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(updater)
        }
        .commands {
            // Replaces the default no-op "Burrow → About Burrow" group with
            // a "Check for Updates…" item (Sparkle-standard placement).
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
        }

        Settings {
            SettingsView(updater: updater)
        }
    }
}
