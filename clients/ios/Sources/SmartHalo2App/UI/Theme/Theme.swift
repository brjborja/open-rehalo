import SwiftUI

/// Halo visual system (docs/UX_DESIGN.md §6): sporty dark theme, always dark, high contrast.
///
/// Colors are plain `Color`s on `Theme` (`Theme.accent`) and are also reachable as `ShapeStyle`s
/// (`.foregroundStyle(.haloAccent)`). Shapes: cards 20 pt, buttons 14 pt, 1 px `stroke` borders and
/// no shadows. Metrics use SF Pro Rounded with monospaced digits.
enum Theme {
    // MARK: Color tokens
    static let bg       = Color(hex: 0x0B0D10)   // background
    static let surface  = Color(hex: 0x15181D)   // cards, panels
    static let surface2 = Color(hex: 0x1F242B)   // raised elements, sheets
    static let stroke   = Color(hex: 0x2A3038)   // 1 px borders
    static let text     = Color(hex: 0xF2F4F7)   // primary text
    static let textDim  = Color(hex: 0x8A93A0)   // secondary text
    static let accent   = Color(hex: 0xC6FF3D)   // CTA, route, connected, light on
    static let onAccent = Color(hex: 0x0B0D10)   // text on accent
    static let warn     = Color(hex: 0xFFB020)   // off-route, reconnecting, recovery
    static let danger   = Color(hex: 0xFF4D4F)   // alarm triggered, destructive
    static let info     = Color(hex: 0x3DD6FF)   // user position, links, DEMO badge

    // MARK: Shape
    enum Radius {
        static let card: CGFloat = 20
        static let button: CGFloat = 14
        static let chip: CGFloat = 20
    }

    /// Spacing scale.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    /// Minimum hit target (56 pt while riding).
    static let minTarget: CGFloat = 44
    static let minTargetRiding: CGFloat = 56

    // MARK: Typography

    /// Metric font: SF Pro Rounded + monospaced digits. Pass a size already scaled for Dynamic Type
    /// (e.g. via `@ScaledMetric`) — `MetricView` does that for you.
    static func metricFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    /// Text-style based rounded font that scales with Dynamic Type automatically.
    static func metricFont(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded, weight: weight).monospacedDigit()
    }
}

extension Font {
    /// Shorthand for `Theme.metricFont(size:weight:)`.
    static func metric(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        Theme.metricFont(size: size, weight: weight)
    }
}

// MARK: - ShapeStyle access

extension ShapeStyle where Self == Color {
    static var haloBg: Color { Theme.bg }
    static var haloSurface: Color { Theme.surface }
    static var haloSurface2: Color { Theme.surface2 }
    static var haloStroke: Color { Theme.stroke }
    static var haloText: Color { Theme.text }
    static var haloTextDim: Color { Theme.textDim }
    static var haloAccent: Color { Theme.accent }
    static var haloOnAccent: Color { Theme.onAccent }
    static var haloWarn: Color { Theme.warn }
    static var haloDanger: Color { Theme.danger }
    static var haloInfo: Color { Theme.info }
}

extension Color {
    /// `Color(hex: 0xRRGGBB)` in sRGB.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - View helpers

extension View {
    /// Card surface: `surface` fill, 20 pt continuous corners, 1 px `stroke`, no shadow.
    func haloCard(padding: CGFloat = Theme.Space.l,
                  fill: Color = Theme.surface,
                  stroke: Color = Theme.stroke) -> some View {
        self
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
    }

    /// Full-screen themed background (behind safe areas).
    func haloScreenBackground() -> some View {
        background(Theme.bg.ignoresSafeArea())
    }

    /// App-wide theme: always dark + accent tint. Apply once at the root.
    func haloTheme() -> some View {
        self
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
    }
}
