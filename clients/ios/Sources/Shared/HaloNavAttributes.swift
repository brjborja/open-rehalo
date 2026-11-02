import Foundation
import ActivityKit

/// Live Activity model for navigation (UX_DESIGN §4.8), compiled into BOTH the app and the
/// `HaloLiveActivity` widget extension (`Sources/Shared/`).
///
/// The app formats everything (units, locale, instruction text) so the extension only lays it out:
/// it has no access to `UnitFormat`, `TurnKind` or the app's String Catalog keys for manoeuvres.
struct HaloNavAttributes: ActivityAttributes {
    /// Dynamic part, pushed by `LiveActivityManager` (throttled: turn change, ~50 m and ≥10 s,
    /// off-route / Halo / light changes).
    struct ContentState: Codable, Hashable {
        /// `TurnKind.rawValue` (`offRoute` while off-route, `arrival` at the end).
        var turn: String
        /// SF Symbol for the manoeuvre (`TurnKind.systemImage`).
        var symbol: String
        /// Formatted distance to the manoeuvre ("350 m"); empty hides it.
        var distance: String
        /// Localized instruction ("Turn left", "Back to the route", "You have arrived").
        var instruction: String
        /// Speed (current while riding, average once ended), value and unit apart ("24,5" / "km/h").
        var speedValue: String
        var speedUnit: String
        /// Remaining distance while riding, distance ridden once ended ("5,4" / "km").
        var distanceValue: String
        var distanceUnit: String
        /// Route progress 0…1.
        var progress: Double
        var offRoute: Bool
        var haloConnected: Bool
        var lightOn: Bool
        /// Final state (arrived or stopped) shown for a few minutes before dismissal.
        var ended: Bool

        var percent: Int { Int((min(1, max(0, progress)) * 100).rounded(.down)) }
        var isArrival: Bool { turn == "arrival" }
    }

    /// Route name, fixed for the activity's lifetime.
    var routeName: String
}
