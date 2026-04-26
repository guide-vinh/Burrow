import AppKit
import SwiftUI

/// First-launch sheet shown when Full Disk Access is not granted.
/// macOS applies TCC permission changes only to fresh processes, so
/// after the user toggles FDA in System Settings they must quit and
/// relaunch Burrow for the new permission to take effect — the sheet
/// surfaces a "Quit Burrow" button to make that one click.
struct FullDiskAccessSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            EmptyState(
                icon: "lock.shield",
                title: "Full Disk Access required",
                subtitle: "Burrow needs Full Disk Access to scan caches in ~/Library. Open System Settings → Privacy & Security → Full Disk Access, enable Burrow, then quit and relaunch this app.",
                action: ("Open System Settings", openSettings)
            )

            HStack(spacing: Spacing.xl) {
                Button("Quit Burrow") {
                    NSApplication.shared.terminate(nil)
                }
                Button("Skip for now") {
                    isPresented = false
                }
            }
            .buttonStyle(.plain)
            .font(.bodyS)
            .foregroundStyle(Color.fgSecondary)
            .padding(.bottom, Spacing.lg)
        }
        .frame(width: 460, height: 380)
        .background(Color.surfacePrimary)
    }

    private func openSettings() {
        FullDiskAccess.openSystemSettings()
    }
}

struct FullDiskAccessSheet_Previews: PreviewProvider {
    static var previews: some View {
        SheetPreview()
    }

    private struct SheetPreview: View {
        @State var presented = true
        var body: some View {
            FullDiskAccessSheet(isPresented: $presented)
        }
    }
}
