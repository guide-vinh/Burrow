import SwiftUI

/// Small uppercase pill (LOW / MED / HIGH) coloured per `RiskLevel`.
/// Per UI_ARCH section 8 (accessibility): uses uppercase text so colour
/// is not the only signal.
struct RiskPill: View {
    let level: RiskLevel

    var body: some View {
        Text(level.rawValue.uppercased())
            .font(.pill)
            .tracking(0.5)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 2)
            .background(level.background)
            .foregroundStyle(level.foreground)
            .clipShape(Capsule())
    }
}

private extension RiskLevel {
    var background: Color {
        switch self {
        case .low:    Color.Risk.lowBG
        case .medium: Color.Risk.medBG
        case .high:   Color.Risk.highBG
        }
    }
    var foreground: Color {
        switch self {
        case .low:    Color.Risk.lowFG
        case .medium: Color.Risk.medFG
        case .high:   Color.Risk.highFG
        }
    }
}

struct RiskPill_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Spacing.sm) {
            RiskPill(level: .low)
            RiskPill(level: .medium)
            RiskPill(level: .high)
        }
        .padding()
    }
}
