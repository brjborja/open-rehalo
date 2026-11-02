import SwiftUI

/// Button look of the Halo system: `.primary` = neon accent fill (CTA), `.secondary` = surface2 with
/// a 1 px stroke, `.destructive` = danger fill. Radius 14 pt, min height 52 pt (56 pt with
/// `riding: true`). Usable on any `Button` / `NavigationLink` / `ShareLink` via `.buttonStyle(…)`.
struct HaloButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }

    var kind: Kind = .primary
    var riding: Bool = false
    var fullWidth: Bool = true

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, Theme.Space.xl)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: riding ? Theme.minTargetRiding : 52)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(kind == .secondary ? Theme.stroke : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var background: Color {
        switch kind {
        case .primary: return Theme.accent
        case .secondary: return Theme.surface2
        case .destructive: return Theme.danger
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Theme.onAccent
        case .secondary: return Theme.text
        case .destructive: return Theme.text
        }
    }
}

extension ButtonStyle where Self == HaloButtonStyle {
    /// `.buttonStyle(.haloPrimary)`
    static var haloPrimary: HaloButtonStyle { HaloButtonStyle(kind: .primary) }
    /// `.buttonStyle(.haloSecondary)`
    static var haloSecondary: HaloButtonStyle { HaloButtonStyle(kind: .secondary) }
    /// `.buttonStyle(.haloDestructive)`
    static var haloDestructive: HaloButtonStyle { HaloButtonStyle(kind: .destructive) }
}

/// Convenience full-width button with an optional SF Symbol.
///
///     PrimaryButton("Navigate", systemImage: "play.fill") { start() }
///     PrimaryButton("Not now", kind: .secondary) { skip() }
struct PrimaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var kind: HaloButtonStyle.Kind = .primary
    var riding: Bool = false
    let action: () -> Void

    init(_ title: LocalizedStringKey,
         systemImage: String? = nil,
         kind: HaloButtonStyle.Kind = .primary,
         riding: Bool = false,
         action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.riding = riding
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
            } else {
                Text(title)
            }
        }
        .buttonStyle(HaloButtonStyle(kind: kind, riding: riding))
    }
}

#Preview("Buttons") {
    VStack(spacing: 12) {
        PrimaryButton("Navigate", systemImage: "play.fill") {}
        PrimaryButton("Change", kind: .secondary) {}
        PrimaryButton("Stop", systemImage: "stop.fill", kind: .destructive, riding: true) {}
        PrimaryButton("Disabled") {}.disabled(true)
    }
    .padding()
    .frame(maxHeight: .infinity)
    .haloScreenBackground()
    .haloTheme()
}
