import SwiftUI

/// One destination row in the left sidebar. Active rows get a tertiary
/// surface fill + medium-weight title; inactive rows are flat.
struct SidebarRow: View {
    let icon: String
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm + 2) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 16, height: 16)
                Text(title).font(isActive ? .bodySMed : .bodyS)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isActive ? Color.fgPrimary : Color.fgSecondary)
            .padding(.horizontal, Spacing.md)
            .frame(height: 36)
            .background(isActive ? Color.surfaceTertiary : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SidebarRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 2) {
            SidebarRow(icon: "sparkles", title: "Clean", isActive: true) {}
            SidebarRow(icon: "trash", title: "Uninstall", isActive: false) {}
            SidebarRow(icon: "chart.pie", title: "Analyze", isActive: false) {}
            SidebarRow(icon: "waveform.path.ecg", title: "Status", isActive: false) {}
        }
        .frame(width: 220)
        .padding()
    }
}
