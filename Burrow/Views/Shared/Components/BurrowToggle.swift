import SwiftUI

/// iOS-style switch tinted with Burrow's accent. Wraps SwiftUI's
/// `Toggle(.switch)`; the label slot is hidden because callers supply
/// their own label text alongside.
struct BurrowToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(Color.accentPrimary)
    }
}

struct BurrowToggle_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Spacing.md) {
            ToggleStateWrapper(initial: false)
            ToggleStateWrapper(initial: true)
        }
        .padding()
    }

    private struct ToggleStateWrapper: View {
        @State var isOn: Bool
        init(initial: Bool) { _isOn = State(initialValue: initial) }
        var body: some View { BurrowToggle(isOn: $isOn) }
    }
}
