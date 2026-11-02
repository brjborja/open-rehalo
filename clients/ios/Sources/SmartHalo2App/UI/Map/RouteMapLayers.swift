import SwiftUI
import MapKit

/// Map layers shared by the Map tab and the Navigating screen: the route in accent with a wide,
/// low-opacity glow under it (so it reads on the muted dark map), plus start / finish markers.
/// `overlayLevel: .aboveRoads` is needed on realistic-elevation (3D) maps: MapKit drops to flat
/// as soon as an overlay sits above labels.
enum RouteMapLayers {
    @MapContentBuilder
    static func route(_ route: GPXRoute, overlayLevel: MKOverlayLevel = .aboveLabels) -> some MapContent {
        MapPolyline(coordinates: route.points)
            .stroke(Theme.accent.opacity(0.22),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
            .mapOverlayLevel(level: overlayLevel)
        MapPolyline(coordinates: route.points)
            .stroke(Theme.accent,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            .mapOverlayLevel(level: overlayLevel)
        if let start = route.start {
            Annotation("Start", coordinate: start, anchor: .center) {
                RouteEndpointMarker(isFinish: false)
            }
            .annotationTitles(.hidden)
        }
        if let end = route.end {
            Annotation("Finish", coordinate: end, anchor: .center) {
                RouteEndpointMarker(isFinish: true)
            }
            .annotationTitles(.hidden)
        }
    }

    /// Another of Apple's routes to the same place, drawn under the chosen one.
    static func alternative(_ route: GPXRoute, overlayLevel: MKOverlayLevel) -> some MapContent {
        MapPolyline(coordinates: route.points)
            .stroke(Theme.textDim.opacity(0.7),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            .mapOverlayLevel(level: overlayLevel)
    }
}

/// Start (accent ring) / finish (checkered flag) marker.
struct RouteEndpointMarker: View {
    let isFinish: Bool

    var body: some View {
        if isFinish {
            Image(systemName: "flag.checkered")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 28, height: 28)
                .background(Theme.accent, in: Circle())
                .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 2))
        } else {
            Circle()
                .fill(Theme.bg)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 4))
        }
    }
}

/// The rider: cyan dot with a direction arrow. `rotation` = heading relative to the screen.
/// With `beamSpread` (half-width, degrees) the arrow becomes a beam of light, like Apple Maps' blue
/// dot: the wider it opens, the less sure the direction is.
struct RiderMarker: View {
    var rotation: Double = 0
    var beamSpread: Double?

    var body: some View {
        ZStack {
            if let beamSpread {
                Beam(spread: beamSpread)
                    .fill(RadialGradient(colors: [Theme.info.opacity(0.6), Theme.info.opacity(0)],
                                         center: .center, startRadius: 8, endRadius: 48))
                    .frame(width: 96, height: 96)
                    .animation(.easeInOut(duration: 0.4), value: beamSpread)
            } else {
                Circle().fill(Theme.info.opacity(0.22)).frame(width: 48, height: 48)
            }
            Circle().fill(Theme.info).frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(Theme.text, lineWidth: 3))
            if beamSpread == nil {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.onAccent)
            }
        }
        .rotationEffect(.degrees(rotation))
        .accessibilityHidden(true)
    }

    /// Wedge pointing up from the centre, `spread` degrees to each side.
    private struct Beam: Shape {
        var spread: Double
        var animatableData: Double {
            get { spread }
            set { spread = newValue }
        }

        func path(in rect: CGRect) -> Path {
            let c = CGPoint(x: rect.midX, y: rect.midY)
            var p = Path()
            p.move(to: c)
            p.addArc(center: c, radius: min(rect.width, rect.height) / 2,
                     startAngle: .degrees(-90 - spread), endAngle: .degrees(-90 + spread), clockwise: false)
            p.closeSubpath()
            return p
        }
    }
}

extension MapStyle {
    /// Dark, muted base map without POIs (the route is the protagonist). Dark comes from the app's
    /// `preferredColorScheme(.dark)`.
    static var halo: MapStyle { .standard(emphasis: .muted, pointsOfInterest: .excludingAll) }
}
