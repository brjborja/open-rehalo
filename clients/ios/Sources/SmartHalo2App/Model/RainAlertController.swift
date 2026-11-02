import CoreLocation
import Foundation
import SH2Protocol

/// Warns on the Halo when rain is close (promised by the official app, never shipped). Only during
/// a ride or navigation, with a ring connected: the app is running then, and it already has a
/// position. The forecast comes from Open-Meteo (free, no key, no entitlement; WeatherKit needs a
/// paid developer account). Off by default: it sends the rider's rounded position to a third party.
@MainActor
final class RainAlertController {
    static let shared = RainAlertController()

    /// How often to ask for a forecast.
    private let fetchInterval: TimeInterval = 10 * 60
    /// Don't cover the ring's guidance this close to a turn (metres): wait for the next check.
    private let turnClearance: Double = 150

    private var loop: Task<Void, Never>?
    private var forecast: RainForecast?
    private var lastFetch: Date?
    private var watch = RainWatch()

    /// Call once at launch (`SmartHalo2App.init`).
    func activate() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.check()
            }
        }
    }

    func test() {
        HaloConnection.shared.controller?.showRainAlert(text: Self.text(minutes: 20))
    }

    private func check() async {
        let connection = HaloConnection.shared
        guard AppSettings.shared.rainAlerts, connection.state == .connected, let position else { return }
        if lastFetch.map({ Date().timeIntervalSince($0) >= fetchInterval }) ?? true {
            lastFetch = Date()
            await fetch(position)
        }
        guard let forecast, let ring = connection.controller, !ring.callAlertActive, !turnIsClose else { return }
        let now = Date()
        let minutes = forecast.minutesToRain(at: now)
        if watch.shouldAlert(minutes: minutes, at: now), let minutes {
            ring.showRainAlert(text: Self.text(minutes: minutes))
        }
    }

    /// The rider's position, only while riding.
    private var position: CLLocationCoordinate2D? {
        if GuidanceController.shared.following { return GuidanceController.shared.lastLocation?.coordinate }
        return RideMetrics.shared.isRunning ? RideMetrics.shared.lastFix?.coordinate : nil
    }

    private var turnIsClose: Bool {
        let guidance = GuidanceController.shared
        return guidance.following && guidance.nextTurn != .straight && guidance.nextTurnDistance < turnClearance
    }

    private func fetch(_ position: CLLocationCoordinate2D) async {
        // Two decimals: about 1 km, finer than the forecast needs and than Open-Meteo should know.
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", position.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", position.longitude)),
            URLQueryItem(name: "minutely_15", value: "precipitation"),
            URLQueryItem(name: "forecast_minutely_15", value: "6"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        do {
            var request = URLRequest(url: url.url!)
            request.timeoutInterval = 15
            let (data, _) = try await URLSession.shared.data(for: request)
            if let fresh = RainForecast(json: data) {
                forecast = fresh
            } else {
                SH2Log.log("rain: unexpected reply from Open-Meteo")
            }
        } catch {
            SH2Log.log("rain: forecast failed: \(error.localizedDescription)")
        }
    }

    private static func text(minutes: Int) -> String {
        minutes == 0 ? String(localized: "Rain now") : String(localized: "Rain in \(minutes) min")
    }
}
