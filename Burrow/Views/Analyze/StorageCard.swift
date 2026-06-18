import SwiftUI

/// Left-column card: the storage donut with a centered "used of total"
/// label, a divider, and a color-dot legend of every category.
struct StorageCard: View {

    let breakdown: StorageBreakdown

    var body: some View {
        VStack(spacing: Spacing.xl) {
            donut
            Divider()
                .background(Color.borderSubtle)
            legend
        }
        .padding(Spacing.xl)
        .borderedCard()
    }

    // MARK: Donut

    private var donut: some View {
        ZStack {
            DonutChart(
                segments: breakdown.categories.map {
                    DonutChart.Segment(value: Double($0.bytes), color: $0.color)
                },
                thickness: 30
            )
            .frame(width: 200, height: 200)

            VStack(spacing: Spacing.xs - 1) {
                Text(breakdown.humanUsed)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.fgPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("of \(breakdown.humanTotal) used")
                    .font(.captionM)
                    .foregroundStyle(Color.fgSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(breakdown.usedPercent)% full")
                    .font(.pill)
                    .foregroundStyle(Color.accentPrimaryHover)
                    .padding(.horizontal, Spacing.sm + 1)
                    .padding(.vertical, Spacing.xs - 1)
                    .background(Capsule().fill(Color.accentSoft))
            }
            // Keep the label inside the donut hole (Ø ≈ 140 for a 200px ring).
            .frame(width: 138)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: Legend

    private var legend: some View {
        VStack(spacing: Spacing.md + 2) {
            ForEach(breakdown.categories) { category in
                HStack(spacing: Spacing.sm + 2) {
                    Circle()
                        .fill(category.color)
                        .overlay(
                            Circle()
                                .stroke(category.kind.dotStroke ?? .clear, lineWidth: 1)
                        )
                        .frame(width: 10, height: 10)
                    Text(category.title)
                        .font(.bodyS)
                        .foregroundStyle(Color.fgSecondary)
                    Spacer(minLength: Spacing.sm)
                    Text(category.humanSize)
                        .font(.bodySMed)
                        .foregroundStyle(Color.fgPrimary)
                }
            }
        }
    }
}
