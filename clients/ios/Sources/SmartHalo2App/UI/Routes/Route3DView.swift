import SwiftUI
import MapKit

/// Full-screen 3D quick look at a route (from the route detail): Apple's realistic-elevation
/// terrain with the route draped on it, the same layers + 3D/2D controls as the Map tab, the route's
/// numbers and a "flyover" camera that rides the route from start to finish and pulls back to an
/// overview. MapKit only — no tile server, works anywhere Apple has 3D terrain (online).
struct Route3DView: View {
    let route: GPXRoute
    let fmt: UnitFormat
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("sh2.map.base") private var base: MapBase = .map
    @AppStorage("sh2.map.tiltHintShown") private var tiltHintShown = false

    @State private var position: MapCameraPosition
    @State private var is3D = true
    @State private var flights = 0
    @State private var showTiltHint = false
    @State private var live = LiveCamera()
    private let plan: FlyoverPlan

    init(route: GPXRoute, fmt: UnitFormat, onClose: @escaping () -> Void) {
        self.route = route
        self.fmt = fmt
        self.onClose = onClose
        let plan = FlyoverPlan(route: route)
        self.plan = plan
        _position = State(initialValue: .camera(plan.overview))
    }

    var body: some View {
        // `.pitch` must stay in the interaction modes (without it MapKit draws flat); steep tilts
        // come from `steepTilt`. Terrain is always 3D; "3D" = the camera is tilted.
        Map(position: $position, interactionModes: .all) {
            // Overlays above labels force MapKit back to flat; keep the route at road level.
            RouteMapLayers.route(route, overlayLevel: .aboveRoads)
        }
        .mapStyle(.halo(base, elevated: true))
        .mapControls { MapCompass() }
        .onMapCameraChange(frequency: .continuous) { context in
            live.camera = context.camera
            let tilted = context.camera.pitch > 1
            if tilted != is3D { is3D = tilted }
        }
        .steepTilt($position, live: live)
        .mapCameraKeyframeAnimator(trigger: flights) { _ in
            KeyframeTrack(\MapCamera.centerCoordinate) {
                CubicKeyframe(plan.centers[0], duration: FlyoverPlan.intro)
                for c in plan.centers.dropFirst() {
                    CubicKeyframe(c, duration: plan.step)
                }
                CubicKeyframe(plan.overview.centerCoordinate, duration: FlyoverPlan.outro)
            }
            KeyframeTrack(\MapCamera.heading) {
                CubicKeyframe(plan.headings[0], duration: FlyoverPlan.intro)
                for h in plan.headings.dropFirst() {
                    CubicKeyframe(h, duration: plan.step)
                }
                CubicKeyframe(plan.headings.last ?? 0, duration: FlyoverPlan.outro)
            }
            KeyframeTrack(\MapCamera.distance) {
                CubicKeyframe(FlyoverPlan.followDistance, duration: FlyoverPlan.intro)
                LinearKeyframe(FlyoverPlan.followDistance, duration: plan.duration)
                CubicKeyframe(plan.overview.distance, duration: FlyoverPlan.outro)
            }
            KeyframeTrack(\MapCamera.pitch) {
                CubicKeyframe(FlyoverPlan.followPitch, duration: FlyoverPlan.intro)
                LinearKeyframe(FlyoverPlan.followPitch, duration: plan.duration)
                CubicKeyframe(plan.overview.pitch, duration: FlyoverPlan.outro)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            VStack(spacing: Theme.Space.s) {
                topBar
                if showTiltHint { TiltHint() }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .trailing, spacing: Theme.Space.m) {
                MapViewControls(base: $base, is3D: is3D, toggle3D: toggle3D)
                    .padding(.horizontal, Theme.Space.l)
                bottomBar
            }
        }
        .task {
            showHintOnce()
            // Let the terrain load before taking off; Reduce Motion leaves the camera still.
            guard !reduceMotion, plan.canFly else { return }
            try? await Task.sleep(for: .seconds(0.8))
            flights += 1
        }
    }

    private func toggle3D() {
        guard let cam = live.camera else { return }
        let next = !is3D ? MapTilt.tilted(cam, pitch: MapTilt.pitch3D)
                         : MapCamera(centerCoordinate: cam.centerCoordinate, distance: cam.distance,
                                     heading: 0, pitch: 0)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.6)) { position = .camera(next) }
    }

    private func showHintOnce() {
        guard !tiltHintShown else { return }
        tiltHintShown = true
        withAnimation { showTiltHint = true }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation { showTiltHint = false }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .frame(width: Theme.minTarget, height: Theme.minTarget)
                    .background(Theme.surface.opacity(0.85), in: Circle())
            }
            .accessibilityLabel(Text("Close"))
            Spacer()
            Text(verbatim: route.name)
                .font(.headline)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.s)
                .background(Theme.surface.opacity(0.85), in: Capsule())
            Spacer()
            Color.clear.frame(width: Theme.minTarget, height: Theme.minTarget)
        }
        .padding(.horizontal, Theme.Space.l)
    }

    private var stats: [String] {
        var out = [fmt.distance(route.length)]
        if let gain = route.totalGain { out.append("↗ " + fmt.elevation(gain)) }
        if let loss = route.totalLoss { out.append("↘ " + fmt.elevation(loss)) }
        out.append("~" + fmt.duration(route.estimatedDuration))
        return out
    }

    private var bottomBar: some View {
        VStack(spacing: Theme.Space.m) {
            HStack {
                ForEach(Array(stats.enumerated()), id: \.offset) { i, s in
                    if i > 0 { Spacer(minLength: Theme.Space.s) }
                    Text(verbatim: s)
                }
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(Theme.textDim)
            if plan.canFly {
                PrimaryButton(flights == 0 ? "Fly the route" : "Fly again", systemImage: "play.fill") {
                    flights += 1
                }
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .background(Theme.bg.opacity(0.94))
    }
}

/// Camera keyframes for the flyover: evenly spaced samples along the route, each with a smoothed
/// direction of travel. Headings are unwrapped (may leave 0…360) so the camera always takes the
/// short way round instead of spinning at north.
struct FlyoverPlan {
    static let intro: TimeInterval = 2.5
    static let outro: TimeInterval = 3
    static let followDistance: CLLocationDistance = 1800
    static let followPitch: Double = 65

    let centers: [CLLocationCoordinate2D]
    let headings: [Double]
    /// Seconds between samples, and for the whole ride along the route.
    let step: TimeInterval
    let duration: TimeInterval
    let overview: MapCamera

    var canFly: Bool { centers.count > 1 }

    init(route: GPXRoute) {
        overview = .overview(of: route)

        let length = route.length
        // ~250 m of route per second, clamped so short loops don't blink and long ones don't drag.
        duration = min(max(length / 250, 20), 60)
        let n = max(1, min(Int(duration * 1.5), 90))
        step = duration / Double(n)

        // Heading over a window around each sample, so GPS zig-zags don't shake the camera.
        let look = max(150, length / Double(n) * 1.5)
        var cs: [CLLocationCoordinate2D] = []
        var hs: [Double] = []
        for i in 0...n {
            let along = length * Double(i) / Double(n)
            cs.append(route.coordinate(at: along))
            let raw = length > 0
                ? Geo.bearing(route.coordinate(at: along - look), route.coordinate(at: along + look))
                : 0
            hs.append(hs.last.map { $0 + Geo.angleDelta(from: $0, to: raw) } ?? raw)
        }
        centers = length > 0 ? cs : Array(cs.prefix(1))
        headings = hs
    }
}
