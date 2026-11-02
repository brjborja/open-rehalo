import Foundation

/// The user's distance/speed unit system (Settings › General › Units). Default comes from the locale.
enum DistanceUnits: String, CaseIterable, Identifiable, Codable {
    case metric      // km, m, km/h
    case imperial    // mi, ft, mph

    var id: String { rawValue }

    /// Metric unless the locale uses miles on the road (US, UK).
    static var localeDefault: DistanceUnits {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }

    /// Picker label.
    var label: LocalizedStringResource {
        switch self {
        case .metric: return "Kilometres (km)"
        case .imperial: return "Miles (mi)"
        }
    }
}

/// Locale-aware formatting of distances, speeds, elevations and durations, honouring the units
/// setting. Built on `Measurement` + `MeasurementFormatter` so symbols and decimal separators follow
/// the locale ("2,4 km" in Spanish, "2.4 km" in English).
///
/// Use `parts(…)` for `MetricView` (value and unit rendered separately) and the plain `String`
/// functions for inline text.
///
///     let f = UnitFormat(units: settings.units)
///     f.distance(2_400)           // "2.4 km"
///     f.distanceParts(350)        // Parts(value: "350", unit: "m")
///     f.speedParts(6.8)           // Parts(value: "24.5", unit: "km/h")
struct UnitFormat {
    var units: DistanceUnits
    var locale: Locale = .current

    /// A formatted value and its unit symbol, kept apart for big-number layouts.
    struct Parts: Equatable {
        let value: String
        let unit: String
        var text: String { unit.isEmpty ? value : "\(value) \(unit)" }
    }

    // MARK: Distance

    /// Route/turn distance. Metric: metres (rounded to 10) under 1 km, then km with one decimal
    /// (no decimals from 100 km). Imperial: feet under 0.1 mi, then miles.
    func distanceParts(_ meters: Double) -> Parts {
        let m = max(0, meters)
        switch units {
        case .metric:
            if m < 1000 {
                return parts(Measurement(value: roundTo(m, step: m < 100 ? 5 : 10), unit: UnitLength.meters), digits: 0)
            }
            let km = m / 1000
            return parts(Measurement(value: km, unit: UnitLength.kilometers), digits: km < 100 ? 1 : 0)
        case .imperial:
            let mi = m / 1609.344
            if mi < 0.1 {
                let ft = m * 3.280_84
                return parts(Measurement(value: roundTo(ft, step: 10), unit: UnitLength.feet), digits: 0)
            }
            return parts(Measurement(value: mi, unit: UnitLength.miles), digits: mi < 100 ? 1 : 0)
        }
    }

    func distance(_ meters: Double) -> String { distanceParts(meters).text }

    // MARK: Speed

    /// Speed from metres/second: km/h or mph, one decimal under 100.
    func speedParts(_ metersPerSecond: Double) -> Parts {
        let base = Measurement(value: max(0, metersPerSecond), unit: UnitSpeed.metersPerSecond)
        let target: UnitSpeed = units == .metric ? .kilometersPerHour : .milesPerHour
        let v = base.converted(to: target)
        return parts(v, digits: v.value < 100 ? 1 : 0)
    }

    func speed(_ metersPerSecond: Double) -> String { speedParts(metersPerSecond).text }

    // MARK: Elevation

    /// Elevation / climb: whole metres or feet.
    func elevationParts(_ meters: Double) -> Parts {
        let base = Measurement(value: meters, unit: UnitLength.meters)
        return parts(base.converted(to: units == .metric ? .meters : .feet), digits: 0)
    }

    func elevation(_ meters: Double) -> String { elevationParts(meters).text }

    // MARK: Duration

    /// "38 min", "1 h 05 min" (abbreviated, locale-aware).
    func duration(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .abbreviated
        f.zeroFormattingBehavior = .dropLeading
        var cal = Calendar.current
        cal.locale = locale
        f.calendar = cal
        return f.string(from: max(0, seconds)) ?? ""
    }

    // MARK: - Helpers

    private func parts<U: Dimension>(_ m: Measurement<U>, digits: Int) -> Parts {
        let nf = NumberFormatter()
        nf.locale = locale
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = digits
        nf.maximumFractionDigits = digits
        let mf = MeasurementFormatter()
        mf.locale = locale
        mf.unitOptions = .providedUnit
        mf.unitStyle = .medium
        mf.numberFormatter = nf
        let value = nf.string(from: NSNumber(value: m.value)) ?? "\(m.value)"
        return Parts(value: value, unit: mf.string(from: m.unit))
    }

    private func roundTo(_ v: Double, step: Double) -> Double { (v / step).rounded() * step }
}
