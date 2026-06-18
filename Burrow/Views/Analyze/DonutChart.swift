import SwiftUI

/// A donut (ring) chart. Each segment is drawn as a trimmed circle stroke;
/// the ring thickness produces the hollow center. Caller sizes it via a
/// `.frame`; with `thickness == width · 0.15` the hole matches the mockup's
/// 0.7 inner-radius. Place a center label by overlaying with a `ZStack`.
struct DonutChart: View {

    struct Segment: Identifiable {
        let id = UUID()
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    var thickness: CGFloat = 30

    var body: some View {
        ZStack {
            ForEach(arcs) { arc in
                Circle()
                    .trim(from: arc.start, to: arc.end)
                    .stroke(
                        arc.color,
                        style: StrokeStyle(lineWidth: thickness, lineCap: .butt)
                    )
            }
        }
        // Stroke is centered on the path; pad so it stays inside the frame.
        .padding(thickness / 2)
        .rotationEffect(.degrees(-90))
    }

    private struct Arc: Identifiable {
        let id = UUID()
        let start: CGFloat
        let end: CGFloat
        let color: Color
    }

    private var arcs: [Arc] {
        let total = max(segments.reduce(0) { $0 + $1.value }, 0.0001)
        var accumulated: Double = 0
        var result: [Arc] = []
        for segment in segments where segment.value > 0 {
            let start = accumulated / total
            accumulated += segment.value
            let end = accumulated / total
            result.append(Arc(start: CGFloat(start), end: CGFloat(end), color: segment.color))
        }
        return result
    }
}

#Preview("Donut") {
    let segments: [DonutChart.Segment] = [
        DonutChart.Segment(value: 86, color: .accentPrimary),
        DonutChart.Segment(value: 64, color: Color(hex: 0x7A746E)),
        DonutChart.Segment(value: 48, color: Color(hex: 0xE0A458)),
        DonutChart.Segment(value: 72, color: Color(hex: 0xB5705A)),
        DonutChart.Segment(value: 42, color: Color(hex: 0xC4BDB4)),
        DonutChart.Segment(value: 200, color: Color(hex: 0xECE7E1)),
    ]
    DonutChart(segments: segments, thickness: 30)
        .frame(width: 200, height: 200)
        .padding(40)
}
