import SwiftUI
import MapKit
import UIKit

/// Two-finger vertical drag that tilts a 3D map further than MapKit's own pitch gesture, for
/// looking along valleys and up at ridges. Past `MapTilt.freePitch` it lowers the camera as it
/// tilts (`MapTilt.tilted`); dragging back down restores the starting distance. `onPitch` reports
/// each new pitch, so the screen can switch its 3D state as the rider tilts in or out.
///
/// Use on a `Map` that keeps `.pitch` in its `interactionModes` (without it MapKit ignores the
/// camera's pitch and draws flat) and feeds `live` from `onMapCameraChange(frequency: .continuous)`.
/// MapKit's own two-finger pan (its tilt) is made to wait for this one to fail, so they don't fight:
///
///     Map(position: $camera, interactionModes: .all) { … }
///         .onMapCameraChange(frequency: .continuous) { live.camera = $0.camera }
///         .steepTilt($camera, live: live) { is3D = $0 > 1 }
extension View {
    func steepTilt(_ position: Binding<MapCameraPosition>, live: LiveCamera, enabled: Bool = true,
                   onPitch: @escaping (Double) -> Void = { _ in }) -> some View {
        modifier(SteepTilt(position: position, live: live, enabled: enabled, onPitch: onPitch))
    }
}

private struct SteepTilt: ViewModifier {
    @Binding var position: MapCameraPosition
    let live: LiveCamera
    var enabled: Bool
    var onPitch: (Double) -> Void

    @State private var start: MapCamera?

    /// Degrees of tilt per point of finger travel (drag up = more tilt, like MapKit).
    static let degreesPerPoint = 0.3

    func body(content: Content) -> some View {
        content.background(TwoFingerDrag(enabled: enabled) { state, dy in drag(state, dy) })
    }

    private func drag(_ state: UIGestureRecognizer.State, _ dy: CGFloat) {
        switch state {
        case .began:
            start = live.camera
        case .changed:
            guard let start else { return }
            let pitch = min(max(start.pitch - Double(dy) * Self.degreesPerPoint, 0), MapTilt.maxPitch)
            position = .camera(MapTilt.tilted(start, pitch: pitch, cap: start.distance))
            onPitch(pitch)
        default:
            start = nil
        }
    }
}

/// Reports two-finger, mostly vertical drags over the view it backs. The recognizer sits on the
/// window (SwiftUI's `Map` doesn't expose its view) and only takes touches that land on this view
/// while it's on the frontmost screen, so a map under a full-screen cover stays quiet.
private struct TwoFingerDrag: UIViewRepresentable {
    var enabled: Bool
    var onDrag: (UIGestureRecognizer.State, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Anchor {
        let view = Anchor()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: Anchor, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.onDrag = onDrag
    }

    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) {
        coordinator.attach(to: nil)
    }

    final class Anchor: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: window == nil ? nil : self)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var enabled = true
        var onDrag: (UIGestureRecognizer.State, CGFloat) -> Void = { _, _ in }
        private weak var anchor: UIView?

        private lazy var pan: UIPanGestureRecognizer = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            pan.cancelsTouchesInView = false
            pan.delegate = self
            return pan
        }()

        func attach(to view: UIView?) {
            pan.view?.removeGestureRecognizer(pan)
            anchor = view
            view?.window?.addGestureRecognizer(pan)
        }

        @objc private func handle(_ pan: UIPanGestureRecognizer) {
            onDrag(pan.state, pan.translation(in: pan.view).y)
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard enabled, let anchor, let window = anchor.window else { return false }
            // Only the frontmost screen: skip maps under a presented (full-screen) controller.
            var top = window.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            guard let topView = top?.view, anchor.isDescendant(of: topView),
                  anchor.bounds.contains(touch.location(in: anchor)) else { return false }
            if let map = touch.view.flatMap(Self.mapView(containing:)) { yieldTilt(of: map) }
            return true
        }

        /// Pinch / twist keep working alongside this drag.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        /// MapKit's tilt is a two-finger pan somewhere inside its map view: make every such pan
        /// wait for ours to fail (ours only begins on a mostly vertical drag).
        private var yielded = Set<ObjectIdentifier>()

        private func yieldTilt(of map: UIView) {
            var stack = [map]
            while let view = stack.popLast() {
                for g in view.gestureRecognizers ?? [] where g !== pan {
                    guard let other = g as? UIPanGestureRecognizer, other.minimumNumberOfTouches >= 2,
                          yielded.insert(ObjectIdentifier(other)).inserted else { continue }
                    other.require(toFail: pan)
                }
                stack.append(contentsOf: view.subviews)
            }
        }

        private static func mapView(containing view: UIView) -> UIView? {
            var v: UIView? = view
            while let current = v {
                if current is MKMapView { return current }
                v = current.superview
            }
            return nil
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            // Both fingers sliding up/down together; pinches and twists barely move the centroid.
            let v = pan.velocity(in: pan.view)
            return abs(v.y) > 80 && abs(v.y) > 2 * abs(v.x)
        }
    }
}
