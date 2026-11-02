import Foundation

/// Addition: one step of a routing service's route (Apple's `MKRoute.Step`). The official app
/// rode destinations on typed Valhalla steps, not on its GPX detector; this gives the guidance the same
/// from what MapKit has, geometry and text, with no manoeuvre type.
public struct RoutedStep: Equatable, Sendable, Codable {
    /// The stretch of the route this step covers.
    public var points: [GeoPoint]
    /// The instruction as it came, in the device's language. May be empty.
    public var text: String
    /// On foot in a bike route, or with a notice from the service: the ring's caution colour.
    public var caution: Bool

    public init(points: [GeoPoint], text: String, caution: Bool = false) {
        self.points = points; self.text = text; self.caution = caution
    }

    var length: Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// Shorter than this a step is a marker of where the route starts or ends, not a stretch of it.
    static let minimumLength = 1.0
    /// How far the steps' length can be from the route's before they can't be trusted.
    static let lengthTolerance = 0.1

    /// A stretch of the route and the instruction of the manoeuvre at its start.
    struct Stretch {
        var points: [NavLocation]
        var text: String
        var caution: Bool
    }

    /// The route's stretches, each with the instruction of its first manoeuvre. Apple doesn't document
    /// which end of its polyline an instruction belongs to, but either way one step has no length: with
    /// the instruction at the end it's the first step, and the last one is the ride to "Arrive"; with
    /// the instruction at the start it's "Arrive" itself. This only decides which text goes with which
    /// turn: where the turns are and their angles don't depend on it.
    static func stretches(_ steps: [RoutedStep]) -> [Stretch] {
        let real = steps.filter { $0.length >= minimumLength }
        let atEnd = (steps.last?.length ?? 0) >= minimumLength
        return real.indices.map { i in
            Stretch(points: real[i].points.map { NavLocation($0.lat, $0.lon) },
                    text: atEnd ? (i > 0 ? real[i - 1].text : "") : real[i].text,
                    caution: real[i].caution)
        }
    }

    /// Where each manoeuvre is and its text for the OLED, for a route still on the GPX detector.
    public static func instructions(_ steps: [RoutedStep]) -> [(location: NavLocation, text: String)] {
        stretches(steps).dropFirst().compactMap { s in
            guard !s.text.isEmpty, let start = s.points.first else { return nil }
            return (location: start, text: oledText(s.text))
        }
    }

    /// The steps add up to a route of `length` metres. If not, they can't be trusted for its turns.
    public static func covers(_ steps: [RoutedStep], length: Double) -> Bool {
        let total = steps.filter { $0.length >= minimumLength }.reduce(0) { $0 + $1.length }
        return total > 0 && abs(total - length) <= length * lengthTolerance
    }

    // MARK: - Text

    /// An instruction for the OLED, which fits 18–20 characters: the street, after the exit in a
    /// roundabout ("Salida 2 · Carrer Major").
    public static func oledText(_ instruction: String) -> String {
        let street = NavDirector.shortInstruction(instruction)
        guard isRoundabout(instruction), let exit = exitLabel(instruction) else { return street }
        return street == instruction ? exit : "\(exit) · \(street)"
    }

    /// MapKit doesn't say which steps are roundabouts: the app's two languages are read from the text.
    static func isRoundabout(_ instruction: String) -> Bool {
        let text = instruction.lowercased()
        return ["roundabout", "rotonda", "glorieta"].contains { text.contains($0) }
    }

    /// "take the second exit" → "Exit 2", "toma la 2.ª salida" → "Salida 2". The ordinal is searched
    /// before the word, as a street after it can have one too ("… hacia Calle Primera").
    static func exitLabel(_ instruction: String) -> String? {
        let text = instruction.lowercased()
        let word = text.contains("salida") ? (key: "salida", label: "Salida") : (key: "exit", label: "Exit")
        guard let end = text.range(of: word.key)?.lowerBound else { return nil }
        let before = text[..<end]
        guard let n = ordinals.firstIndex(where: { $0.contains { before.contains($0) } }) else { return nil }
        return "\(word.label) \(n + 1)"
    }

    static let ordinals = [
        ["first", "1st", "primera", "1.ª", "1ª"], ["second", "2nd", "segunda", "2.ª", "2ª"],
        ["third", "3rd", "tercera", "3.ª", "3ª"], ["fourth", "4th", "cuarta", "4.ª", "4ª"],
        ["fifth", "5th", "quinta", "5.ª", "5ª"], ["sixth", "6th", "sexta", "6.ª", "6ª"],
    ]
}

