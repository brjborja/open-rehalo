import XCTest

/// Walks the app in demo mode and saves the website's screenshots (`.github/workflows/screenshots.yml`).
/// Not a behaviour test: a missing element only skips that screen and dumps the UI tree beside the
/// PNGs, so one renamed label can't cost the other shots.
final class ScreenshotTests: XCTestCase {
    private static let outputDir = URL(fileURLWithPath: "/tmp/rehalo-shots", isDirectory: true)

    /// `PlaceSearch.Recent` list as a defaults value: a plist `<data>` literal of its JSON.
    private static let recentDestinations: String = {
        let places: [(String, String, Double, Double)] = [
            ("Sagrada Família", "Carrer de Mallorca, 401, Barcelona", 41.4036, 2.1744),
            ("Park Güell", "Carrer d'Olot, Barcelona", 41.4145, 2.1527),
            ("Mercat de la Boqueria", "La Rambla, 91, Barcelona", 41.3817, 2.1716),
            ("Platja de la Barceloneta", "Barcelona", 41.3784, 2.1925),
        ]
        let list = places.map { ["name": $0.0, "subtitle": $0.1, "latitude": $0.2, "longitude": $0.3] as [String: Any] }
        let json = try! JSONSerialization.data(withJSONObject: list)
        return "<data>\(json.base64EncodedString())</data>"
    }()

    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = true
        try FileManager.default.createDirectory(at: Self.outputDir, withIntermediateDirectories: true)
        // Argument-domain defaults: skip onboarding, run the simulated ring, and show the features on.
        app.launchArguments = ["-sh2.onboarded", "YES", "-sh2.demoMode", "YES",
                               "-sh2.units", "metric", "-sh2.rain.alerts", "YES",
                               "-sh2.alarm.on", "YES", "-sh2.alarm.tapCode", "SLSLS",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    func test1_MapAndSearch() {
        launch()
        pause(8)
        shot("01-map")
        guard tap(app.buttons["Search a place or a route"], "search-pill") else { return }
        dismissKeyboardTip()
        pause(2)
        guard tap(app.buttons["Use demo route"], "demo-route") else { return }
        pause(5)
        shot("03-route-on-map")

        // Sample places, so the search sheet shows recent destinations under the recent route.
        app.launchArguments += ["-sh2.map.recentDestinations", Self.recentDestinations]
        relaunch()
        guard tap(app.buttons["Search a place or a route"], "search-pill") else { return }
        pause(3)
        shot("02-search")
    }

    func test2_Routes() {
        launch()
        guard openDemoRoute() else { return }
        pause(4)
        shot("05-route-detail")
        guard tap(app.buttons["View the route in 3D"], "route-3d") else { return }
        pause(10)
        shot("06-route-3d")
    }

    func test3_Navigation() {
        launch()
        guard openDemoRoute(), tap(app.buttons["NAVIGATE"], "navigate") else { return }
        pause(8)
        shot("07-navigating")
        pause(270)              // the demo rider reaches the first turn
        shot("08-navigating-later")
        XCUIDevice.shared.press(.home)
        pause(3)
        shot("09-live-activity", from: XCUIScreen.main.screenshot())
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        pause(4)
        shot("09-lock-screen", from: XCUIScreen.main.screenshot())
    }

    func test4_HaloAndSettings() {
        launch()
        guard tap(app.tabBars.buttons["Halo"], "tab-halo") else { return }
        pause(4)
        shot("10-halo")
        guard tap(app.buttons["Ring cards"], "section-cards") else { return }
        pause(2)
        shot("11-halo-cards")
        guard tap(app.buttons["Taps"], "section-taps") else { return }
        pause(2)
        shot("12-halo-taps")
        guard tap(app.buttons["Settings"], "settings") else { return }
        pause(2)
        shot("13-settings")
        app.swipeUp()
        pause(1)
        shot("14-settings-alerts")
    }

    // MARK: - Helpers

    private func launch() {
        app.launch()
        allowSystemAlerts()
        pause(2)                // past the boot sweep
    }

    private func relaunch() {
        app.terminate()
        launch()
    }

    /// First keyboard use on a fresh simulator shows the slide-to-type tip over the sheet.
    private func dismissKeyboardTip() {
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 4) { tip.tap() }
    }

    /// Routes tab › the demo route, added from the Map's search on the first walk.
    private func openDemoRoute() -> Bool {
        guard tap(app.tabBars.buttons["Routes"], "tab-routes") else { return false }
        pause(2)
        shot("04-routes")
        return tap(app.buttons.containing(.staticText, identifier: "Demo route · City centre").firstMatch,
                   "demo-route-row")
    }

    private func allowSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 2) { button.tap() }
        }
    }

    @discardableResult
    private func tap(_ element: XCUIElement, _ name: String) -> Bool {
        guard element.waitForExistence(timeout: 12) else {
            let tree = app.debugDescription
            try? tree.write(to: Self.outputDir.appendingPathComponent("missing-\(name).txt"),
                            atomically: true, encoding: .utf8)
            XCTFail("Missing element: \(name)")
            return false
        }
        element.tap()
        return true
    }

    private func shot(_ name: String, from screenshot: XCUIScreenshot? = nil) {
        let png = (screenshot ?? app.screenshot()).pngRepresentation
        try? png.write(to: Self.outputDir.appendingPathComponent("\(name).png"))
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}
