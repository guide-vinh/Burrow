import SwiftUI

/// Transient confirmation that an apply ran — a dry-run preview, a real
/// move to Trash, or a real permanent delete, per `summary.kind`.
/// Auto-dismissed by the view-model 5 seconds after appearing, or
/// manually via the ×.
struct PreviewBanner: View {
    let summary: PreviewSummary
    let actionTitle: String
    let onAction: () -> Void
    let onDismiss: () -> Void

    private var title: String {
        switch summary.kind {
        case .preview:            return "Preview complete"
        case .trashed, .deleted:  return "Cleanup complete"
        }
    }

    private var detail: String {
        let bytes = summary.bytes.formatted(.byteCount(style: .file))
        let paths = "\(summary.items) \(summary.items == 1 ? "path" : "paths")"
        switch summary.kind {
        case .preview: return "Would have moved \(bytes) across \(paths)"
        case .trashed: return "Moved \(bytes) across \(paths) to the Trash"
        case .deleted: return "Deleted \(bytes) across \(paths)"
        }
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.accentPrimary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.bodySMed)
                    .foregroundStyle(Color.fgPrimary)
                Text(detail)
                    .font(.bodyS)
                    .foregroundStyle(Color.fgSecondary)
                    .monospacedDigit()
            }

            Spacer()

            Button(actionTitle, action: onAction)
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
            actionTitle: "View Log",
            onAction: {},
            onDismiss: {}
        )
        .frame(width: 760)
        .padding()
    }
}
