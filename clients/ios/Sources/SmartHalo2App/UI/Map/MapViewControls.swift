import SwiftUI
import MapKit

/// Base map picked with the layers button (remembered in `sh2.map.base`). The map is a quick look
/// at the route, not a planner, so there are only two.
enum MapBase: String {
    case map, satellite
}

extension MapStyle {
    /// The Halo look for `base`, flat or on Apple's realistic-elevation terrain (3D relief).
    static func halo(_ base: MapBase, elevated: Bool) -> MapStyle {
        let elevation: MapStyle.Elevation = elevated ? .realistic : .flat
        switch base {
        case .map: return .standard(elevation: elevation, emphasis: .muted, pointsOfInterest: .excludingAll)
        case .satellite: return .hybrid(elevation: elevation, pointsOfInterest: .excludingAll)
        }
    }
}

/// Camera tilt rules shared by the 3D button, the two-finger tilt and the flyover. MapKit caps
/// pitch by camera altitude (also for cameras set in code), so steep tilts lower the camera.
enum MapTilt {
    /// Pitch the 3D button tilts to.
    static let pitch3D = 60.0
    static let maxPitch = 80.0
    /// Below this pitch the camera distance is left alone.
    static let freePitch = 55.0

    /// Farthest camera distance at which MapKit still allows `pitch` — a guess (Apple documents no
    /// numbers), tune on the device: ~11 km at 60°, ~4.9 km at 65°, ~2.2 km at 70°, ~430 m at 80°.
    static func maxDistance(forPitch pitch: Double) -> CLLocationDistance {
        pitch <= freePitch ? .greatestFiniteMagnitude : 25_000 * pow(0.85, pitch - freePitch)
    }

    /// `camera` tilted to `pitch` around the same point, lowered if MapKit would clamp the tilt
    /// (never above `cap`, the distance to come back up to when tilting back).
    static func tilted(_ camera: MapCamera, pitch: Double, cap: CLLocationDistance? = nil) -> MapCamera {
        MapCamera(centerCoordinate: camera.centerCoordinate,
                  distance: min(cap ?? camera.distance, maxDistance(forPitch: pitch)),
                  heading: camera.heading, pitch: pitch)
    }
}

/// The map's latest camera, kept out of SwiftUI state so following it every frame doesn't
/// re-render the screen.
final class LiveCamera {
    var camera: MapCamera?
}

extension MapCamera {
    /// Tilted camera framing the whole route, north up.
    static func overview(of route: GPXRoute, pitch: Double = 55) -> MapCamera {
        let rect = route.boundingMapRect(padding: 0.1)
        let center = rect.isNull ? (route.start ?? CLLocationCoordinate2D())
                                 : MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        let side = rect.isNull ? 2000 : max(rect.width, rect.height) * MKMetersPerMapPointAtLatitude(center.latitude)
        return MapCamera(centerCoordinate: center, distance: max(side * 2.2, 2500), heading: 0, pitch: pitch)
    }
}

/// The map's view controls, one pill in the thumb column: layers (what you see: Map / Satellite)
/// over 3D/2D (where you look from). The 3D button shows what a tap does, like Apple Maps, and is
/// filled while in 3D.
struct MapViewControls: View {
    @Binding var base: MapBase
    let is3D: Bool
    let toggle3D: () -> Void

    @State private var showBases = false

    var body: some View {
        VStack(spacing: 0) {
            Button { showBases = true } label: {
                Image(systemName: "square.2.layers.3d")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(showBases ? Theme.onAccent : Theme.text)
                    .frame(width: 48, height: 48)
                    .background(showBases ? Theme.accent : .clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Map type"))
            .popover(isPresented: $showBases, arrowEdge: .trailing) {
                bases
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(Theme.surface2)
            }

            Theme.stroke.frame(width: 32, height: 1)

            Button(action: toggle3D) {
                Text(is3D ? "2D" : "3D")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(is3D ? Theme.onAccent : Theme.text)
                    .frame(width: 48, height: 48)
                    .background(is3D ? Theme.accent : .clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(is3D ? Text("Back to 2D") : Text("View in 3D"))
        }
        .background(Theme.surface.opacity(0.94))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private var bases: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Map type")
                .font(.footnote.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.textDim)
            MapBaseTiles(base: $base) { showBases = false }
            Text("Both work in 2D and 3D.")
                .font(.footnote)
                .foregroundStyle(Theme.textDim)
        }
        .padding(14)
        .frame(width: 252)
    }
}

/// The Map tab's single view button: everything about how the map looks, in one popover (Map /
/// Satellite, 3D, Compass), so the thumb column stays short.
struct MapViewMenu: View {
    @Binding var base: MapBase
    let is3D: Bool
    let isCompass: Bool
    let toggle3D: () -> Void
    let toggleCompass: () -> Void

    @State private var show = false

    var body: some View {
        MapRoundButton(systemImage: "square.2.layers.3d", label: "Map view", isOn: show) { show = true }
            .popover(isPresented: $show, arrowEdge: .trailing) {
                menu
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(Theme.surface2)
            }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Map type")
                .font(.footnote.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.textDim)
            MapBaseTiles(base: $base) { show = false }
            HStack(spacing: 10) {
                toggle("3D", isOn: is3D, action: toggle3D)
                toggle("Compass", isOn: isCompass, action: toggleCompass)
            }
        }
        .padding(14)
        .frame(width: 252)
    }

    private func toggle(_ title: LocalizedStringKey, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            show = false
            action()
        } label: {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isOn ? Theme.onAccent : Theme.text)
                .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                .background(isOn ? Theme.accent : Theme.surface,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isOn ? Color.clear : Theme.stroke, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The two base-map tiles (Map / Satellite); `onPick` runs after choosing one.
struct MapBaseTiles: View {
    @Binding var base: MapBase
    let onPick: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            baseTile(.map, title: "Map", systemImage: "map.fill", fill: Theme.bg)
            baseTile(.satellite, title: "Satellite", systemImage: "globe.europe.africa.fill",
                     fill: Color(hex: 0x3E4A31))
        }
    }

    private func baseTile(_ value: MapBase, title: LocalizedStringKey, systemImage: String,
                          fill: Color) -> some View {
        let selected = base == value
        return Button {
            base = value
            onPick()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill)
                    .frame(height: 76)
                    .overlay(Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.textDim))
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Theme.onAccent, Theme.accent)
                                .padding(6)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Theme.accent : Theme.stroke, lineWidth: selected ? 3 : 1))
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.text)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One-time hint shown the first time the map goes 3D.
struct TiltHint: View {
    var body: some View {
        Label("Slide two fingers up to tilt further", systemImage: "hand.draw")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, Theme.Space.s)
            .background(Theme.surface2.opacity(0.96), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            .transition(.opacity)
    }
}
