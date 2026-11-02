import Foundation
import CoreLocation
import UIKit

/// The iPhone's compass, for the map's Compass mode and the rider's beam. Its own
/// `CLLocationManager`, so heading runs only while a map needs it, apart from `LocationTracker`.
///
/// Never asks iOS for its calibration screen (it would cover the ride): a poor `accuracy` makes
/// the caller fall back to the GPS course instead. Read on every frame, so nothing is `@Published`.
@MainActor
final class HeadingTracker: NSObject, CLLocationManagerDelegate {
    /// Degrees 0…359, 0 = north (true north when iOS knows it, else magnetic). nil until a reading.
    private(set) var heading: Double?
    /// Maximum error in degrees; negative = invalid.
    private(set) var accuracy: Double = -1

    /// Worse than this (or invalid) and the compass isn't trusted.
    static let maxAccuracy: Double = 30

    var isReliable: Bool { heading != nil && accuracy >= 0 && accuracy <= Self.maxAccuracy }

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 2
    }

    func start() {
        guard CLLocationManager.headingAvailable() else { return }
        syncOrientation()
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingHeading()
        heading = nil
        accuracy = -1
    }

    /// Heading is measured against the top of the *interface*, so it follows a landscape mount.
    /// (Interface landscape-left is the device turned landscape-right, and vice versa.)
    private func syncOrientation() {
        let scene = UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene
        let device: CLDeviceOrientation = switch scene?.interfaceOrientation ?? .portrait {
        case .landscapeLeft: .landscapeRight
        case .landscapeRight: .landscapeLeft
        case .portraitUpsideDown: .portraitUpsideDown
        default: .portrait
        }
        if manager.headingOrientation != device { manager.headingOrientation = device }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        let accuracy = newHeading.headingAccuracy
        Task { @MainActor in
            self.heading = value
            self.accuracy = accuracy
            self.syncOrientation()
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false
    }
}
