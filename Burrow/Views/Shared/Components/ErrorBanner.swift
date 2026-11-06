import SwiftUI

/// Red strip under a screen header that explains a failed (or partially
/// failed) action, with a close button. Without it a failed apply looks
/// like a silent no-op.
struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.destructive)
            Text(message)
                .font(.bodyS)
                .foregroundStyle(Color.destructive)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.fgSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.sm)
        .background(Color.Risk.highBG)
    }
}