extension NavStepFactory {
    /// Under this a change of step is a new street name, not a turn.
    static let routedTurnMinimum = 20
    /// Headings are read this far from a manoeuvre, over `headingSpan` metres: closer in, a rounded
    /// corner hasn't finished turning.
    static let headingOffset = 20.0
    static let headingSpan = 20.0
    /// Two headings in a row within this are a straight road: a roundabout has been left behind.
    static let settledWithin = 10

    /// A routed route → steps, as `steps(from:)` does for a GPX, and the OLED text of each turn (step
    /// index → text). All STANDARD: a roundabout is an arc with its net angle, as MapKit doesn't give
    /// the angles of its exits for the ring's own display.
    static func steps(routed: [RoutedStep]) -> (steps: [NavStep], texts: [Int: String]) {
        let stretches = RoutedStep.stretches(routed)
        guard let first = stretches.first, let start = first.points.first else { return ([], [:]) }
        let continueKey = "nav.inject.continue.instruction"
        var steps = [NavStep(type: NavStepType.standard, angles: [], headingBefore: 0, headingAfter: 0,
                             entrance: start, exit: start, mode: first.caution ? 1 : 0,
                             instruction: continueKey, streetName: continueKey,
                             path: first.points, firstDistance: 0, startIndex: 0)]
        var texts: [Int: String] = [:]
        for s in stretches.dropFirst() {
            guard let m = s.points.first else { continue }
            let last = steps[steps.count - 1]
            let roundabout = RoutedStep.isRoundabout(s.text)
            let back = settledHeading(Array(last.path.reversed()), past: headingOffset)
            let before = NavMath.normalized(back + 180)
            let after = roundabout ? headingOut(s.points) : settledHeading(s.points, past: headingOffset)
            let angle = NavMath.difference(before, after)
            let mode = s.caution ? 1 : 0
            if abs(angle) < routedTurnMinimum && mode == last.mode && !roundabout {
                steps[steps.count - 1].path += s.points.dropFirst()
                continue
            }
            let key = angle > 0 ? "nav.found.right" : "nav.found.left"
            steps.append(NavStep(type: NavStepType.standard, angles: [angle],
                                 headingBefore: before, headingAfter: after, entrance: m, exit: m, mode: mode,
                                 instruction: key, streetName: key, path: s.points, firstDistance: 0, startIndex: 0))
            if !s.text.isEmpty { texts[steps.count - 1] = RoutedStep.oledText(s.text) }
        }

        var total = 0
        for i in steps.indices {
            steps[i].firstDistance = Path(points: steps[i].path).distance
            steps[i].startIndex = total
            total += steps[i].path.count
        }
        let last = steps[steps.count - 1]
        let end = last.path[last.path.count - 1]
        let arrival = "nav.inject.direct.arrival"
        steps.append(NavStep(type: NavStepType.destination, angles: [], headingBefore: last.headingBefore,
                             headingAfter: 0, entrance: end, exit: end, mode: 0,
                             instruction: arrival, streetName: arrival,
                             path: [end], firstDistance: 0, startIndex: total))
        return (steps, texts)
    }

    /// The heading of `path` once `offset` metres along it, in the original's -180…180. A stretch too
    /// short for that gets its chord, as a heading between two equal points would be meaningless.
    static func settledHeading(_ path: [NavLocation], past offset: Double) -> Int {
        let a = point(on: path, at: offset), b = point(on: path, at: offset + headingSpan)
        let enough = a.distance(to: b) >= headingSpan / 2
        return Int((enough ? a : path[0]).bearing(to: enough ? b : path[path.count - 1]))
    }

    /// Where a roundabout's way out points: where the path stops turning, as how far round it goes
    /// depends on the roundabout's size and the exit. A stretch that never settles gets its chord.
    static func headingOut(_ path: [NavLocation]) -> Int {
        let length = Path(points: path).distance
        var along = headingOffset
        var heading = settledHeading(path, past: along)
        while along + 2 * headingSpan <= length {
            along += headingSpan
            let next = settledHeading(path, past: along)
            if abs(NavMath.difference(heading, next)) < settledWithin { return next }
            heading = next
        }
        return Int(path[0].bearing(to: path[path.count - 1]))
    }

    /// The point `metres` along `path`, or its end.
    static func point(on path: [NavLocation], at metres: Double) -> NavLocation {
        var left = metres
        for (a, b) in zip(path, path.dropFirst()) {
            let d = a.distance(to: b)
            if d > 0 && d >= left {
                let t = left / d
                return NavLocation(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t)
            }
            left -= d
        }
        return path[path.count - 1]
    }
}
