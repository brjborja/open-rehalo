import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Widget extension hosting ONLY the navigation Live Activity (no home-screen widget in the MVP).
@main
struct HaloLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        HaloNavLiveActivity()
    }
}

/// Navigation Live Activity / Dynamic Island (UX_DESIGN §4.8). The app pushes pre-formatted
/// content (`HaloNavAttributes.ContentState`); this only lays it out.
struct HaloNavLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HaloNavAttributes.self) { context in
            LockScreenView(routeName: context.attributes.routeName, state: context.state)
                .activityBackgroundTint(LA.lockBackground)
                .activitySystemActionForegroundColor(LA.text)
                .environment(\.colorScheme, .dark)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TurnIcon(state: s, side: 48)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LightButton(state: s, side: 48, filledWhenOn: false)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    TurnText(state: s, distanceSize: 30, instructionSize: 14)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedFooter(state: s)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: s.symbol)
                        .font(.system(size: 14, weight: .heavy))
                    if !s.distance.isEmpty {
                        Text(s.distance)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(LA.tint(s))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(s.instruction))
                .accessibilityValue(Text(verbatim: s.distance))
            } compactTrailing: {
                Text(verbatim: "\(s.percent) %")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LA.text)
                    .accessibilityLabel(Text("Route progress"))
                    .accessibilityValue(Text(verbatim: "\(s.percent) %"))
            } minimal: {
                Image(systemName: s.symbol)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LA.tint(s))
                    .accessibilityLabel(Text(s.instruction))
            }
            .keylineTint(LA.accent)
        }
    }
}

// MARK: - Palette (mirrors the app's Theme, docs/UX_DESIGN.md §6)

enum LA {
    static let accent = Color(laHex: 0xC6FF3D)
    static let onAccent = Color(laHex: 0x0B0D10)
    static let text = Color(laHex: 0xF2F4F7)
    static let textSoft = Color(laHex: 0xC9CFD8)
    static let textDim = Color(laHex: 0xA9B0BA)
    static let surface2 = Color(laHex: 0x1F242B)
    static let stroke = Color(laHex: 0x2A3038)
    static let warn = Color(laHex: 0xFFB020)
    static let lockBackground = Color(laHex: 0x1E2229).opacity(0.92)

    /// Accent for the manoeuvre (warn while off-route).
    static func tint(_ s: HaloNavAttributes.ContentState) -> Color { s.offRoute ? warn : accent }

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

private extension Color {
    init(laHex hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Pieces

/// Accent (warn when off-route) rounded square with the manoeuvre symbol.
struct TurnIcon: View {
    let state: HaloNavAttributes.ContentState
    let side: CGFloat

    var body: some View {
        Image(systemName: state.symbol)
            .font(.system(size: side * 0.6, weight: .semibold))
            .foregroundStyle(LA.onAccent)
            .frame(width: side, height: side)
            .background(LA.tint(state), in: RoundedRectangle(cornerRadius: side * 0.29, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Big distance + instruction.
struct TurnText: View {
    let state: HaloNavAttributes.ContentState
    let distanceSize: CGFloat
    let instructionSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !state.distance.isEmpty {
                Text(state.distance)
                    .font(LA.rounded(distanceSize))
                    .foregroundStyle(state.offRoute ? LA.warn : LA.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
            }
            Text(state.instruction)
                .font(.system(size: instructionSize, weight: .semibold))
                .foregroundStyle(state.offRoute ? LA.warn : LA.textSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(state.instruction))
        .accessibilityValue(Text(verbatim: state.distance))
    }
}

/// Front-light toggle (a `LiveActivityIntent`, runs in the app). Inert without a Halo / after the ride.
struct LightButton: View {
    let state: HaloNavAttributes.ContentState
    let side: CGFloat
    /// Lock Screen style: solid accent when on. Dynamic Island: always the raised surface.
    let filledWhenOn: Bool

    private var active: Bool { state.haloConnected && !state.ended }

    var body: some View {
        if active {
            Button(intent: ToggleHaloLightIntent()) { glyph }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Front light"))
                .accessibilityValue(state.lightOn ? Text("On") : Text("Off"))
                .accessibilityAddTraits(state.lightOn ? [.isSelected] : [])
        } else {
            glyph
                .opacity(0.4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Front light"))
                .accessibilityValue(Text("Halo not connected"))
        }
    }

    private var filled: Bool { filledWhenOn && state.lightOn && active }

    private var glyph: some View {
        Image(systemName: state.lightOn ? "lightbulb.fill" : "lightbulb")
            .font(.system(size: side * 0.46, weight: .semibold))
            .foregroundStyle(filled ? LA.onAccent : (state.lightOn ? LA.accent : LA.textSoft))
            .frame(width: side, height: side)
            .background(filled ? LA.accent : LA.surface2, in: Circle())
    }
}

/// Thin progress bar (stroke track, accent fill).
struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(LA.stroke)
                Capsule().fill(LA.accent)
                    .frame(width: max(6, g.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel(Text("Route progress"))
        .accessibilityValue(Text(verbatim: "\(Int((min(1, max(0, progress)) * 100).rounded(.down))) %"))
    }
}

/// Dynamic Island expanded footer: "24,5 km/h · 5,4 km remaining · 43 %" + progress bar.
struct ExpandedFooter: View {
    let state: HaloNavAttributes.ContentState

    var body: some View {
        let distance = "\(state.distanceValue) \(state.distanceUnit)"
        VStack(spacing: 10) {
            HStack {
                Text(verbatim: "\(state.speedValue) \(state.speedUnit)")
                Spacer(minLength: 4)
                Group {
                    if state.ended { Text("\(distance) ridden") } else { Text("\(distance) remaining") }
                }
                Spacer(minLength: 4)
                Text(verbatim: "\(state.percent) %").foregroundStyle(LA.accent)
            }
            .font(.system(size: 14, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(LA.textSoft)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)
            ProgressBar(progress: state.progress)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}

/// Small value-over-label metric (Lock Screen).
struct LockMetric: View {
    let value: String
    let label: Text
    var tint: Color = LA.text

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: value)
                .font(LA.rounded(22))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            label
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LA.textDim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Lock Screen / banner

struct LockScreenView: View {
    let routeName: String
    let state: HaloNavAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 14) {
                TurnIcon(state: state, side: 56)
                TurnText(state: state, distanceSize: 34, instructionSize: 15)
                if !state.ended {
                    LightButton(state: state, side: 52, filledWhenOn: true)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                LockMetric(value: state.speedValue,
                           label: state.ended ? Text("\(state.speedUnit) average") : Text(verbatim: state.speedUnit))
                LockMetric(value: state.distanceValue,
                           label: state.ended ? Text("\(state.distanceUnit) ridden")
                                              : Text("\(state.distanceUnit) remaining"))
                LockMetric(value: "\(state.percent) %", label: Text("done"), tint: LA.accent)
            }
            ProgressBar(progress: state.progress)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(LA.accent)
                .accessibilityHidden(true)
            Text(verbatim: "Halo · \(routeName)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(LA.textSoft)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Circle()
                    .fill(state.haloConnected ? LA.accent : LA.textDim)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Group {
                    if state.haloConnected { Text("Connected") } else { Text("Halo not connected") }
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(state.haloConnected ? LA.accent : LA.textDim)
                .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
