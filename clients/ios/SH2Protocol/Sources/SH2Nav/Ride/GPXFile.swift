import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum GPXError: Error, LocalizedError {
    case noPoints
    public var errorDescription: String? { "No track points found in the GPX file." }
}

/// The route in a GPX file, as both the screen and the ring follow it.
public struct GPXFile: Equatable, Sendable {
    public let name: String
    /// The route: its `<trkpt>`s, or its `<wpt>`s when there are more of them (what the official app
    /// navigates), or else its `<rtept>`s, which the official app couldn't navigate at all. They never
    /// mix: a track's points of interest or a planned `<rte>` next to it are not part of the route.
    public let points: [GeoPoint]
    /// Elevation per point in `points`.
    public let elevations: [Double?]
    public var navPoints: [GeoPoint] { points }

    /// Minimal GPX parser — extracts the `<trkpt>`s, `<rtept>`s and `<wpt>`s (lat/lon + optional
    /// `<ele>`), and the first `<name>`. Mirrors the fields used by the official app's `GPXParser`.
    public static func parse(data: Data) throws -> GPXFile {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw GPXError.noPoints }
        let main = delegate.waypoints.count > delegate.track.count ? delegate.waypoints : delegate.track
        let route = main.isEmpty ? delegate.planned : main
        guard !route.isEmpty else { throw GPXError.noPoints }
        return GPXFile(name: delegate.name.isEmpty ? "Route" : delegate.name, points: route.map(\.point),
                       elevations: route.map(\.elevation))
    }

    private struct Point {
        var point: GeoPoint
        var elevation: Double?
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var track: [Point] = []
        var waypoints: [Point] = []
        var planned: [Point] = []
        var name = ""
        private var current: ReferenceWritableKeyPath<Delegate, [Point]>?
        private var inName = false
        private var nameBuf = ""
        private var inEle = false
        private var eleBuf = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            let element = elementName.lowercased()
            switch element {
            case "trkpt", "rtept", "wpt":
                if let latS = attributeDict["lat"], let lonS = attributeDict["lon"],
                   let lat = Double(latS), let lon = Double(lonS) {
                    let list: ReferenceWritableKeyPath<Delegate, [Point]> =
                        element == "wpt" ? \.waypoints : element == "trkpt" ? \.track : \.planned
                    self[keyPath: list].append(Point(point: GeoPoint(lat, lon)))
                    current = list
                }
            case "ele" where current != nil:
                inEle = true; eleBuf = ""
            case "name" where name.isEmpty:
                inName = true; nameBuf = ""
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inName { nameBuf += string }
            if inEle { eleBuf += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            switch elementName.lowercased() {
            case "name" where inName:
                let trimmed = nameBuf.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { name = trimmed }
                inName = false
            case "ele" where inEle:
                if let e = Double(eleBuf.trimmingCharacters(in: .whitespacesAndNewlines)), let list = current,
                   let last = self[keyPath: list].indices.last {
                    self[keyPath: list][last].elevation = e
                }
                inEle = false
            case "trkpt", "rtept", "wpt":
                current = nil
            default: break
            }
        }
    }
}
