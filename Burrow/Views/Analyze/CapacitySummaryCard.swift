import SwiftUI

/// Left-column card below the donut: free-space headline, a used/total
/// progress bar, and a caption naming the volume.
struct CapacitySummaryCard: View {

    let breakdown: StorageBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Free space remaining")
                        .font(.captionM)
                        .foregroundStyle(Color.fgSecondary)
                    Text(breakdown.humanFree)
                        .font(.titleL)
                        .foregroundStyle(Color.fgPrimary)
                }
                Spacer(minLength: 0)
                Text("\(breakdown.freePercent)%")
                    .font(.bodySMed)
                    .foregroundStyle(Color.accentPrimary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.surfaceTertiary)
                    Capsule()
                        .fill(Color.accentPrimary)
                        .frame(width: max(0, geometry.size.width * breakdown.usedFraction))
                }
            }
            .frame(height: 8)

            Text("\(breakdown.humanUsed) of \(breakdown.humanTotal) used on \(breakdown.volumeName)")
                .font(.captionS)
                .foregroundStyle(Color.fgMuted)
        }
        .padding(Spacing.lg + 2)
        .borderedCard()
    }
}
