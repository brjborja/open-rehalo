import SwiftUI

/// Global connection chip (UX_DESIGN §3): `● Halo` (accent) · `◌ Connecting…` (warn, pulsing) ·
/// `○ No Halo` (dim) · `⚠ Re-pair` (warn). Color is never the only cue: each state has its own
/// label and glyph. What a tap does is up to the caller (see `HaloChrome`). `compact` is the round
/// version floating on the map: no label, but still a different glyph per state.
struct StatusChip: View {
    let state: HaloConnectionState
    var compact = false
    var action: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            if compact {
                compactGlyph
                    .frame(width: Theme.minTarget, height: Theme.minTarget)
                    .background(Theme.surface.opacity(0.94), in: Circle())
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
                    .contentShape(Circle())
            } else {
                HStack(spacing: 8) {
                    indicator
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                }
                .foregroundStyle(color)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Theme.surface.opacity(0.92), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                .contentShape(Capsule())
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: Theme.minTarget)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityHint(Text(hint))
        .onAppear { updatePulse() }
        .onChange(of: state) { _, _ in updatePulse() }
        .sensoryFeedback(.success, trigger: state) { _, new in new == .connected }
    }

    @ViewBuilder private var indicator: some View {
        switch state {
        case .needsRecovery:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
        case .disconnected:
            Circle().strokeBorder(color, lineWidth: 1.5).frame(width: 9, height: 9)
        case .connected, .connecting:
            Circle().fill(color).frame(width: 9, height: 9)
                .opacity(state == .connecting && pulse ? 0.25 : 1)
                .animation(state == .connecting && !reduceMotion
                           ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                           : .default,
                           value: pulse)
        }
    }

    /// A ring like the Halo's: solid centre when linked or linking, empty when not.
    @ViewBuilder private var compactGlyph: some View {
        switch state {
        case .needsRecovery:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
        case .disconnected:
            Circle().strokeBorder(color, lineWidth: 2.5).frame(width: 22, height: 22)
        case .connected, .connecting:
            ZStack {
                Circle().strokeBorder(color, lineWidth: 2.5).frame(width: 22, height: 22)
                Circle().fill(color).frame(width: 9, height: 9)
            }
            .opacity(state == .connecting && pulse ? 0.25 : 1)
            .animation(state == .connecting && !reduceMotion
                       ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                       : .default,
                       value: pulse)
        }
    }

    private func updatePulse() {
        pulse = state == .connecting && !reduceMotion
    }

    private var title: LocalizedStringKey {
        switch state {
        case .connected: return "Halo"
        case .connecting: return "Connecting…"
        case .disconnected: return "No Halo"
        case .needsRecovery: return "Re-pair"
        }
    }

    private var accessibilityText: LocalizedStringKey {
        switch state {
        case .connected: return "Halo connected"
        case .connecting: return "Connecting to Halo"
        case .disconnected: return "Halo not connected"
        case .needsRecovery: return "Halo needs re-pairing"
        }
    }

    private var hint: LocalizedStringKey {
        switch state {
        case .connected, .connecting: return "Opens the Halo tab"
        case .disconnected: return "Tries to connect again"
        case .needsRecovery: return "Opens the recovery steps"
        }
    }

    private var color: Color {
        switch state {
        case .connected: return Theme.accent
        case .connecting, .needsRecovery: return Theme.warn
        case .disconnected: return Theme.textDim
        }
    }
}

/// Persistent "DEMO" badge shown while the simulated ring is active.
struct DemoBadge: View {
    var body: some View {
        Text("DEMO · no real Halo")
            .font(.caption2.weight(.heavy))
            .tracking(0.8)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 10)
            .frame(minHeight: 22)
            .background(Theme.info, in: Capsule())
            .accessibilityLabel(Text("Demo mode: simulated Halo"))
    }
}

#Preview("StatusChip") {
    VStack(spacing: 16) {
        StatusChip(state: .connected)
        StatusChip(state: .connecting)
        StatusChip(state: .disconnected)
        StatusChip(state: .needsRecovery)
        HStack {
            StatusChip(state: .connected, compact: true)
            StatusChip(state: .connecting, compact: true)
            StatusChip(state: .disconnected, compact: true)
            StatusChip(state: .needsRecovery, compact: true)
        }
        DemoBadge()
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .haloScreenBackground()
    .haloTheme()
}
