import SwiftUI

/// Launch motion "Boot sweep" (~1.2 s, drawn over the app on cold launch).
///
/// Picks up from the static launch screen (the dim dead ring, `LaunchRing` on `LaunchBackground`):
/// a lime head runs twice round the ring's 24 LED segments, laying the ring down on the second lap,
/// parks in the gap as the spark, snaps to the solid Spark mark, then the ring steps outward past the
/// screen edges with the app showing through its centre. Frames are stepped at 30 fps like real LEDs.
/// Reduce Motion skips it. Geometry matches `brand/tools/build_mark.py` (a 200-unit box, 150 pt wide).
struct LaunchSweepOverlay: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { context in
            let ms = start.map { context.date.timeIntervalSince($0) * 1000 } ?? 0
            Canvas { gc, size in
                LaunchSweep.draw(in: &gc, size: size, t: LaunchSweep.quantized(ms))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task {
            if reduceMotion { onFinished(); return }
            start = .now
            try? await Task.sleep(for: .milliseconds(Int(LaunchSweep.duration)))
            onFinished()
        }
    }
}

/// The boot-sweep timeline (milliseconds) and its drawing. Matches the "Boot sweep, refined" board.
enum LaunchSweep {
    static let duration = 1200.0
    private static let step = 1000.0 / 30
    private static let solidAt = 920.0
    private static let expandAt = 1000.0
    /// Segment slots that make the ring (15° each, from 12 o'clock clockwise); 1–4 are the gap.
    private static let ring = Array(5...23) + [0]
    /// Hand-off: the ring's scale, held until each time.
    private static let expand: [(until: Double, scale: CGFloat)] = [
        (1000, 1), (1033, 1.35), (1066, 1.9), (1100, 2.7), (1133, 3.9), (1166, 5.6), (1200, 8),
    ]

    static func quantized(_ ms: Double) -> Double { (ms / step).rounded(.down) * step }

    private struct Frame {
        var segments = Array(repeating: (color: Theme.text, opacity: 0.0), count: 24)
        var solid = false
        var spark = false
    }

    private static func frame(at t: Double) -> Frame {
        var f = Frame()
        if t >= solidAt {
            f.solid = true
            f.spark = true
            return f
        }
        if t < 850 {
            for i in 0..<24 { f.segments[i] = (Theme.text, 0.14) }       // the dead ring
        }
        if t < 450 {                                                   // lap 1: boot check
            let k = (5 + Int(t / 450 * 24)) % 24
            f.segments[k] = (Theme.accent, 1)
            f.segments[(k + 23) % 24] = (Theme.accent, 0.5)
            f.segments[(k + 22) % 24] = (Theme.accent, 0.2)
        } else if t < 850 {                                            // lap 2 lays the ring
            let order = ring + [1, 2]
            let pos = min(order.count - 1, Int((t - 450) / 400 * Double(order.count)))
            for j in 0..<pos where ring.contains(order[j]) { f.segments[order[j]] = (Theme.text, 1) }
            f.segments[order[pos]] = (Theme.accent, 1)
        } else {                                                       // parked as the spark
            for i in ring { f.segments[i] = (Theme.text, 1) }
            f.spark = true
        }
        return f
    }

    static func draw(in gc: inout GraphicsContext, size: CGSize, t: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let scale = expand.first { t < $0.until }?.scale ?? expand.last!.scale
        let unit = 150.0 / 200 * scale                                 // points per design unit

        // The ground; once the ring expands, its inside is a hole the app shows through.
        var ground = Path(CGRect(origin: .zero, size: size))
        if t >= expandAt {
            let r = 57 * unit
            ground.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        }
        gc.fill(ground, with: .color(Theme.bg), style: FillStyle(eoFill: true))

        // Angles are compass degrees: 0 = 12 o'clock, increasing clockwise.
        func arc(from: Double, to: Double) -> Path {
            Path { p in
                p.addArc(center: center, radius: 70 * unit, startAngle: .degrees(from - 90),
                         endAngle: .degrees(to - 90), clockwise: false)
            }
        }
        let stroke = 26 * unit
        let f = frame(at: t)
        if f.solid {
            gc.stroke(arc(from: 75, to: 375), with: .color(Theme.text),
                      style: StrokeStyle(lineWidth: stroke, lineCap: .round))
        } else {
            for (i, seg) in f.segments.enumerated() where seg.opacity > 0 {
                let a = Double(i) * 15
                gc.stroke(arc(from: a + 1.5, to: a + 13.5), with: .color(seg.color.opacity(seg.opacity)),
                          style: StrokeStyle(lineWidth: stroke, lineCap: .butt))
            }
        }
        if f.spark {
            let d = 70 * unit * 0.5.squareRoot()                         // 45°, on the ring
            let r = 15 * unit
            gc.fill(Path(ellipseIn: CGRect(x: center.x + d - r, y: center.y - d - r, width: 2 * r, height: 2 * r)),
                    with: .color(Theme.accent))
        }
    }
}
