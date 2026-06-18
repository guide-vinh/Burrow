import AppKit
import SwiftUI

/// One app row in the Licenses list: icon, name + verdict badge, reason,
/// version, and (when found) App Store price.
struct LicenseRow: View {
    let license: AppLicense
    let onReveal: () -> Void
    let onOpenStore: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: license.app.bundleURL.path))
                .resizable()
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Spacing.sm) {
                    Text(license.app.name)
                        .font(.bodyM.weight(.medium))
                        .foregroundStyle(Color.fgPrimary)
                        .lineLimit(1)
                    StatusBadge(verdict: license.verdict)
                }
                Text(license.reason)
                    .font(.captionM)
                    .foregroundStyle(Color.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: Spacing.sm)

            VStack(alignment: .trailing, spacing: 2) {
                if let version = license.app.version {
                    Text("v\(version)")
                        .font(.captionM)
                        .foregroundStyle(Color.fgSecondary)
                }
                if let store = license.store {
                    Text(store.priceLabel)
                        .font(.captionS)
                        .foregroundStyle(store.isFree ? Color.fgMuted : Color.accentPrimary)
                }
            }
        }
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, Spacing.lg)
        .borderedCard()
        .contextMenu {
            Button("Reveal in Finder", action: onReveal)
            if license.store?.listingURL != nil {
                Button("View on App Store", action: onOpenStore)
            }
        }
    }
}
