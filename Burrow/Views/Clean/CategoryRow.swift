import SwiftUI

/// One row in a category group card. Shows checkbox, icon, title,
/// risk pill, and (post-scan) the reclaimable size.
struct CategoryRow: View {
    let category: CleanCategory
    let scanResult: ScanResult?
    @Binding var isSelected: Bool
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            BurrowCheckbox(isOn: $isSelected)

            Image(systemName: Iconography.sfSymbol(for: category.icon))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.fgSecondary)
                .frame(width: 20, height: 20)

            Text(category.title)
                .font(.bodyM)
                .foregroundStyle(Color.fgPrimary)

            Button(action: onReveal) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.fgMuted)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")

            Spacer(minLength: Spacing.sm)

            RiskPill(level: category.risk)

            if let bytes = scanResult?.totalBytes {
                Text(bytes, format: .byteCount(style: .file))
                    .font(.bodyS)
                    .foregroundStyle(Color.fgSecondary)
                    .frame(minWidth: 70, alignment: .trailing)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}
