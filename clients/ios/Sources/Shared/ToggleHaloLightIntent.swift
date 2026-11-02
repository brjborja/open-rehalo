import Foundation
import AppIntents

/// Light button of the navigation Live Activity (UX_DESIGN §4.8).
///
/// A `LiveActivityIntent` always runs in the APP's process (never in the widget extension), so it
/// can use the open BLE session. The type is compiled into both targets (`Sources/Shared/`) so the
/// extension can reference it from `Button(intent:)`; only the app build (`HALO_APP` compilation
/// condition, set in `project.yml`) has a real `perform()`.
struct ToggleHaloLightIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle the Halo front light"
    static var description = IntentDescription("Turns the SmartHalo front light on or off during navigation.")
    static var isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        #if HALO_APP
        await LiveActivityManager.toggleLightFromIntent()
        #endif
        return .result()
    }
}
