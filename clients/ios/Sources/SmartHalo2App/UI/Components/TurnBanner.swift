import SwiftUI
import SH2Protocol

/// How a `TurnBanner` shows each manoeuvre (`TurnKind` comes from the route's geometry).
extension TurnKind {
    var systemImage: String {
        switch self {
        case .straight: return "arrow.up"
        case .slightLeft: return "arrow.up.left"
        case .left: return "arrow.turn.up.left"
        case .sharpLeft: return "arrow.turn.left.down"
        case .slightRight: return "arrow.up.right"
        case .right: return "arrow.turn.up.right"
        case .sharpRight: return "arrow.turn.right.down"
        case .uTurn: return "arrow.uturn.down"
        case .roundabout: return "arrow.triangle.turn.up.right.circle"
        case .arrival: return "flag.checkered"
        case .offRoute: return "arrow.uturn.backward"
        }
    }

    /// Default instruction text (ES/EN in the String Catalog).
    var instruction: LocalizedStringKey {
        switch self {
        case .straight: return "Continue straight"
        case .slightLeft: return "Bear left"
        case .left: return "Turn left"
        case .sharpLeft: return "Sharp left"
        case .slightRight: return "Bear right"
        case .right: return "Turn right"
        case .sharpRight: return "Sharp right"
        case .uTurn: return "Make a U-turn"
        case .roundabout: return "At the roundabout"
        case .arrival: return "You have arrived"
        case .offRoute: return "Back to the route"
        }
    }

    /// Same instruction as a plain localized `String` (Live Activity content state).
    var instructionText: String {
        switch self {
        case .straight: return String(localized: "Continue straight")
        case .slightLeft: return String(localized: "Bear left")
        case .left: return String(localized: "Turn left")
        case .sharpLeft: return String(localized: "Sharp left")
        case .slightRight: return String(localized: "Bear right")
        case .right: return String(localized: "Turn right")
        case .sharpRight: return String(localized: "Sharp right")
        case .uTurn: return String(localized: "Make a U-turn")
        case .roundabout: return String(localized: "At the roundabout")
        case .arrival: return String(localized: "You have arrived")
        case .offRoute: return String(localized: "Back to the route")
        }
    }
}

/// Next-manoeuvre panel for the Navigating screen: icon + big distance + instruction. `.offRoute`
/// switches the whole banner to the warn color ("Back to the route · 120 m").
///
///     TurnBanner(kind: .left, distance: fmt.distance(350))
///     TurnBanner(kind: .roundabout, distance: "120 m", instruction: "Take the 2nd exit")
///     TurnBanner(kind: .offRoute, distance: "120 m", iconRotation: .degrees(bearingDelta))
struct TurnBanner: View {
    let kind: TurnKind
    /// Pre-formatted distance (see `UnitFormat`). Empty hides it (e.g. on arrival).
    var distance: String = ""
    /// Overrides `kind.instruction` (already-localized text, e.g. a street name).
    var instruction: String? = nil
    /// Makes the icon an arrow aimed this way (e.g. at the route, when off-route).
    var iconRotation: Angle? = nil

    @ScaledMetric(relativeTo: .largeTitle) private var distanceSize: CGFloat = 48

    private var accent: Color {
        switch kind {
        case .offRoute: return Theme.warn
        case .arrival: return Theme.accent
        default: return Theme.text
        }
    }

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            Image(systemName: iconRotation == nil ? kind.systemImage : "arrow.up")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .rotationEffect(iconRotation ?? .zero)
                .frame(width: 64, height: 64)
                .background(kind == .offRoute ? Theme.warn : Theme.accent,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                if !distance.isEmpty {
                    Text(distance)
                        .font(Theme.metricFont(size: distanceSize))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                }
                Group {
                    if let instruction { Text(instruction) } else { Text(kind.instruction) }
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(kind == .offRoute ? Theme.warn : Theme.textDim)
                .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .haloCard(fill: Theme.surface.opacity(0.96),
                  stroke: kind == .offRoute ? Theme.warn.opacity(0.7) : Theme.stroke)
        .accessibilityElement(children: .combine)
    }
}

#Preview("TurnBanner") {
    VStack(spacing: 12) {
        TurnBanner(kind: .left, distance: "350 m")
        TurnBanner(kind: .roundabout, distance: "120 m", instruction: "Take the 2nd exit")
        TurnBanner(kind: .straight, distance: "2.4 km")
        TurnBanner(kind: .offRoute, distance: "120 m", iconRotation: .degrees(30))
        TurnBanner(kind: .arrival)
    }
    .padding()
    .frame(maxHeight: .infinity)
    .haloScreenBackground()
    .haloTheme()
}
