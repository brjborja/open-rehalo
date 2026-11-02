import SwiftUI
import Charts

/// Elevation profile of a route (Swift Charts `AreaMark` + `LineMark` in accent). Only meaningful
/// when `route.hasElevation`; the caller hides it otherwise. X = distance (km / mi), Y = elevation
/// (m / ft), following the units setting.
struct ElevationProfileView: View {
    let route: GPXRoute
    let fmt: UnitFormat

    struct Sample: Identifiable {
        let id: Int
        let x: Double
        let y: Double
    }

    private var metric: Bool { fmt.units == .metric }

    /// ≤ ~200 samples with elevation, evenly spread along the route.
    private var samples: [Sample] {
        let n = route.points.count
        guard n > 1 else { return [] }
        let stride = max(1, n / 200)
        let xDiv = metric ? 1000.0 : 1609.344
        let yMul = metric ? 1.0 : 3.280_84
        var out: [Sample] = []
        var i = 0
        while i < n {
            if let e = route.elevations[i] {
                out.append(Sample(id: i, x: route.cumulative[i] / xDiv, y: e * yMul))
            }
            if i == n - 1 { break }
            i = min(n - 1, i + stride)
        }
        return out
    }

    var body: some View {
        let data = samples
        let lo = data.map(\.y).min() ?? 0
        let hi = data.map(\.y).max() ?? 1
        let pad = max(metric ? 5 : 15, (hi - lo) * 0.15)
        let floorY = lo - pad
        let topY = hi + pad
        let maxX = max(data.last?.x ?? 1, 0.1)

        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text("Elevation profile")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textDim)
                    .textCase(.uppercase)
                Spacer()
                Text(verbatim: metric ? "km · m" : "mi · ft")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textDim)
            }
            Chart(data) { p in
                AreaMark(x: .value("Distance", p.x),
                         yStart: .value("Elevation", floorY),
                         yEnd: .value("Elevation", p.y))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.03)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Distance", p.x), y: .value("Elevation", p.y))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            .chartXScale(domain: 0...maxX)
            .chartYScale(domain: floorY...topY)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel().foregroundStyle(Theme.textDim)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel().foregroundStyle(Theme.textDim)
                }
            }
            .frame(height: 130)
            .accessibilityLabel(Text("Elevation profile"))
            .accessibilityValue(Text(verbatim: "\(fmt.elevation(lo / (metric ? 1 : 3.280_84))) – \(fmt.elevation(hi / (metric ? 1 : 3.280_84)))"))
        }
    }
}
