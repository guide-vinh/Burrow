import AppKit
import SwiftUI

/// One row in the Uninstall tab's left list. Active rows pick up the
/// surface-tertiary fill + medium-weight title (same treatment as
/// `SidebarRow`). The icon is fetched via `NSWorkspace` and bridged
/// to a SwiftUI `Image`.
struct AppListRow: View {
    let app: InstalledApp
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm + 2) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(isActive ? .bodySMed : .bodyS)
                        .foregroundStyle(Color.fgPrimary)
                        .lineLimit(1)
                    Text(app.bundleId)
                        .font(.captionS)
                        .foregroundStyle(Color.fgMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(isActive ? Color.surfaceTertiary : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct AppListRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 2) {
            AppListRow(
                app: InstalledApp(
                    bundleId: "com.tinyspeck.slackmacgap",
                    name: "Slack",
                    displayName: nil,
                    bundleURL: URL(fileURLWithPath: "/Applications/Slack.app"),
                    version: "4.36.140",
                    build: "1",
                    bundleSize: nil,
                    lastOpenedDate: nil,
                    installSource: .manual
                ),
                isActive: true,
                action: {}
            )
            AppListRow(
                app: InstalledApp(
                    bundleId: "com.spotify.client",
                    name: "Spotify",
                    displayName: nil,
                    bundleURL: URL(fileURLWithPath: "/Applications/Spotify.app"),
                    version: "1.2.0",
                    build: "1",
                    bundleSize: nil,
                    lastOpenedDate: nil,
                    installSource: .manual
                ),
                isActive: false,
                action: {}
            )
        }
        .frame(width: 320)
        .padding()
    }
}
