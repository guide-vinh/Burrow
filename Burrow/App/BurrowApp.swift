import AppKit
import SwiftUI

@main
struct BurrowApp: App {
    @StateObject private var updater = UpdaterController()

    private static let githubURL = URL(string: "https://github.com/guide-vinh/Burrow")!

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
            CommandGroup(after: .help) {
                Button("Burrow on GitHub") {
                    NSWorkspace.shared.open(Self.githubURL)
                }
            }
        }

        Settings {
            SettingsView(updater: updater)
        }
    }
}
