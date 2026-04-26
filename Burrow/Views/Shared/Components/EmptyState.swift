import SwiftUI

/// Hero-styled empty state with icon, headline, subtitle, and optional
/// primary action. Used for "FDA needed", "Ready to scan", "All clean".
struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: (label: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Color.fgMuted)
            Text(title)
                .font(.titleM)
                .foregroundStyle(Color.fgPrimary)
            Text(subtitle)
                .font(.bodyS)
                .foregroundStyle(Color.fgSecondary)
                .multilineTextAlignment(.center)
            if let action {
                PrimaryButton(action.label, action: action.run)
                    .padding(.top, Spacing.sm)
            }
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: 360)
    }
}

struct EmptyState_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Spacing.lg) {
            EmptyState(
                icon: "sparkles",
                title: "Ready to scan",
                subtitle: "Find caches, logs, and developer junk you can safely reclaim.",
                action: ("Scan", {})
            )
            EmptyState(
                icon: "lock.shield",
                title: "Full Disk Access required",
                subtitle: "Grant access in System Settings to scan ~/Library.",
                action: ("Open Settings", {})
            )
            EmptyState(
                icon: "checkmark.circle",
                title: "All clean",
                subtitle: "Nothing to reclaim right now.",
                action: nil
            )
        }
        .padding()
    }
}
