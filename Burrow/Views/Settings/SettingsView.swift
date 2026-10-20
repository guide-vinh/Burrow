import AppKit
import SwiftUI

/// Lives in the SwiftUI `Settings` scene. macOS opens it via ⌘, or via
/// "Burrow → Settings…" — also reachable from the sidebar Settings row.
struct SettingsView: View {
    @ObservedObject var updater: UpdaterController
    @ObservedObject var catalogUpdates: CatalogUpdateViewModel

    // SMAppService status is an IPC call; read it on appear, not per render.
    @State private var openAtLogin = false
    @State private var loginItemMessage: String?

    var body: some View {
        Form {
            if LoginItem.isSupported {
                Section("General") {
                    Toggle("Open Burrow at login", isOn: Binding(
                        get: { openAtLogin },
                        set: { newValue in
                            loginItemMessage = LoginItem.setEnabled(newValue)
                            openAtLogin = LoginItem.isEnabled
                        }
                    ))
                    if let loginItemMessage {
                        Text(loginItemMessage)
                            .font(.captionM)
                            .foregroundStyle(Color.fgSecondary)
                    }
                }
                .onAppear(perform: refreshLoginItem)
                // Approving in System Settings happens outside the app.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    refreshLoginItem()
                }
            }

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

            CatalogUpdatesSection(vm: catalogUpdates)

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

    private func refreshLoginItem() {
        openAtLogin = LoginItem.isEnabled
        loginItemMessage = LoginItem.needsApproval ? LoginItem.approvalMessage : nil
    }
}
