import SwiftUI

/// One leftover-file row in the Uninstall detail pane. Shows checkbox,
/// category icon, path (last component prominent + full path muted),
/// risk pill, size. Disabled + faded when the match requires admin
/// privilege (Phase 2 has no privileged helper). Italic "(shared)"
/// suffix when the match targets a vendor-shared root.
struct LeftoverRow: View {
    let match: LeftoverMatch
    @Binding var isChecked: Bool

    private var requiresPrivilege: Bool { match.pattern.needsPrivilege == true }

    var body: some View {
        HStack(spacing: Spacing.md) {
            BurrowCheckbox(isOn: $isChecked)

            Image(systemName: Iconography.sfSymbol(for: match.pattern.category))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.fgSecondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Spacing.xs) {
                    Text(match.url.lastPathComponent)
                        .font(.bodyM)
                        .foregroundStyle(Color.fgPrimary)
                        .lineLimit(1)
                    if match.isShared {
                        Text("(shared)")
                            .font(.captionS)
                            .italic()
                            .foregroundStyle(Color.fgMuted)
                    }
                    if requiresPrivilege {
                        Text("(needs admin)")
                            .font(.captionS)
                            .italic()
                            .foregroundStyle(Color.fgMuted)
                    }
                }
                Text(match.url.deletingLastPathComponent().path)
                    .font(.captionS)
                    .foregroundStyle(Color.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: Spacing.sm)

            RiskPill(level: match.pattern.risk.asRiskLevel)

            Text(match.bytes, format: .byteCount(style: .file))
                .font(.bodyS)
                .foregroundStyle(Color.fgSecondary)
                .frame(minWidth: 70, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .opacity(requiresPrivilege ? 0.5 : 1.0)
        .disabled(requiresPrivilege)
        .tooltip(match.url.path)
    }
}

struct LeftoverRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Spacing.xs) {
            row(.safe, shared: false, priv: false, bytes: 4_096)
            row(.caution, shared: false, priv: false, bytes: 524_288)
            row(.highValue, shared: false, priv: false, bytes: 8_192_000)
            row(.highValue, shared: true,  priv: false, bytes: 100_000_000)
            row(.caution, shared: false, priv: true,  bytes: 1_024)
        }
        .padding()
        .frame(width: 720)
    }

    @ViewBuilder
    private static func row(
        _ risk: LeftoverPattern.Risk,
        shared: Bool,
        priv: Bool,
        bytes: Int64
    ) -> some View {
        Wrapper(
            match: LeftoverMatch(
                url: URL(fileURLWithPath: "/Users/me/Library/Caches/preview-fixture-\(risk.rawValue).cache"),
                bytes: bytes,
                pattern: LeftoverPattern(
                    path: "preview",
                    risk: risk,
                    category: "cache",
                    needsPrivilege: priv ? true : nil,
                    description: "Preview row"
                ),
                isShared: shared
            )
        )
    }

    private struct Wrapper: View {
        let match: LeftoverMatch
        @State var checked = true
        var body: some View { LeftoverRow(match: match, isChecked: $checked) }
    }
}
