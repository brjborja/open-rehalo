import Foundation

/// The rider's direction of travel, from successive GPS fixes only (the original never uses a
/// compass in GPX mode). Bearing part of `smarthalo::NavigationState`; 999 = unknown.
///
/// A sample is the bearing previous fix → new fix, kept when both fixes are better than 35 m and
/// more than 3.5 m apart (at 1 Hz: slower than ~12.6 km/h gives no samples). The current bearing is
/// the circular mean of 3 samples within 40° of each other; the crow-flies bearing the mean of the
/// newest 3. Quirk kept on purpose: once a current bearing exists, the crow-flies update is fed the
/// current-sample list, so the same sample is pushed twice.
public struct NavBearing: Equatable, Sendable {
    public static let unknown = 999

    var previousLocation = NavLocation.none
    public private(set) var current = unknown
    var hasCurrent = false
    var currentSamples: [Float] = []
    public private(set) var crowFlies = unknown
    var hasCrowFlies = false                    // never set true in the original
    var crowSamples: [Float] = []

    public init() {}

    /// `NavigationState::updateCurrentBearing`.
    mutating func update(_ fix: NavLocation) {
        current = Self.update(fix, current, hasCurrent, &currentSamples, previousLocation, currentMode: true)
        if current != Self.unknown || hasCurrent {
            if current != Self.unknown { hasCurrent = true }
            crowFlies = Self.update(fix, crowFlies, hasCrowFlies, &currentSamples, previousLocation, currentMode: false)
        } else {
            crowFlies = Self.update(fix, crowFlies, hasCrowFlies, &crowSamples, previousLocation, currentMode: false)
        }
        previousLocation = fix
    }

    /// `NavigationState::clearCurrentBearing`: the current samples move to the crow-flies list.
    mutating func clearCurrent() {
        current = Self.unknown
        hasCurrent = false
        crowSamples = currentSamples
        currentSamples.removeAll()
    }

    /// `updateBearingData` = `validateNewBearing` + `calculateCurrentBearing`.
    static func update(_ fix: NavLocation, _ previous: Int, _ previousValid: Bool, _ samples: inout [Float],
                       _ previousFix: NavLocation, currentMode: Bool) -> Int {
        if previousFix.exists, Double(previousFix.accuracy) < 35, Double(fix.accuracy) < 35,
           previousFix.distance(to: fix) > 3.5 {
            samples.append(Float(previousFix.bearing(to: fix)))
        }
        return calculate(&samples, previous, previousValid, currentMode: currentMode)
    }

    /// `calculateCurrentBearing`.
    static func calculate(_ v: inout [Float], _ previous: Int, _ previousValid: Bool, currentMode: Bool) -> Int {
        let n = v.count
        if n >= 3 {
            if !currentMode {
                v.removeFirst(n - 3)
                return NavMath.normalized(average(v))
            }
            for i in stride(from: n - 1, through: 0, by: -1) {
                let ref = Int(v[i])
                var picked: [Float] = []
                for j in stride(from: v.count - 1, through: 0, by: -1)
                where NavMath.smallerGap(Int(v[j]), ref) <= 40 {
                    picked.append(v[j])
                    if picked.count == 3 {
                        let avg = average(picked)
                        v.removeFirst(j)               // drop samples older than the 3rd pick
                        return NavMath.normalized(avg)
                    }
                }
            }
        }
        return previousValid ? NavMath.normalized(previous) : previous
    }

    /// `calculateAverageBearing`: circular mean with float accumulators.
    static func average(_ v: [Float]) -> Int {
        var s: Float = 0, c: Float = 0
        for b in v {
            s = Float(sin(NavMath.rad(Double(b))) + Double(s))
            c = Float(cos(NavMath.rad(Double(b))) + Double(c))
        }
        return Int(NavMath.deg(Double(atan2f(s, c))).rounded())
    }
}
