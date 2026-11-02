import Foundation
import CoreLocation
import MapKit
import SH2Protocol

/// A place picked on the Map tab: a search result or a long-press pin.
struct Destination: Identifiable, Equatable {
    let id: UUID
    var coordinate: CLLocationCoordinate2D
    var name: String
    var subtitle: String?

    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, name: String, subtitle: String? = nil) {
        self.id = id
        self.coordinate = coordinate
        self.name = name
        self.subtitle = subtitle
    }

    static func == (a: Destination, b: Destination) -> Bool {
        a.id == b.id && a.name == b.name && a.subtitle == b.subtitle
            && a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude
    }
}

/// How the rider wants to get there. MapKit has one bike profile and no notion of rider, so each kind
/// of route asks it for the closest thing it has.
enum RouteProfile: String, CaseIterable, Identifiable {
    /// Bike lanes and paths: Apple's bike routes.
    case city
    /// Tarmac: Apple's car routes without motorways or tolls. Not a bike route, and nothing keeps it
    /// off busy roads.
    case road
    /// Tracks and footpaths: Apple's walking routes.
    case trails

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .city: return "City"
        case .road: return "Road"
        case .trails: return "Trails"
        }
    }

    var systemImage: String {
        switch self {
        case .city: return "bicycle"
        case .road: return "road.lanes"
        case .trails: return "figure.hiking"
        }
    }
}

/// A route to a destination from Apple, ready for the ring guidance.
struct RoutedDestination {
    /// What Apple's route is for, which isn't always what was asked.
    enum Travel {
        case bike, car, foot

        var label: String {
            switch self {
            case .bike: return String(localized: "by bike")
            case .car: return String(localized: "by road")
            case .foot: return String(localized: "on foot")
            }
        }
    }

    let route: GPXRoute
    /// Where each of Apple's manoeuvres is + its text shortened for the ring's OLED.
    let instructions: [(location: NavLocation, text: String)]
    /// Apple's own steps: the turns of the ride.
    let steps: [RoutedStep]
    let expectedTravelTime: TimeInterval
    let travel: Travel
    /// What the rider should know before leaving, most important first.
    let notices: [String]
}

/// Routes with MapKit (`MKDirections`), no server of our own, in the rider's `RouteProfile`. Needs a
/// network connection; once computed, guidance works offline.
enum DestinationRouter {
    enum RouteError: LocalizedError {
        case noRoute
        var errorDescription: String? { String(localized: "No route found to this place.") }
    }

    /// Most of Apple's routes the rider chooses from.
    static let maxOptions = 3

    /// Routes from `origin` (nil = the current location) to `destination`, Apple's best first. `id`
    /// keeps a stable route id (e.g. the destination's, or a lead-in's).
    static func routes(to destination: Destination, from origin: CLLocationCoordinate2D? = nil,
                       profile: RouteProfile, id: UUID = UUID()) async throws -> [RoutedDestination] {
        switch profile {
        case .city:
            if let bike = bikeTransport,
               let options = try? await calculate(destination, origin, id: id, transport: bike) { return options }
            return try await calculate(destination, origin, id: id, transport: .walking)
        case .road:
            return try await calculate(destination, origin, id: id, transport: .automobile)
        case .trails:
            return try await calculate(destination, origin, id: id, transport: .walking)
        }
    }

    /// Apple's best route, where the rider doesn't choose (a lead-in).
    static func route(to destination: Destination, from origin: CLLocationCoordinate2D? = nil,
                      profile: RouteProfile, id: UUID = UUID()) async throws -> RoutedDestination {
        guard let best = try await routes(to: destination, from: origin, profile: profile, id: id).first else {
            throw RouteError.noRoute
        }
        return best
    }

    private static func calculate(_ destination: Destination, _ origin: CLLocationCoordinate2D?, id: UUID,
                                  transport: MKDirectionsTransportType) async throws -> [RoutedDestination] {
        let request = MKDirections.Request()
        request.source = origin.map { MKMapItem(placemark: MKPlacemark(coordinate: $0)) } ?? .forCurrentLocation()
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.requestsAlternateRoutes = true
        request.transportType = transport
        if transport == .automobile {
            request.highwayPreference = .avoid
            request.tollPreference = .avoid
        }
        let response = try await MKDirections(request: request).calculate()
        // `.avoid` is only a preference: motorways are the last resort.
        let clear = response.routes.filter { !$0.hasHighways }
        let routes = transport == .automobile && !clear.isEmpty ? clear : response.routes
        let options = routes.prefix(maxOptions).compactMap { routed($0, to: destination, id: id) }
        guard !options.isEmpty else { throw RouteError.noRoute }
        return options
    }

    private static func routed(_ r: MKRoute, to destination: Destination, id: UUID) -> RoutedDestination? {
        let points = r.polyline.coordinates
        guard points.count >= 2 else { return nil }
        let route = GPXRoute(id: id, name: destination.name, points: points)
        let travel: RoutedDestination.Travel = r.transportType == .walking ? .foot
            : r.transportType == .automobile ? .car : .bike
        let onFoot = { (step: MKRoute.Step) in step.transportType == .walking && travel != .foot }
        let steps = r.steps.map { step in
            RoutedStep(points: step.polyline.coordinates.map { GeoPoint($0) }, text: step.instructions,
                       caution: step.notice != nil || onFoot(step))
        }

        var notices: [String] = []
        if travel == .car {
            notices.append(r.hasHighways
                ? String(localized: "This car route uses motorways, which may be banned for bikes.")
                : String(localized: "A car route without motorways: check it before you ride."))
        }
        notices += r.advisoryNotices + r.steps.compactMap(\.notice)
        if r.steps.contains(where: onFoot) { notices.append(String(localized: "Part of this route is on foot.")) }
        var seen = Set<String>()

        return RoutedDestination(route: route, instructions: RoutedStep.instructions(steps), steps: steps,
                                 // Apple's time for a car says nothing about a bike.
                                 expectedTravelTime: travel == .car ? route.estimatedDuration : r.expectedTravelTime,
                                 travel: travel, notices: notices.filter { seen.insert($0).inserted })
    }

    /// Apple's bike routes. The symbol came with Xcode 26 / Swift 6.2, though it's marked iOS 14+: an
    /// iOS that can't do them answers with an error, and the rider gets a walking route.
    private static var bikeTransport: MKDirectionsTransportType? {
        #if compiler(>=6.2)
        return MKDirectionsTransportType.cycling
        #else
        return nil
        #endif
    }
}

extension MKMultiPoint {
    var coordinates: [CLLocationCoordinate2D] {
        var c = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&c, range: NSRange(location: 0, length: pointCount))
        return c
    }
}

/// A route as a minimal GPX (one track), to save a routed destination in the library.
enum GPXWriter {
    static func data(name: String, points: [CLLocationCoordinate2D]) -> Data {
        var s = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="rehalo (Apple Maps route)" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>\(escape(name))</name><trkseg>

        """
        for p in points {
            s += String(format: "<trkpt lat=\"%.6f\" lon=\"%.6f\"/>\n", p.latitude, p.longitude)
        }
        s += "</trkseg></trk>\n</gpx>\n"
        return Data(s.utf8)
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
