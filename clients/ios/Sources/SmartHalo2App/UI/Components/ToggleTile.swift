import SwiftUI

/// Big square device-control tile (Halo tab: Light, Alarm). A tap toggles; when on, the whole tile
/// fills with `tint` (accent, or `Theme.danger` for a triggered alarm). An optional secondary button
/// (e.g. brightness & mode) sits top-trailing and never triggers the tile's own action.
///
///     ToggleTile(title: "Light", systemImage: "lightbulb", state: "On", isOn: true) { toggle() }
///
/// When `isEnabled` is false the tile is dimmed and shows `disabledNote` (e.g. "Reconnect to use").
struct ToggleTile: View {
    struct Secondary {
        let systemImage: String
        let label: LocalizedStringKey
        let action: () -> Void
    }

    let title: LocalizedStringKey
    let systemImage: String
    var state: LocalizedStringKey? = nil
    var detail: String? = nil
    var isOn = false
    var tint: Color = Theme.accent
    var isEnabled = true
    var disabledNote: LocalizedStringKey? = nil
    var secondary: Secondary? = nil
    let action: () -> Void

    private var foreground: Color { isOn ? Theme.onAccent : Theme.text }
    private var dim: Color { isOn ? Theme.onAccent.opacity(0.72) : Theme.textDim }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(isOn ? Theme.onAccent.opacity(0.12) : Theme.surface2, in: Circle())
                Spacer(minLength: Theme.Space.m)
                Text(title)
                    .font(.headline.weight(.bold))
                if !isEnabled, let disabledNote {
                    Text(disabledNote).font(.subheadline).foregroundStyle(Theme.textDim)
                } else {
                    if let state {
                        Text(state).font(.subheadline.weight(.semibold))
                    }
                    if let detail {
                        Text(verbatim: detail).font(.footnote).foregroundStyle(dim).lineLimit(1)
                    }
                }
            }
            .foregroundStyle(foreground)
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
            .background(isOn ? tint : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(isOn ? tint : Theme.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .overlay(alignment: .topTrailing) {
            if let secondary {
                Button(action: secondary.action) {
                    Image(systemName: secondary.systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(foreground)
                        .frame(width: Theme.minTarget, height: Theme.minTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(Theme.Space.s)
                .disabled(!isEnabled)
                .accessibilityLabel(Text(secondary.label))
            }
        }
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// Full-width device-control row (Halo tab › Controls: Light, Alarm): a big target that toggles,
/// filled with `tint` when on, with an optional trailing secondary button.
struct ToggleRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    var detail: String? = nil
    var isOn = false
    var tint: Color = Theme.accent
    var isEnabled = true
    var isBusy = false
    var secondary: ToggleTile.Secondary? = nil
    let action: () -> Void

    private var foreground: Color { isOn ? Theme.onAccent : Theme.text }
    private var dim: Color { isOn ? Theme.onAccent.opacity(0.72) : Theme.textDim }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.l) {
                ZStack {
                    if isBusy {
                        ProgressView().tint(foreground)
                    } else {
                        Image(systemName: systemImage).font(.title3.weight(.semibold))
                    }
                }
                .frame(width: 48, height: 48)
                .background(isOn ? Theme.onAccent.opacity(0.12) : Theme.surface2, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title3.weight(.bold))
                    if let detail {
                        Text(verbatim: detail).font(.footnote).foregroundStyle(dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: secondary == nil ? 0 : Theme.minTarget + Theme.Space.s)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(isOn ? tint : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(isOn ? tint : Theme.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled || isBusy)
        .opacity(isEnabled ? 1 : 0.45)
        .overlay(alignment: .trailing) {
            if let secondary {
                Button(action: secondary.action) {
                    Image(systemName: secondary.systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(foreground)
                        .frame(width: Theme.minTarget, height: Theme.minTarget)
                        .background(isOn ? Theme.onAccent.opacity(0.12) : Theme.surface2, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, Theme.Space.m)
                .disabled(!isEnabled || isBusy)
                .accessibilityLabel(Text(secondary.label))
            }
        }
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// Subtle press feedback for custom tappable surfaces (scale, respects Reduce Motion).
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview("ToggleTile") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        ToggleTile(title: "Light", systemImage: "lightbulb.fill", state: "On", detail: "50% · Steady", isOn: true,
                   secondary: .init(systemImage: "slider.horizontal.3", label: "Brightness and mode", action: {})) {}
        ToggleTile(title: "Alarm", systemImage: "lock.open", state: "Disarmed", detail: "Tap to arm") {}
        ToggleTile(title: "Alarm", systemImage: "bell.and.waves.left.and.right.fill", state: "Motion!",
                   isOn: true, tint: Theme.danger) {}
        ToggleTile(title: "Light", systemImage: "lightbulb", isEnabled: false,
                   disabledNote: "Reconnect to use") {}
    }
    .padding()
    .frame(maxHeight: .infinity)
    .haloScreenBackground()
    .haloTheme()
}
