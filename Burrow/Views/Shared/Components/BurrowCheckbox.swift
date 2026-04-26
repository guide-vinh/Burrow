import SwiftUI

/// Two-state square checkbox with the coral accent fill when checked.
/// Custom because SwiftUI's `Toggle(.checkbox)` style doesn't honour
/// the design tokens.
struct BurrowCheckbox: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isOn ? Color.accentPrimary : Color.surfacePrimary)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(isOn ? Color.clear : Color.fgMuted, lineWidth: 1.5)
                    }
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.fgInverse)
                }
            }
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
    }
}

struct BurrowCheckbox_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Spacing.md) {
            CheckboxStateWrapper(initial: false)
            CheckboxStateWrapper(initial: true)
        }
        .padding()
    }

    private struct CheckboxStateWrapper: View {
        @State var isOn: Bool
        init(initial: Bool) { _isOn = State(initialValue: initial) }
        var body: some View { BurrowCheckbox(isOn: $isOn) }
    }
}
