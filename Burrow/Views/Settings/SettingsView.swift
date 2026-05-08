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
        }
        .frame(width: 420)
        .padding(.vertical, Spacing.md)
    }
}
