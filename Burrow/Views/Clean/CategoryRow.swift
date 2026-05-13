import SwiftUI

/// One row in a category group card. Shows checkbox, icon, title,
/// risk pill, and (post-scan) the reclaimable size.
struct CategoryRow: View {
    let category: CleanCategory
    let scanResult: ScanResult?
    @Binding var isSelected: Bool
    let onReveal: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            BurrowCheckbox(isOn: $isSelected)
                .padding(.top, 2)

            Image(systemName: Iconography.sfSymbol(for: category.icon))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.fgSecondary)
                .frame(width: 20, height: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                // Line 1 — title, risk pill, size, info
                HStack(spacing: Spacing.sm) {
                    Text(category.title)
                        .font(.bodyM)
                        .foregroundStyle(Color.fgPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    RiskPill(level: category.risk)
                    Spacer(minLength: Spacing.sm)
                    if let bytes = scanResult?.totalBytes {
                        Group {
                            if bytes > 0 {
                                Text(bytes, format: .byteCount(style: .file))
                            } else {
                                Text("—")
                            }
                        }
                        .font(.bodyS)
                        .foregroundStyle(Color.fgSecondary)
                        .monospacedDigit()
                    }
                    Button(action: onReveal) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.fgMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                }

                // Line 2 — category summary as muted description
                Text(category.summary)
                    .font(.captionS)
                    .foregroundStyle(Color.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tooltip("\(category.title) — \(category.summary)")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}
