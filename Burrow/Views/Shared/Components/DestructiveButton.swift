import SwiftUI

/// Red CTA for irreversible-feeling actions. Per UI_ARCH section 8
/// always pairs the colour with text + icon so colour is not the only
/// signal.
struct DestructiveButton: View {
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
            .background(Color.destructive)
            .foregroundStyle(Color.fgInverse)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct DestructiveButton_Previews: PreviewProvider {
    static var previews: some View {
        DestructiveButton("Move to Trash", icon: "trash") {}
            .padding()
    }
}
