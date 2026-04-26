import SwiftUI

/// Transient confirmation that a dry-run apply ran. Auto-dismissed by
/// the view-model 5 seconds after appearing, or manually via the ×.
struct PreviewBanner: View {
    let summary: CleanViewModel.PreviewSummary
    let onShowInFinder: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.accentPrimary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Preview complete")
                    .font(.bodySMed)
                    .foregroundStyle(Color.fgPrimary)
                Text("Would have moved \(summary.bytes, format: .byteCount(style: .file)) across \(summary.items) \(summary.items == 1 ? "path" : "paths")")
                    .font(.bodyS)
                    .foregroundStyle(Color.fgSecondary)
                    .monospacedDigit()
            }

            Spacer()

            Button("Show in Finder", action: onShowInFinder)
                .buttonStyle(.plain)
                .font(.bodySMed)
                .foregroundStyle(Color.accentPrimary)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.fgMuted)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(Color.surfaceInverseSoft)
    }
}

struct PreviewBanner_Previews: PreviewProvider {
    static var previews: some View {
        PreviewBanner(
            summary: .init(items: 2, bytes: 48_500_000),
            onShowInFinder: {},
            onDismiss: {}
        )
        .frame(width: 760)
        .padding()
    }
}
