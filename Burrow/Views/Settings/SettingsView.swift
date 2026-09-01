import SwiftUI

/// Lives in the SwiftUI `Settings` scene. macOS opens it via ⌘, or via
/// "Burrow → Settings…" — also reachable from the sidebar Settings row.
struct SettingsView: View {
    @ObservedObject var updater: UpdaterController

    var body: some View {
        Form {
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))

                HStack {
                    Text("Burrow checks daily and notifies you when a new version is available.")
                        .font(.bodyS)
                        .foregroundStyle(Color.fgSecondary)
                    Spacer(minLength: Spacing.md)
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            }

            Section("Help & Feedback") {
                HStack {
                    Text("Found a bug or have an idea? Open a pre-filled issue on GitHub — your Burrow and macOS versions are included automatically.")
                        .font(.bodyS)
                        .foregroundStyle(Color.fgSecondary)
                    Spacer(minLength: Spacing.md)
                    Button("Report an Issue…") { IssueReporter.open(.bug) }
                }
            }
        }
        .frame(width: 420)
        .padding(.vertical, Spacing.md)
    }
}
