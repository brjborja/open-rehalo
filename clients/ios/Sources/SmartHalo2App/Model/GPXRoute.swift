import Foundation
import CoreLocation
import MapKit
import SH2Protocol

/// A route loaded from a GPX file: its shape (`RouteGeometry`, shared with the ride logic) with the
/// coordinates the map needs.
///
/// Identity is the `id` (two loads of the same file are different routes); M9's library can pass a
/// stable id when it rebuilds a route from storage.
struct GPXRoute: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let geometry: RouteGeometry
    let points: [CLLocationCoordinate2D]
    /// The points the official app navigates (ring guidance, `NavDirector`), see `RouteGeometry`.
    let navPoints: [CLLocationCoordinate2D]

    init(id: UUID = UUID(), name: String, geometry: RouteGeometry) {
        self.id = id
        self.name = name
        self.geometry = geometry
        points = geometry.points.map { CLLocationCoordinate2D($0) }
        navPoints = geometry.navPoints.map { CLLocationCoordinate2D($0) }
    }

    init(id: UUID = UUID(), name: String, points: [CLLocationCoordinate2D], elevations: [Double?] = [],
         navPoints: [CLLocationCoordinate2D]? = nil) {
        self.init(id: id, name: name,
                  geometry: RouteGeometry(points: points.map { GeoPoint($0) }, elevations: elevations,
                                          navPoints: navPoints?.map { GeoPoint($0) }))
    }

    static func == (a: GPXRoute, b: GPXRoute) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    // MARK: Stats

    /// Elevation per point in metres (`nil` where the GPX has no `<ele>`). Same count as `points`.
    var elevations: [Double?] { geometry.elevations }
    /// Distance along the route at each point, metres. `cumulative[0] == 0`.
    var cumulative: [Double] { geometry.cumulative }
    /// Total length, metres.
    var length: Double { geometry.length }
    var hasElevation: Bool { geometry.hasElevation }
    /// Total climb, metres (nil without elevation data).
    var totalGain: Double? { geometry.totalGain }
    /// Total descent, metres, with the same 3 m hysteresis as the climb (nil without elevation).
    var totalLoss: Double? { geometry.totalLoss }
    var start: CLLocationCoordinate2D? { points.first }
    var end: CLLocationCoordinate2D? { points.last }

    /// Rough riding time: 16 km/h on the flat + 2 s per metre of climb. Shown as "~ETA" before
    /// starting (UX_DESIGN §4.2); not a promise.
    var estimatedDuration: TimeInterval {
        length / (16 / 3.6) + (totalGain ?? 0) * 2
    }

    /// Map rect enclosing the route (for camera framing), padded by `padding` (fraction per side).
    func boundingMapRect(padding: Double = 0.15) -> MKMapRect {
        guard !points.isEmpty else { return .null }
        let rect = MKPolyline(coordinates: points, count: points.count).boundingMapRect
        let w = max(rect.size.width, 400), h = max(rect.size.height, 400)
        let base = MKMapRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        return base.insetBy(dx: -w * padding, dy: -h * padding)
    }

    // MARK: Along-route geometry

    /// The point `along` metres from the start (clamped to the route).
    func coordinate(at along: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(geometry.coordinate(at: along))
    }

    /// Direction of travel (degrees, 0 = north) at `along`.
    func heading(at along: Double) -> Double { geometry.heading(at: along) }

    /// A short built-in loop, only a fallback for demo mode if the bundled `DemoRoute.gpx` is missing.
    static let demo: GPXRoute = {
        let base = (lat: 45.5231, lon: -73.5817)   // Montréal
        let offsets: [(Double, Double)] = [
            (0.0000, 0.0000), (0.0008, 0.0002), (0.0016, 0.0006), (0.0022, 0.0014),
            (0.0024, 0.0024), (0.0020, 0.0033), (0.0012, 0.0038), (0.0003, 0.0037),
            (-0.0004, 0.0030), (-0.0006, 0.0020), (-0.0004, 0.0010), (0.0000, 0.0002),
        ]
        let pts = offsets.map {
            CLLocationCoordinate2D(latitude: base.lat + $0.0, longitude: base.lon + $0.1)
        }
        return GPXRoute(name: "Demo loop (Montréal)", points: pts)
    }()
}

/// Reads a GPX file into a route (`GPXFile`).
struct GPXDocumentParser {
    func parse(data: Data) throws -> GPXRoute {
        let file = try GPXFile.parse(data: data)
        return GPXRoute(name: file.name, geometry: RouteGeometry(points: file.points, elevations: file.elevations,
                                                                 navPoints: file.navPoints))
    }
}

extension GeoPoint {
    init(_ c: CLLocationCoordinate2D) { self.init(c.latitude, c.longitude) }
}

extension CLLocationCoordinate2D {
    init(_ p: GeoPoint) { self.init(latitude: p.lat, longitude: p.lon) }
}

extension RideFix {
    init(_ loc: CLLocation) {
        self.init(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude,
                  horizontalAccuracy: loc.horizontalAccuracy, course: loc.course, speed: loc.speed,
                  time: loc.timestamp.timeIntervalSince1970)
    }
}

/// Great-circle geo helpers for guidance.
enum Geo {
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Initial bearing from `a` to `b` in degrees 0…359 (0 = north, 90 = east).
    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        GeoPoint(a).bearing(to: GeoPoint(b))
    }

    /// Point `distance` metres from `c` towards `bearing` (flat-earth; for short hops only).
    static func offset(_ c: CLLocationCoordinate2D, distance: Double, bearing: Double) -> CLLocationCoordinate2D {
        let b = bearing * .pi / 180
        let dLat = distance * cos(b) / 111_320
        let dLon = distance * sin(b) / (111_320 * max(0.01, cos(c.latitude * .pi / 180)))
        return CLLocationCoordinate2D(latitude: c.latitude + dLat, longitude: c.longitude + dLon)
    }

    /// Signed smallest difference `to - from` in degrees, in (-180, 180]. Positive = clockwise (right).
    static func angleDelta(from: Double, to: Double) -> Double { GeoPoint.angleDelta(from: from, to: to) }
}
