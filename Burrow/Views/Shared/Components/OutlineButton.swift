import SwiftUI

/// Transparent-fill, subtle-border button. Used for secondary actions
/// where a coloured fill would compete with the primary CTA.
struct OutlineButton: View {
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
            .foregroundStyle(Color.fgPrimary)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct OutlineButton_Previews: PreviewProvider {
    static var previews: some View {
        OutlineButton("Cancel") {}
            .padding()
    }
}
