import SwiftUI

/// All-caps muted label, used above grouped lists ("System Junk",
/// "Browsers", etc.) to mirror the Pencil mockup.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.captionM)
            .tracking(0.8)
            .foregroundStyle(Color.fgMuted)
    }
}

struct SectionLabel_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionLabel(text: "System Junk")
            SectionLabel(text: "Browsers")
            SectionLabel(text: "Developer Tools")
        }
        .padding()
    }
}
