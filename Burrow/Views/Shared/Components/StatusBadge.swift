import SwiftUI

/// Small colored capsule for a license verdict (e.g. APP STORE / UNVERIFIED).
/// Uppercase text so color is not the only signal (matches `RiskPill`).
struct StatusBadge: View {
    let verdict: LicenseVerdict

    var body: some View {
        Text(verdict.title.uppercased())
            .font(.pill)
            .tracking(0.5)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 2)
            .background(verdict.background)
            .foregroundStyle(verdict.color)
            .clipShape(Capsule())
    }
}
