import Foundation
import CoreLocation
import SH2Protocol

/// Live ride numbers for the Halo's carousel cards (speed, distance, ride time, average speed),
/// from the iPhone's GPS — the official app's `CarouselController` feeds the same cards from its
/// ride. A ride starts when the ring first asks for a ride card and ends after `idleTimeout`
/// without movement or card requests.
///
/// Location updates run in the background like navigation (`location` UIBackgroundMode). With a
/// When-In-Use grant iOS only lets them *start* in the foreground: open rehalo before setting off.
@MainActor
final class RideMetrics {
    static let shared = RideMetrics()

    struct Snapshot {
        var speedKmh: Double = 0
        var metres: Int = 0
        var seconds: Int = 0
        var averageKmh: Double = 0
    }

    private let tracker = LocationTracker()
    private(set) var isRunning = false
    private var startedAt: Date?
    private(set) var lastFix: CLLocation?
    private var lastActivity = Date()
    private var distance: Double = 0
    private var movingSeconds: Double = 0
    private var speed: Double = 0              // m/s
    private var idleCheck: Task<Void, Never>?

    /// No movement and no ring requests for this long → the ride is over (numbers reset).
    private let idleTimeout: TimeInterval = 10 * 60
    /// Below this the rider is stopped (m/s).
    private let movingSpeed: Double = 1

    private init() {
        tracker.onLocation = { [weak self] loc in self?.handle(loc) }
    }

    /// The ring asked for a ride card: make sure a ride is being tracked, and return its numbers.
    func snapshotForRing() -> Snapshot {
        lastActivity = Date()
        if !isRunning { start() }
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        return Snapshot(speedKmh: speed * 3.6,
                        metres: Int(distance.rounded()),
                        seconds: Int(elapsed),
                        averageKmh: movingSeconds > 0 ? distance / movingSeconds * 3.6 : 0)
    }

    private func start() {
        isRunning = true
        startedAt = Date()
        distance = 0
        movingSeconds = 0
        speed = 0
        lastFix = nil
        tracker.start(background: true)
        SH2Log.log("ride: tracking for the ring's ride cards")
        idleCheck = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled else { return }
                if Date().timeIntervalSince(self.lastActivity) > self.idleTimeout { self.stop() }
            }
        }
    }

    private func stop() {
        guard isRunning else { return }
        isRunning = false
        idleCheck?.cancel()
        idleCheck = nil
        tracker.stop()
        startedAt = nil
        SH2Log.log("ride: idle — stopped tracking")
    }

    private func handle(_ loc: CLLocation) {
        guard isRunning, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 30 else { return }
        speed = max(0, loc.speed)
        if let last = lastFix {
            let dt = loc.timestamp.timeIntervalSince(last.timestamp)
            guard dt > 0 else { return }
            if speed >= movingSpeed {
                distance += loc.distance(from: last)
                movingSeconds += dt
                lastActivity = Date()
            }
        }
        lastFix = loc
    }
}
