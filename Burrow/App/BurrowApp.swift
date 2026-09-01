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
            // Replace (not append to) the default Help group so macOS's
            // "Burrow Help" item — which points at a non-existent help book
            // and shows "Help isn't available" — is removed.
            CommandGroup(replacing: .help) {
                Button("Burrow on GitHub") {
                    NSWorkspace.shared.open(Self.githubURL)
                }
                Divider()
                Button("Report an Issue…") {
                    IssueReporter.open(.bug)
                }
                Button("Request a Feature…") {
                    IssueReporter.open(.feature)
                }
            }
        }

        Settings {
            SettingsView(updater: updater)
        }
    }
}
