import SwiftUI

/// The Halo tab's live ring: the device's 24 LED segments drawn in the Spark style, mirroring what
/// the app knows about the ring. Light on → brighter with a glow (flashing when blinking); alarm
/// armed → the spark blinks slowly; triggered → the ring flashes red; connecting → the boot-sweep
/// head laps the dim ring; offline → the dim dead ring. `card` previews a carousel card the way
/// the Halo draws it (clock hands, battery level, speed gauge…). Stepped at 30 fps like the launch
/// motion; Reduce Motion shows each state still.
struct RingMirror: View {
    let state: HaloConnectionState
    var lightOn = false
    /// 0…1.
    var brightness: Double = 0.5
    var blinking = false
    var armed = false
    var triggered = false
    /// A carousel card being shown on the Halo right now (connected only).
    var card: RingCard? = nil
    var batteryLevel: Int? = nil
    var charging = false
    var size: CGFloat = 196

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !isAnimated)) { context in
            let ms = context.date.timeIntervalSinceReferenceDate * 1000
            Canvas { gc, canvasSize in
                draw(in: &gc, size: canvasSize, t: reduceMotion ? 0 : ms)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityText))
    }

    private var isAnimated: Bool {
        switch state {
        case .connecting: return true
        case .connected: return card != nil || triggered || armed || (lightOn && blinking)
        case .disconnected, .needsRecovery: return false
        }
    }

    private var accessibilityText: LocalizedStringKey {
        switch state {
        case .connecting: return "Ring: connecting"
        case .disconnected: return "Ring: offline"
        case .needsRecovery: return "Ring: needs re-pairing"
        case .connected:
            if card != nil { return "Ring: showing a card" }
            if triggered { return "Ring: alarm triggered" }
            if armed { return lightOn ? "Ring: light on, alarm armed" : "Ring: alarm armed" }
            return lightOn ? "Ring: light on" : "Ring: light off"
        }
    }

    /// A card the way the Halo draws it on its 24 LEDs (`RideTask.c` / `AnimationsLibrary.c`).
    private func drawCard(_ card: RingCard, into segments: inout [(color: Color, opacity: Double)], t: Double) {
        for i in 0..<24 { segments[i] = (Theme.text, 0.1) }
        func lit(_ i: Int, _ color: Color, _ opacity: Double = 1) { segments[((i % 24) + 24) % 24] = (color, opacity) }
        switch card {
        case .battery:
            let level = batteryLevel ?? 0
            let n = Int((Double(level) / 100 * 24).rounded())
            let color = level <= 20 ? Theme.danger : Theme.accent
            let flash = level <= 10 && !reduceMotion && Int(t / 400) % 2 == 1
            for i in 0..<n { lit(i, color, flash ? 0.3 : 1) }
            if charging && n < 24 && !reduceMotion { lit(n + Int(t / 120) % (24 - n), Theme.accent, 0.5) }
        case .clock:
            let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
            let m = Double(c.minute ?? 0)
            lit(Int((m / 2.5).rounded()), Theme.text)
            lit(Int(((Double((c.hour ?? 0) % 12) + m / 60) * 2).rounded()), Theme.accent)
        case .speed, .avgSpeed:
            let pct = reduceMotion ? 0.45 : 0.45 + 0.08 * sin(t / 900)
            for k in 0..<17 { lit(16 + k, Theme.text, k < Int((pct * 17).rounded()) ? (card == .avgSpeed ? 0.55 : 1) : 0.1) }
            if card == .avgSpeed { lit(24, Theme.accent) }
        case .distance:
            let k = 12 + (reduceMotion ? 0 : Int(t / 500) % 24)
            lit(k, Theme.accent); lit(k - 1, Theme.accent, 0.4)
        case .time:
            lit(Int(t / 1000).quotientAndRemainder(dividingBy: 60).remainder * 2 / 5, Theme.text)
            lit(0, Theme.accent, 0.6)
        }
    }

    /// Segment slots that make the ring (15° each, from 12 o'clock clockwise); 1–4 are the gap.
    private static let ring = Array(5...23) + [0]

    private func draw(in gc: inout GraphicsContext, size: CGSize, t: Double) {
        var segments = Array(repeating: (color: Theme.text, opacity: 0.0), count: 24)
        var spark: (color: Color, opacity: Double)? = nil
        var glow: CGFloat = 0
        let phase = { (period: Double) in Int(t / period) % 2 == 0 }

        switch state {
        case .disconnected:
            for i in 0..<24 { segments[i] = (Theme.text, 0.14) }
        case .needsRecovery:
            for i in 0..<24 { segments[i] = (Theme.text, 0.14) }
            spark = (Theme.warn, 1)
        case .connecting:
            for i in 0..<24 { segments[i] = (Theme.text, 0.14) }
            if !reduceMotion {
                let k = (5 + Int(t / 40)) % 24
                segments[k] = (Theme.accent, 1)
                segments[(k + 23) % 24] = (Theme.accent, 0.5)
                segments[(k + 22) % 24] = (Theme.accent, 0.2)
            }
        case .connected where card != nil:
            drawCard(card!, into: &segments, t: t)
        case .connected:
            if triggered {
                let on = reduceMotion || phase(250)
                for i in 0..<24 { segments[i] = (Theme.danger, on ? 1 : 0.25) }
            } else {
                let blinkOff = lightOn && blinking && !reduceMotion && !phase(500)
                let level = lightOn ? (blinkOff ? 0.2 : 0.4 + 0.6 * brightness) : 0.72
                for i in Self.ring { segments[i] = (Theme.text, level) }
                glow = lightOn && !blinkOff ? 4 + 14 * brightness : 0
                spark = (Theme.accent, armed && !reduceMotion && !phase(700) ? 0.2 : 1)
            }
        }

        // The design's 200-unit box, inset so a full glow still fits the frame.
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let unit = min(size.width, size.height) / 200
        func arc(from: Double, to: Double) -> Path {
            Path { p in
                p.addArc(center: center, radius: 70 * unit, startAngle: .degrees(from - 90),
                         endAngle: .degrees(to - 90), clockwise: false)
            }
        }
        var layer = gc
        if glow > 0 { layer.addFilter(.shadow(color: Theme.text.opacity(0.55), radius: glow * unit)) }
        for (i, seg) in segments.enumerated() where seg.opacity > 0 {
            let a = Double(i) * 15
            layer.stroke(arc(from: a + 1.5, to: a + 13.5), with: .color(seg.color.opacity(seg.opacity)),
                         style: StrokeStyle(lineWidth: 26 * unit, lineCap: .butt))
        }
        if let spark {
            let d = 70 * unit * 0.5.squareRoot()                           // 45°, on the ring
            let r = 15 * unit
            gc.fill(Path(ellipseIn: CGRect(x: center.x + d - r, y: center.y - d - r, width: 2 * r, height: 2 * r)),
                    with: .color(spark.color.opacity(spark.opacity)))
        }
    }
}

#Preview {
    HStack {
        RingMirror(state: .connected, lightOn: true, brightness: 0.8, size: 120)
        RingMirror(state: .connecting, size: 120)
    }
    .padding()
    .background(Theme.bg)
}
