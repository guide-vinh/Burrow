import SwiftUI

/// Solid coral CTA. Used for the Scan and primary onboarding actions.
struct PrimaryButton: View {
    let title: String
    let icon: String?
    let isLoading: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(Color.fgInverse)
                } else if let icon {
                    Image(systemName: icon)
                }
                Text(title).font(.bodySMed)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 10)
            .background(Color.accentPrimary)
            .foregroundStyle(Color.fgInverse)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            // Only fade for "logically disabled" (e.g. catalog not loaded);
            // during isLoading, keep full opacity so the spinner + text stay
            // readable on the coral background.
            .opacity((isEnabled || isLoading) ? 1.0 : 0.6)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isLoading)
    }
}

struct PrimaryButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Spacing.md) {
            PrimaryButton("Scan") {}
            PrimaryButton("Move to Trash", icon: "trash") {}
        }
        .padding()
    }
}
