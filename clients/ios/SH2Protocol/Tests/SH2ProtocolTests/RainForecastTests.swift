import XCTest
@testable import SH2Protocol

final class RainForecastTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    /// A forecast whose slots end 5, 20, 35… minutes from `now` (the first one is still running).
    private func forecast(_ millimetres: [Double?]) -> RainForecast {
        let times = millimetres.indices.map { Int(now.timeIntervalSince1970) + 300 + $0 * 900 }
        let mm = millimetres.map { $0.map { "\($0)" } ?? "null" }.joined(separator: ",")
        let json = "{\"minutely_15\":{\"time\":\(times),\"precipitation\":[\(mm)]}}"
        return RainForecast(json: Data(json.utf8))!
    }

    func testParsing() {
        XCTAssertEqual(forecast([0, nil, 0.4]).slots.map(\.millimetres), [0, 0.4])
        XCTAssertNil(RainForecast(json: Data("{\"error\":true,\"reason\":\"nope\"}".utf8)))
        XCTAssertNil(RainForecast(json: Data("{\"minutely_15\":{\"time\":[],\"precipitation\":[]}}".utf8)))
    }

    func testMinutesToRain() {
        // Dry, and drizzle below the threshold.
        XCTAssertNil(forecast([0, 0, 0, 0]).minutesToRain(at: now))
        XCTAssertNil(forecast([0.1, 0.1]).minutesToRain(at: now))
        // Raining in the running slot.
        XCTAssertEqual(forecast([0.5, 0]).minutesToRain(at: now), 0)
        // Slot 3 starts in 20 minutes.
        XCTAssertEqual(forecast([0, 0, 1.2]).minutesToRain(at: now), 20)
        // Slots already over don't count.
        XCTAssertNil(forecast([1.2, 0]).minutesToRain(at: now.addingTimeInterval(600)))
        // Beyond the 30-minute window (starts in 50).
        XCTAssertNil(forecast([0, 0, 0, 0, 1.2]).minutesToRain(at: now))
    }

    func testOneAlertPerSpell() {
        var watch = RainWatch()
        XCTAssertFalse(watch.shouldAlert(minutes: nil, at: now))
        XCTAssertTrue(watch.shouldAlert(minutes: 20, at: now))
        // Still coming: quiet.
        XCTAssertFalse(watch.shouldAlert(minutes: 10, at: now.addingTimeInterval(600)))
        // A dry reading too soon doesn't rearm it.
        XCTAssertFalse(watch.shouldAlert(minutes: nil, at: now.addingTimeInterval(900)))
        XCTAssertFalse(watch.shouldAlert(minutes: 15, at: now.addingTimeInterval(1200)))
        // Dry after the gap does.
        XCTAssertFalse(watch.shouldAlert(minutes: nil, at: now.addingTimeInterval(1800)))
        XCTAssertTrue(watch.shouldAlert(minutes: 5, at: now.addingTimeInterval(2400)))
    }
}
