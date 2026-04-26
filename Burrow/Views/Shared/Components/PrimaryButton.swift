import SwiftUI

/// Solid coral CTA. Used for the Scan and primary onboarding actions.
struct PrimaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if let icon { Image(systemName: icon) }
                Text(title).font(.bodySMed)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 10)
            .background(Color.accentPrimary)
            .foregroundStyle(Color.fgInverse)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
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
